# Deploying

OmniNix builds ordinary `nixosConfigurations` and `darwinConfigurations`, so
anything that deploys those works unchanged.

## Before the first deploy

- **Passwords.** Don't deploy with `omninix.allowInsecureBootstrap` still on.
- **sops keys.** A host decrypts with its SSH host key, so its age recipient
  must be in `.sops.yaml`, and the secrets re-encrypted, before it can read
  them ([Passwords and secrets](secrets.md#keys)).
- **Impermanence.** Seed `/persist` (at least `/persist/etc/ssh`) before
  turning on `roles.impermanent` ([the rollout](impermanence.md#rolling-it-out-on-a-running-machine)).

## On the machine

```bash
sudo nixos-rebuild switch --flake .#laptop
```

For changes that touch boot-time state, such as the SSH host keys moving into
`/persist`, prefer `boot` and a reboot to a live `switch`.

## Over SSH

Build locally, switch a remote machine:

```bash
nixos-rebuild switch --flake .#web --target-host admin@web.lan --sudo --ask-sudo-password
```

`admin` needs `sudo` there:

```nix
# hosts/web/default.nix
omninix.hostUsers.admin = {
  enable = true;
  extraGroups = ["wheel"];
};
```

Add `--build-host admin@web.lan` to build on the target, e.g. from a laptop to
an aarch64 server.

## Pull-based, with comin

[comin](https://github.com/nlewo/comin) runs on each host, pulls your flake's
branch and switches to it. Hosts deploy themselves on every push:

```nix
# flake.nix
omninix.extraNixosModules.comin = inputs.comin.nixosModules.comin;
```

```nix
# a role, or modules/nixos/internal/comin.nix
services.comin = {
  enable = true;
  remotes = [
    {
      name = "origin";
      url = "https://github.com/you/my-fleet";
      branches.main.name = "main";
    }
  ];
};
```

comin switches live, so a change best applied with `boot` and a reboot (like
the one above) is best done by hand on each host **before** pushing it: comin
then finds the host already up to date.

## deploy-rs

[deploy-rs](https://github.com/serokell/deploy-rs) adds parallel deploys and
rolls back a switch that cuts off SSH:

```nix
inputs.deploy-rs = {
  url = "github:serokell/deploy-rs";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

```nix
# next to the omninix block in flake.nix
flake.deploy.nodes.web = {
  hostname = "web.lan";
  sshUser = "admin";
  profiles.system = {
    user = "root";
    path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.web;
  };
};
```

```bash
nix run github:serokell/deploy-rs -- .#web
```

The system in `deploy-rs.lib.<system>` must match the host's.

## Macs

Macs are switched on the Mac: see [Macs](macs.md#adding-one).
