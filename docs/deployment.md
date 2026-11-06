# Deploying to your machines

OmniNix builds ordinary `nixosConfigurations` and `darwinConfigurations`, so
anything that deploys those works unchanged. Two common setups for NixOS hosts,
then Macs:

## nixos-rebuild over SSH

No extra inputs. Build locally and switch a remote machine:

```bash
nixos-rebuild switch --flake .#web --target-host admin@web.lan --sudo --ask-sudo-password
```

`admin` must be able to `sudo` on the target, so give it `wheel` there:

```nix
# hosts/web/default.nix
omninix.hostUsers.admin = {
  enable = true;
  extraGroups = ["wheel"];
};
```

Add `--build-host admin@web.lan` to build on the target instead, for example
when deploying from a laptop to an aarch64 server.

## deploy-rs

[deploy-rs](https://github.com/serokell/deploy-rs) adds parallel deploys and
automatic rollback when a switch cuts off SSH. Add the input:

```nix
inputs.deploy-rs = {
  url = "github:serokell/deploy-rs";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Then describe each node next to the `omninix` block:

```nix
outputs = {self, flake-parts, omninix, ...} @ inputs:
  flake-parts.lib.mkFlake {inherit inputs;} {
    imports = [omninix.flakeModules.default];
    systems = ["x86_64-linux"];
    omninix = { /* … */ };

    flake.deploy.nodes.web = {
      hostname = "web.lan";
      sshUser = "admin";
      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.web;
      };
    };

    # `nix flake check` then validates the deploy definitions too.
    perSystem = {system, ...}: {
      checks = inputs.deploy-rs.lib.${system}.deployChecks self.deploy;
    };
  };
```

```bash
nix run github:serokell/deploy-rs -- .#web
```

The architecture in `deploy-rs.lib.<system>` must match the host's (its
`hostSystems` entry, or `defaultSystem`).

## Macs

Mac hosts (`darwinConfigurations`) are switched on the Mac itself. The first
time, before `darwin-rebuild` is installed:

```bash
sudo nix run nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake .#macbook
```

and afterwards:

```bash
sudo darwin-rebuild switch --flake .#macbook
```

nix-darwin recommends the `nixpkgs-26.05-darwin` branch for Macs. To use it
without moving your NixOS hosts, point the Macs at it with `hostInputs`:

```nix
inputs.nixpkgs-darwin.url = "github:nixos/nixpkgs?ref=nixpkgs-26.05-darwin";
inputs.nix-darwin = {
  url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
  inputs.nixpkgs.follows = "nixpkgs-darwin";
};

omninix.hostInputs.macbook.nixpkgs = inputs.nixpkgs-darwin;
```

## Before the first deploy

- **Passwords (NixOS).** A host whose active users have no password doesn't build (see
  [Passwords and secrets](secrets.md)). Don't deploy with
  `omninix.allowInsecureBootstrap` still on.
- **sops-nix keys.** The target decrypts with its SSH host key, so its age
  recipient must be in `.sops.yaml` and the secrets re-encrypted before it can
  read them.
- **Impermanence.** Seed `/persist` (at least `/persist/etc/ssh`) before turning
  on the root wipe. [The guide](impermanence.md) covers a safe rollout.
