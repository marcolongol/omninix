# OmniNix

A small Nix library for running a fleet of NixOS machines and Home Manager users
from a few plain directories: **hosts**, **roles**, **users** and **profiles**.
Secure defaults included.

```bash
nix flake init -t github:marcolongol/omninix
```

## What it looks like

```
my-fleet/
├── flake.nix                   # inputs + one omninix block
├── hosts/laptop/default.nix    # which machine, which roles, who logs in
├── roles/docker.nix            # what a machine does   (roles.docker.enable)
├── users/alice/default.nix     # who uses it            (also works without NixOS)
└── profiles/developer.nix      # how they like it      (profiles.developer.enable)
```

Drop a file in one of those directories and OmniNix picks it up. No list to keep
in sync, no special syntax: every file is an ordinary NixOS or Home Manager
module.

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    omninix = {
      url = "github:marcolongol/omninix";
      inputs.flake-parts.follows = "flake-parts";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {flake-parts, omninix, ...} @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [omninix.flakeModules.default];
      systems = ["x86_64-linux"];

      omninix = {
        hostsDir = ./hosts;
        rolesDir = ./roles;
        usersDir = ./users;
        profilesDir = ./profiles;
      };
    };
}
```

```nix
# hosts/laptop/default.nix
{
  system.stateVersion = "26.05";
  imports = [./hardware-config.nix];

  roles.docker.enable = true;

  omninix.hostUsers.alice = {
    enable = true;
    extraGroups = ["wheel" "docker"]; # privileged groups are always opt-in
  };
}
```

That's a complete fleet: `nixosConfigurations.laptop` for the machine and
`homeConfigurations.alice` for Alice's environment anywhere else.

## Quick start

1. **Scaffold** a full example (host, roles, user, profile, secrets):
   ```bash
   mkdir my-fleet && cd my-fleet
   nix flake init -t github:marcolongol/omninix
   ```
2. **Make it your machine.** Rename the host and generate its hardware config:
   ```bash
   mv hosts/example-host hosts/laptop
   nixos-generate-config --show-hardware-config > hosts/laptop/hardware-config.nix
   ```
3. **Make it yours.** Rename `users/example-user` to your username, set your git
   name and email in it, and enable it on the host with
   `omninix.hostUsers.<you>.enable = true;`.
4. **Set a password.** OmniNix refuses to build a host where an active user has
   no password, so a typo can't ship a machine nobody can log in to. See
   [Passwords and secrets](docs/secrets.md). For the very first install only,
   `omninix.allowInsecureBootstrap = true;` lets you build without one.
5. **Build and switch:**
   ```bash
   sudo nixos-rebuild switch --flake .#laptop
   ```

From here on, adding something is "write a module, flip a flag".

## How it fits together

| Directory | Is a… | Answers | Turned on with |
|---|---|---|---|
| `hosts/` | NixOS module | which machine is this? | one file or `<name>/default.nix` per host |
| `roles/` | NixOS module | what does it do? | `roles.<name>.enable = true;` on a host |
| `users/` | Home Manager module | who is this person? | `omninix.hostUsers.<name>.enable = true;` on a host |
| `profiles/` | Home Manager module | how do they like it? | `profiles.<name>.enable = true;` in a user |

Every role and profile is imported everywhere and switches itself on with its
own `enable` option, so a typo in a role name is an evaluation error, not a
silently ignored setting.

### Roles

```nix
# roles/docker.nix
{config, lib, pkgs, ...}: {
  options.roles.docker.enable = lib.mkEnableOption "Docker";
  config = lib.mkIf config.roles.docker.enable {
    virtualisation.docker.enable = true;
    environment.systemPackages = [pkgs.docker-compose];
  };
}
```

A role can also be a directory with a `default.nix`, if it outgrows one file.

### Users and profiles

```nix
# users/alice/default.nix
{
  home.stateVersion = "26.05";
  profiles.developer.enable = true;
  programs.git.settings.user = {name = "Alice"; email = "alice@example.com";};
}
```

```nix
# profiles/developer.nix
{config, lib, pkgs, ...}: {
  options.profiles.developer.enable = lib.mkEnableOption "developer tools";
  config = lib.mkIf config.profiles.developer.enable {
    home.packages = with pkgs; [kubectl k9s];
    programs.direnv.enable = true;
  };
}
```

🏠 The same user file builds two ways: as part of every host that enables the
user, and on its own for a machine without NixOS:

```bash
home-manager switch --flake .#alice
```

### Roles with a home side

Some features need both halves. A desktop needs a compositor and audio on the
system **and** a terminal and browser config for each user. Instead of a role
plus a matching profile that must always agree, let the role ship its Home
Manager half:

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

`roles/desktop/home.nix` is a plain Home Manager module with no `enable` option.
One host flag now drives both halves. Use a profile instead when users should
opt in individually.

### Per-user settings on a host

`config.omninix.activeUsers` lists the users enabled on the host:

```nix
home-manager.users = lib.genAttrs config.omninix.activeUsers (_: {
  wayland.windowManager.sway.config.output."*".scale = "1.5";
});
```

## Secure by default 🔐

These hold no matter how you build the flake:

- **No privileged groups by default.** `wheel`, `docker` and friends are granted
  per user with `extraGroups`, never implicitly.
- **No password, no build.** A host with an active user and no password fails
  to evaluate, with a message saying how to fix it.
- **Unfree software is off** until you set `omninix.allowUnfree = true;`.

## Guides

- [Passwords and secrets](docs/secrets.md): sops-nix wiring, or bring your own
  (agenix, plain hashes).
- [Impermanence and root wipe](docs/impermanence.md): keep state in `/persist`,
  wipe the rest on every boot, and roll it out safely.
- [Packages and overlays](docs/packages-and-overlays.md): your own packages as
  `pkgs.<name>`, and overriding nixpkgs.
- [Third-party modules](docs/third-party-modules.md): disko, stylix,
  nixos-hardware and friends, per host or fleet-wide.
- [Reference](docs/reference.md): every option, the shipped roles and profiles,
  the library functions, and using OmniNix without flake-parts.

## Scaffolding

Templates for single pieces, copied with the Nix CLI:

```bash
nix flake new -t github:marcolongol/omninix#host    hosts/laptop
nix flake new -t github:marcolongol/omninix#role    roles/webserver
nix flake new -t github:marcolongol/omninix#user    users/alice
nix flake new -t github:marcolongol/omninix#profile profiles/desktop
```

Rename the placeholder `enable` option to match the directory afterwards.

## Scope

OmniNix targets a **Linux NixOS + Home Manager fleet**: organized, composable and
safe to deploy. It deliberately doesn't try to describe one feature across NixOS,
Darwin and other module systems at once. If you need that, look at an
aspect-oriented framework such as [den](https://github.com/denful/den).

Everything is the stock NixOS module system (options, `mkIf`, merging,
assertions), so nothing here is new to learn beyond the directory layout.

## Status

Maturing from a personal config into a reusable library; the surface documented
here is the committed API. Planned:

- `nixosModules.default` / `homeModules.default`, so the secure module can be
  used without the builders.
- A migration guide from a hand-rolled NixOS config.

Feedback and ideas are welcome in the issues.

## License

MIT
