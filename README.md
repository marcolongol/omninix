# OmniNix

A small Nix library for running a fleet of NixOS machines, Macs and Home Manager
users from a few plain directories: **hosts**, **roles**, **users** and **profiles**.
Secure defaults included.

```bash
nix flake init -t github:marcolongol/omninix
```

Documentation: **[marcolongol.github.io/omninix](https://marcolongol.github.io/omninix)**

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
| `hosts/` | NixOS or nix-darwin module | which machine is this? | one file or `<name>/default.nix` per host |
| `roles/` | NixOS module (plus a `darwin.nix` for Macs) | what does it do? | `roles.<name>.enable = true;` on a host |
| `users/` | Home Manager module | who is this person? | `omninix.hostUsers.<name>.enable = true;` on a host |
| `profiles/` | Home Manager module | how do they like it? | `profiles.<name>.enable = true;` in a user |

Every role and profile is imported everywhere and switches itself on with its
own `enable` option, so a typo in a role name is an evaluation error, not a
silently ignored setting.

For code that isn't a toggle, there are module directories:
`nixosModulesDir`, `darwinModulesDir` and `homeManagerModulesDir`. They hold
always-on modules and option libraries, such as a module declaring
`services.surfshark`, and are exported as the standard `nixosModules`,
`darwinModules` and `homeModules` flake outputs, so any flake can use them. Roles and profiles say what a host or user *is*; module
directories hold what they're built from.

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

That includes macOS: set `userSystems.alice = "aarch64-darwin";` and the home
lands in `/Users/alice`.

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

### Mac hosts

A host whose system is darwin is built with nix-darwin, as
`darwinConfigurations.<name>`. Add the `nix-darwin` input and mark the host:

```nix
omninix.hostSystems.macbook = "aarch64-darwin";
```

`nix flake new -t github:marcolongol/omninix#darwin-host hosts/macbook`
scaffolds one. Users and profiles work unchanged. A role gets its Mac half from
a `darwin.nix` next to its `default.nix`:

```
roles/desktop/
├── default.nix   NixOS
├── darwin.nix    macOS
└── home.nix      both, through home-manager.sharedModules
```

Both halves declare the same `roles.desktop.enable`, so one flag works on either
kind of host. A role directory with only a `darwin.nix` is macOS only.

### Per-user settings on a host

`config.omninix.activeUsers` lists the users enabled on the host:

```nix
home-manager.users = lib.genAttrs config.omninix.activeUsers (_: {
  wayland.windowManager.sway.config.output."*".scale = "1.5";
});
```

## Secure by default 🔐

On NixOS hosts, these hold no matter how you build the flake:

- **No privileged groups by default.** `wheel`, `docker` and friends are granted
  per user with `extraGroups`, never implicitly.
- **No password, no build.** A host with an active user and no password fails
  to evaluate, with a message saying how to fix it.
- **Unfree software is off** until you set `omninix.allowUnfree = true;`.

Not using the builders? `omninix.nixosModules.default` brings the same
guarantees to any `nixosSystem` ([details](docs/reference.md#just-the-modules)).

On Macs, macOS manages passwords and groups itself, so the first two don't
apply. OmniNix doesn't create macOS accounts, and `extraGroups` on a Mac host
is an error rather than silently ignored.

## Guides

- [Migrating a hand-rolled config](docs/migrating.md): move an existing flake
  over one host at a time, and prove nothing changed.
- [Passwords and secrets](docs/secrets.md): sops-nix wiring, or bring your own
  (agenix, plain hashes).
- [Impermanence and root wipe](docs/impermanence.md): keep state in `/persist`,
  wipe the rest on every boot, and roll it out safely.
- [Packages and overlays](docs/packages-and-overlays.md): your own packages as
  `pkgs.<name>`, overriding nixpkgs, and a different nixpkgs per host.
- [Third-party modules](docs/third-party-modules.md): disko, stylix,
  nixos-hardware and friends, per host or fleet-wide.
- [Deploying](docs/deployment.md): `nixos-rebuild --target-host` and deploy-rs.
- [Sharing roles, profiles and modules](docs/sharing.md): use other flakes'
  pieces, write shareable ones, and the check that proves it.
- [Reference](docs/reference.md): outputs, the standalone modules, and the
  option pages for the flake, hosts, users and shipped roles and profiles.

## Scaffolding

Templates for single pieces, copied with the Nix CLI:

```bash
nix flake new -t github:marcolongol/omninix#host        hosts/laptop
nix flake new -t github:marcolongol/omninix#darwin-host hosts/macbook
nix flake new -t github:marcolongol/omninix#role        roles/webserver
nix flake new -t github:marcolongol/omninix#user        users/alice
nix flake new -t github:marcolongol/omninix#profile     profiles/desktop
```

Rename the placeholder `enable` option to match the directory afterwards.

## Scope and alternatives

OmniNix targets a **fleet of NixOS machines and Macs with Home Manager users**:
organized, composable and safe to deploy. Everything is the stock module system
(options, `mkIf`, merging, assertions), so nothing here is new to learn beyond
the directory layout.

Other projects may fit better:

- **[Blueprint](https://github.com/numtide/blueprint)**: folders mapped straight
  to flake outputs, with no module layer of its own. Lighter. Its docs don't
  cover secrets or user defaults.
- **[Clan](https://clan.lol)**: a full fleet manager with an inventory, built-in
  secrets, and install and update commands. Much more opinionated, with its
  own model to adopt.
- **[den](https://github.com/denful/den)**: aspect-oriented. One feature
  described once across NixOS, nix-darwin and Home Manager.
- **[Snowfall Lib](https://github.com/snowfallorg/lib)**: directory conventions
  for systems, homes, modules and packages, with nix-darwin hosts, on its own
  `mkFlake`. Its code hasn't changed since December 2025, and its README asks
  for new maintainers.

Choose OmniNix for plain modules on flake-parts, with safe user defaults and
tests that boot real machines.

## Status

Not released yet: `main` may change without notice. Tested against the current
NixOS stable release and nixos-unstable, plus nix-darwin hosts and standalone
Home Manager on Linux and macOS.

Feedback and ideas are welcome in the issues.

## License

MIT
