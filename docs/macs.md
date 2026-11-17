# Macs

A host whose system is darwin is built with
[nix-darwin](https://github.com/nix-darwin/nix-darwin), from the same
directories, as `darwinConfigurations.<name>`.

## Adding one

```nix
# flake.nix
inputs.nix-darwin = {
  url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
  inputs.nixpkgs.follows = "nixpkgs";
};

omninix.hostSystems.macbook = "aarch64-darwin";
```

```bash
nix flake new -t github:marcolongol/omninix#darwin-host hosts/macbook
```

```nix
# hosts/macbook/default.nix
{
  system.stateVersion = 7; # nix-darwin's own numbering
  omninix.hostUsers.alice.enable = true;
}
```

The first time, on the Mac (before `darwin-rebuild` is installed):

```bash
sudo nix run nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake .#macbook
```

Afterwards, `sudo darwin-rebuild switch --flake .#macbook`.

## What's different from NixOS

- **Accounts already exist.** OmniNix doesn't create macOS accounts:
  `hostUsers` says which existing ones get a Home Manager home, in
  `/Users/<name>`. With exactly one active user, `system.primaryUser` defaults
  to them.
- **No password rule, no groups.** macOS manages both. Setting `extraGroups`
  on a Mac is an error.
- **Roles have a Mac half.** A role directory may hold a `darwin.nix` next to
  its `default.nix`; Macs get `darwin.nix`, NixOS hosts `default.nix`. Both
  declare the same `roles.<name>.enable`:

  ```
  roles/desktop/
  ├── default.nix   NixOS
  ├── darwin.nix    macOS
  └── home.nix      both, through home-manager.sharedModules
  ```

  A role file (`roles/docker.nix`), or a role with only `default.nix`,
  doesn't exist on Macs. One with only `darwin.nix` is macOS only.
- **Always-on modules** come from `omninix.darwinModulesDir`.
- **Secrets:** `secrets/<host>.yaml` and `secrets/shared.yaml` work as on
  NixOS; there are no password secrets.

Users and profiles work unchanged.

## Packages

Macs are built from the flake's `nixpkgs`, with your packages and overlays,
like NixOS hosts. nix-darwin recommends the `nixpkgs-26.05-darwin` branch for
Macs; to use it without moving your NixOS hosts, give the Macs their own
input:

```nix
inputs.nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-26.05-darwin";

omninix.hostInputs.macbook.nixpkgs = inputs.nixpkgs-darwin;
```
