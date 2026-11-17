![OmniNix](docs/assets/banner.png)

# OmniNix

Run a fleet of NixOS machines, Macs and Home Manager users from a few plain
directories: **hosts**, **users**, **roles** and **profiles**. Secure defaults
included.

```bash
nix flake init -t github:marcolongol/omninix
```

Documentation: **[marcolongol.github.io/omninix](https://marcolongol.github.io/omninix)**

## What it looks like

```
my-fleet/
├── flake.nix              # inputs and one omninix block
├── hosts/laptop/          # a machine: becomes nixosConfigurations.laptop
├── users/alice.nix        # a person's Home Manager config
├── roles/docker.nix       # what a machine does      (roles.docker.enable)
└── profiles/developer.nix # how a person likes it    (profiles.developer.enable)
```

Drop a file in one of those directories and it's part of the fleet. Every file
is an ordinary NixOS or Home Manager module; there's no list to keep in sync
and no new syntax.

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    omninix = {
      url = "github:marcolongol/omninix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
  };

  outputs = {flake-parts, omninix, ...} @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [omninix.flakeModules.default];
      systems = ["x86_64-linux"];

      omninix = {
        hostsDir = ./hosts;
        usersDir = ./users;
        rolesDir = ./roles;
        profilesDir = ./profiles;
      };
    };
}
```

```nix
# hosts/laptop/default.nix
{
  imports = [./hardware-configuration.nix];
  system.stateVersion = "26.05";

  roles.docker.enable = true;

  omninix.hostUsers.alice = {
    enable = true;
    extraGroups = ["wheel" "docker"]; # privileged groups are always opt-in
  };
}
```

That's a fleet: `nixosConfigurations.laptop` (hostname `laptop`, from the
directory), with Alice's home on it, and `homeConfigurations.alice` for her
environment on any other machine.

## Add a piece

Every piece has a template, so growing the fleet is one command:

```bash
nix flake new -t github:marcolongol/omninix#host        hosts/server
nix flake new -t github:marcolongol/omninix#darwin-host hosts/macbook
nix flake new -t github:marcolongol/omninix#user        users/bob
nix flake new -t github:marcolongol/omninix#role        roles/webserver
nix flake new -t github:marcolongol/omninix#profile     profiles/gaming
```

The directory you give is the piece's name: `hosts/server` is a host called
`server`. There's nothing to register; it's part of the fleet as soon as it
exists.

## Secure by default

- **No password, no build.** A host where an active user has no password
  doesn't evaluate, and the error says how to fix it.
- **No privileged groups by default.** `wheel`, `docker` and friends are
  granted per user, never implicitly.
- **Accounts come from the config.** A password changed in your secrets
  reaches the machine on the next switch.
- **Unfree software is off** until you turn it on.

## Guides

1. [Getting started](docs/getting-started.md): from the template to a first switch.
2. [Hosts, users, roles and profiles](docs/pieces.md): how a fleet is put together.
3. [Macs](docs/macs.md): nix-darwin hosts from the same directories.
4. [Passwords and secrets](docs/secrets.md): sops-nix by convention, or your own.
5. [Impermanence and root wipe](docs/impermanence.md): keep `/persist`, wipe the rest.
6. [Packages, overlays and inputs](docs/packages.md): your packages everywhere, a different nixpkgs per host.
7. [Sharing between flakes](docs/sharing.md): use other fleets' roles and profiles, and share yours.
8. [Third-party modules](docs/third-party-modules.md): disko, stylix and the rest.
9. [Deploying](docs/deployment.md): over SSH, with comin, or deploy-rs.
10. [Migrating an existing flake](docs/migrating.md): one host at a time, proving nothing changed.

[Reference](docs/reference.md): outputs, defaults, and every option.

## Scope and alternatives

OmniNix is for a **fleet of NixOS machines and Macs with Home Manager users**,
on flake-parts. Everything is the stock module system (options, `mkIf`,
merging, assertions), so there's nothing to learn beyond the directory layout.

If you're coming from Ansible, the layout will feel familiar: hosts are your
inventory and roles are your roles. The difference is that each machine is
built from a full description of itself instead of a playbook run against it,
which is what got me here.

Other projects may fit better:

- **[Blueprint](https://github.com/numtide/blueprint)**: folders mapped straight
  to flake outputs, with no module layer of its own. Lighter.
- **[Clan](https://clan.lol)**: a full fleet manager with an inventory, built-in
  secrets, and install and update commands. More opinionated, with its own
  model to adopt.
- **[den](https://github.com/denful/den)**: aspect-oriented. One feature
  described once across NixOS, nix-darwin and Home Manager.
- **[Snowfall Lib](https://github.com/snowfallorg/lib)**: directory conventions
  for systems, homes, modules and packages, on its own `mkFlake`.

## Status

Not released yet: `main` may change without notice. Tested against the current
NixOS stable release, with nix-darwin hosts and standalone Home Manager.
Feedback and ideas are welcome in the issues.

## License

MIT
