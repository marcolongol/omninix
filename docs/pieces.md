# Hosts, users, roles and profiles

A fleet is four directories. Each holds plain NixOS or Home Manager modules.

| Directory | Each file is | Becomes |
|---|---|---|
| `hostsDir` | a NixOS (or nix-darwin) module | a machine: `nixosConfigurations.<name>` |
| `usersDir` | a Home Manager module | a person's home on every host that enables them, and `homeConfigurations.<name>` |
| `rolesDir` | a NixOS module | imported by every host, off until a host turns it on |
| `profilesDir` | a Home Manager module | imported by every home, off until a user turns it on |

## What counts as a piece

In any of these directories, a piece is either `<name>.nix` or a directory
`<name>/` with a `default.nix`. Its name is the file or directory name.
Anything else (READMEs, `.gitkeep`, directories without `default.nix`) is
ignored, so you can keep notes next to your modules. A file and a directory
with the same name are an error.

## Hosts

```bash
nix flake new -t github:marcolongol/omninix#host hosts/laptop
```

```nix
# hosts/laptop/default.nix
{
  imports = [./hardware-configuration.nix];
  system.stateVersion = "26.05";

  roles.docker.enable = true;
  omninix.hostUsers.alice = {
    enable = true;
    extraGroups = ["wheel"];
  };
}
```

OmniNix sets, and the host can override:

- `networking.hostName` to the host's name;
- `nixpkgs.hostPlatform` to `omninix.hostSystems.<name>`, or
  `omninix.defaultSystem` (`x86_64-linux`). If your
  `hardware-configuration.nix` says a different platform, the build stops with
  a conflict instead of picking one.

Host files receive `hostName` and `inputs` (your flake's inputs) as arguments.

## Users

```bash
nix flake new -t github:marcolongol/omninix#user users/alice
```

```nix
# users/alice/default.nix (or users/alice.nix)
{pkgs, ...}: {
  profiles.developer.enable = true;
  home.packages = [pkgs.ripgrep];
  programs.git.settings.user = {
    name = "Alice";
    email = "alice@example.com";
  };
}
```

A host turns a user on with `omninix.hostUsers.<name>.enable`. On NixOS, the
user gets a normal account with **no groups** beyond what you list:

```nix
omninix.hostUsers.alice.extraGroups = ["wheel" "docker"]; # per user
omninix.defaultUserGroups = ["networkmanager"];           # every user on this host
```

Every active user gets a Home Manager home (with the `home-manager` input),
built from their file when they have one. Homes share the host's packages and
install into the user's profile. `home.stateVersion` defaults to `"26.05"`;
set it in the user file to keep an older one.

The same file also builds on its own, for a machine without NixOS:

```bash
home-manager switch --flake .#alice
```

`omninix.userSystems.alice = "aarch64-darwin";` builds that one for a Mac
(home in `/Users/alice`).

Accounts and passwords come from the config alone: `users.mutableUsers`
defaults to `false` on hosts with active users, and every active user needs a
password ([Passwords and secrets](secrets.md)).

## Roles

A role says what a machine does. It declares its own switch:

```bash
nix flake new -t github:marcolongol/omninix#role roles/docker
```

Rename the template's `myrole` to the directory's name, then:

```nix
# roles/docker/default.nix (or roles/docker.nix)
{config, lib, pkgs, ...}: {
  options.roles.docker.enable = lib.mkEnableOption "Docker";

  config = lib.mkIf config.roles.docker.enable {
    virtualisation.docker.enable = true;
    environment.systemPackages = [pkgs.docker-compose];
  };
}
```

Every host imports every role, so a misspelt `roles.dokcer.enable` is an error,
not a silently ignored setting. A role can declare more options, and read the
rest of the config:

```nix
# add every active user to the docker group
users.users = lib.genAttrs config.omninix.activeUsers (_: {extraGroups = ["docker"];});
```

`config.omninix.activeUsers` lists the users enabled on the host.

### A role with a home side

When a feature has both halves (a desktop needs a compositor *and* each
user's terminal config), let the role ship the Home Manager half:

```nix
# roles/desktop/default.nix
{config, lib, ...}: {
  options.roles.desktop.enable = lib.mkEnableOption "desktop";

  config = lib.mkIf config.roles.desktop.enable {
    programs.sway.enable = true;
    home-manager.sharedModules = [./home.nix]; # every user on this host
  };
}
```

`roles/desktop/home.nix` is a plain Home Manager module. One host flag drives
both halves. Use a profile instead when each user should opt in.

## Profiles

A profile says how a person likes their environment. Same shape as a role, in
Home Manager:

```bash
nix flake new -t github:marcolongol/omninix#profile profiles/developer
```

```nix
# profiles/developer/default.nix (or profiles/developer.nix)
{config, lib, pkgs, ...}: {
  options.profiles.developer.enable = lib.mkEnableOption "developer tools";

  config = lib.mkIf config.profiles.developer.enable {
    home.packages = [pkgs.kubectl pkgs.k9s];
    programs.direnv.enable = true;
  };
}
```

A user turns it on with `profiles.developer.enable = true;`.

## Always-on modules

For code that isn't a toggle, such as a module declaring options other pieces
set, or settings every machine gets:

```nix
omninix = {
  nixosModulesDir = ./modules/nixos; # every NixOS host
  homeModulesDir = ./modules/home;   # every home
  darwinModulesDir = ./modules/darwin; # every Mac
};
```

These are exported as your flake's `nixosModules`, `homeModules` and
`darwinModules`, like roles and profiles are exported as `roles` and
`profiles`. Anything in an `internal/` subdirectory is used but not exported:
see [Sharing between flakes](sharing.md).

## When something's wrong

Setting mistakes are reported together, before anything is built:

```
error: OmniNix: hostSystems names unknown host(s): lpatop
OmniNix: secretsPath needs a sops-nix flake input
```

A host that's wrong in itself, like an active user without a password, fails
with NixOS's usual assertion message, starting with `OmniNix:`.
