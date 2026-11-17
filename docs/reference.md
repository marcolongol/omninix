# Reference

OmniNix is used through its flake module: import `omninix.flakeModules.default`
in a flake-parts flake and configure it under `omninix`. Every option, with
its type and default:

- [Flake options](https://marcolongol.github.io/omninix/options/flake.html): the `omninix = { … }` block
- [Host options (NixOS)](https://marcolongol.github.io/omninix/options/nixos.html)
- [Host options (nix-darwin)](https://marcolongol.github.io/omninix/options/darwin.html)
- [User options (Home Manager)](https://marcolongol.github.io/omninix/options/home.html)
- [Shipped roles](https://marcolongol.github.io/omninix/options/roles.html)

## What your flake gets

| Output | From |
|---|---|
| `nixosConfigurations.<host>` | each host whose system isn't darwin |
| `darwinConfigurations.<host>` | each host whose system is darwin ([Macs](macs.md)) |
| `homeConfigurations.<user>` | each user, standalone |
| `roles`, `profiles` | your `rolesDir`, `profilesDir` (not `internal/`) |
| `nixosModules`, `darwinModules`, `homeModules` | your module directories (not `internal/`) |
| `packages.<system>.<name>` | your `packagesDir`, where each builds |
| `overlays.packages` | your `packagesDir`, for other flakes |

Apart from `nixosConfigurations`, outputs that would be empty aren't set. Your own `flake.nixosModules.<name>`
replaces a discovered one of the same name.

## What every piece receives

| Argument | In | Is |
|---|---|---|
| `inputs` | every host, role, user, profile and module | your flake's inputs, with `hostInputs.<host>` or `userInputs.<user>` on top |
| `hostName` | NixOS and nix-darwin modules | the host's name |

## What OmniNix sets for you

All of these are defaults: set the option yourself to change it.

| Where | Setting | Value |
|---|---|---|
| every host | `networking.hostName` | the host's name |
| every host | `nixpkgs.hostPlatform` | `hostSystems.<host>` or `defaultSystem` |
| NixOS hosts with active users | `users.mutableUsers` | `false` |
| Macs with one active user | `system.primaryUser` | that user |
| every home | `home.stateVersion` | `"26.05"` |
| standalone homes | `home.username`, `home.homeDirectory` | the user's name; `/home/<name>`, `/Users/<name>` on darwin, `/root` |
| hosts with secrets | `sops.defaultSopsFile` | `secrets/<host>.yaml` |
| homes with secrets | `sops.defaultSopsFile` | `secrets/users/<user>.yaml` |

And always, with the `home-manager` input: `home-manager.useGlobalPkgs` and
`useUserPackages` are `true`.

## Inputs OmniNix needs

| Input | When |
|---|---|
| `home-manager` | you have users, profiles or home modules |
| `sops-nix` | you set `secretsPath` |
| `nix-darwin` | a host's system is darwin |

A missing one is reported with what to add.

## Shipped roles

Add them by name: `extraRoles = {inherit (omninix.roles) impermanent;};`.

- **`impermanent`**: an ephemeral root with a persistent `/persist`, and an
  optional btrfs root wipe ([Impermanence and root wipe](impermanence.md)).

## Templates

`nix flake init -t github:marcolongol/omninix` for a whole fleet, or
`nix flake new -t github:marcolongol/omninix#<template> <dir>` for one piece:
`host`, `darwin-host`, `user`, `role`, `profile`.
