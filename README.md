# OmniNix

> **A small Nix library for composing NixOS + Home Manager fleets from hosts, roles, users, and profiles — secure by default.**

OmniNix is **a library, not a framework**. It doesn't own your `flake.nix` or
hide your outputs behind a DSL. It gives you a handful of plain functions —
directory discovery, two config builders, and a secure-by-default NixOS/Home
Manager module — that you call from your own flake and assemble however you
like. On top of that sit two thin entry points: a **flake-parts module**
(`omninix.flakeModules.default`) for the common flake-parts setup, and a
batteries-included `mkFlake` function if you'd rather not use flake-parts. Both
run the same engine.

It stays **inside the NixOS module system** on purpose: roles and profiles are
ordinary modules gated by `enable` flags, so merging, options, types,
assertions, and `lib.mkIf` are the stock module system you already know — not
something OmniNix reimplements. That's why the whole library is ~900 lines.

```bash
nix flake init -t github:marcolongol/omninix   # scaffold a whole config
```

## What you get

- 🧩 **Four plain-module concepts** — hosts (what a machine *is*), roles (what it
  *does*), users (*who* uses it), profiles (*how* they like it). All ordinary
  NixOS/HM modules with `enable` flags.
- 🔎 **Directory discovery** — drop a `.nix` file in `roles/` and it's picked up.
  No registration, no central list.
- 🔐 **Secure by default** — fail-closed passwords, no privileged groups unless
  you opt in, unfree off by default. Enforced by the OmniNix module, so it holds
  whether you use the flake-parts module, `mkFlake`, or the builders themselves.
- 🏠 **One user file, two worlds** — each user builds both as a NixOS HM submodule
  and as a standalone `homeConfigurations.<name>` for non-NixOS machines.
- 💾 **Persistence aggregation** — the one piece of impermanence glue you can't
  do in userland: any role/host/user/profile drops paths into
  `omninix.persistence.*` and they flow to the right `/persist` store. Everything
  else is plain modules you import yourself.

## Scope (and what this is *not*)

OmniNix targets the common case: a **Linux NixOS + Home Manager fleet** you want
organized, composable, and safe to deploy. It deliberately does **not** try to
be a cross-platform feature engine — there's no single feature definition
spanning NixOS + Darwin + custom build classes, no aspect router, no implicit
cross-class conditioning. If you need *that*, reach for an aspect-oriented
framework like [den](https://github.com/denful/den); it's a different, heavier
bet. OmniNix's bet is that the system/user split plus the native module system
covers most fleets at a fraction of the machinery.

---

## Getting started

From nothing to a booting machine in five steps.

**1. Scaffold a config.** This drops a complete example flake — host, role,
user, profile, secrets — into the current directory:

```bash
mkdir my-fleet && cd my-fleet
nix flake init -t github:marcolongol/omninix
```

You get:

```
flake.nix            # flake-parts + omninix.flakeModules.default, wires inputs
hosts/example-host/  # default.nix + hardware-config.nix placeholder
roles/common.nix     # a starter system role
users/example-user/  # default.nix
profiles/common.nix  # a starter user profile
secrets/             # sops setup (.sops.yaml)
```

**2. Make it your machine.** Rename `hosts/example-host/` to your hostname and
generate real hardware config into it:

```bash
mv hosts/example-host hosts/laptop
nixos-generate-config --show-hardware-config > hosts/laptop/hardware-config.nix
```

Set the basics in `hosts/laptop/default.nix` — which roles it runs and who can
log in:

```nix
{
  system.stateVersion = "25.11";
  imports = [ ./hardware-config.nix ];
  boot.loader.systemd-boot.enable = true;

  roles.common.enable = true;

  omninix.hostUsers.alice = {
    enable = true;
    extraGroups = [ "wheel" ];   # opt-in sudo
  };
}
```

**3. Add yourself.** Rename `users/example-user/` to `alice` and edit
`users/alice/default.nix`:

```nix
{ pkgs, ... }: {
  home.stateVersion = "25.11";
  profiles.common.enable = true;
  programs.git.settings.user = { name = "Alice"; email = "alice@example.com"; };
}
```

**4. Give yourself a password.** OmniNix fails the build if an active user has
no password. Either encrypt one with sops…

```bash
# hashed-password: key inside secrets/users/alice.yaml (see secrets/.sops.yaml)
mkpasswd -m sha-512 | sops --set '["hashed-password"] "<paste>"' secrets/users/alice.yaml
```

…or, **for the very first boot only**, skip it:

```nix
# hosts/laptop/default.nix
omninix.allowInsecureBootstrap = true;   # remove once a password is set
```

**5. Build and switch.**

```bash
sudo nixos-rebuild switch --flake .#laptop
```

That's a running system. From here, adding capability is "write a module, flip a
flag": drop `roles/docker.nix`, set `roles.docker.enable = true;` on the host,
rebuild.

### Just my user environment (no NixOS)

On a work laptop or any non-NixOS box that already has Home Manager, the same
`users/alice` file works standalone — no host required:

```bash
home-manager switch --flake .#alice
```

---

## The library

Everything lives under `omninix.lib.omninix.*`. Pick the layer you want.

| Function | Type | What it does |
|---|---|---|
| `omninix.flakeModules.default` | flake-parts module | **The usual entry point.** Typed `omninix.*` options over the same engine as `mkFlake`; hosts/users/packages land in `flake.*` and `perSystem`. |
| `mkFlake inputs { … }` | `Inputs -> Attrs -> Outputs` | **Batteries-included, no flake-parts.** Discovers `hosts/roles/users/profiles`, builds everything, returns `nixosConfigurations`, `homeConfigurations`, and (optionally) `packages`. |
| `mkNixosConfigurations { … }` | `Attrs -> { host = system }` | Build NixOS systems yourself. Imports the secure OmniNix module + your roles. |
| `mkHomeConfigurations { … }` | `Attrs -> { user = hmConfig }` | Build standalone Home Manager configs for non-NixOS machines. |
| `mkHomeModules` | shared module set | The per-user HM module set, identical between the NixOS submodule and standalone paths. |
| `forAllNixFiles dir f` | `Path -> (Path -> a) -> Attrs` | Scan a directory: `.nix` files and `dir/default.nix` units become `{ name = f path; }`. |
| `mkDirMap { name = dir; }` | `Attrs -> Attrs` | `forAllNixFiles` over several directories at once. |
| `pick [ … ] attrs` | `[String] -> Attrs -> Attrs` | Cherry-pick named entries (e.g. roles from a shared library). Throws on a typo. |
| `drop [ … ] attrs` | `[String] -> Attrs -> Attrs` | Everything except the named entries. |

The flake also exposes `omninix.roles`, `omninix.profiles` (the shipped
library), `omninix.templates` (scaffolding), and `omninix.lib` (the nixpkgs lib
extended with the above).

### Path A — flake-parts module

Import the module into your flake-parts flake. Discovery and assembly come from
OmniNix; everything else (`perSystem`, other flake-parts modules) is yours:

```nix
{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    omninix = {
      url = "github:marcolongol/omninix";
      inputs.flake-parts.follows = "flake-parts";
    };
    # + nixpkgs, home-manager, sops-nix, … (see Dependencies)
  };

  outputs = { flake-parts, omninix, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ omninix.flakeModules.default ];
      systems = [ "x86_64-linux" "aarch64-linux" ]; # cover every host's system

      omninix = {
        hostsDir    = ./hosts;
        rolesDir    = ./roles;
        usersDir    = ./users;
        profilesDir = ./profiles;
        secretsPath = ./secrets;
        # hostSystems = { rpi = "aarch64-linux"; };  # per-host arch
        # allowUnfree = true;                         # off by default
      };

      perSystem = { pkgs, ... }: {
        formatter = pkgs.alejandra;
      };
    };
}
```

Notes:
- `perSystem`'s `pkgs` is OmniNix's: `overlaysDir`, `packagesDir` and
  `allowUnfree` applied, same as the hosts. To replace it, set
  `_module.args.pkgs` with a plain definition (or `mkForce`), not `mkDefault`.
- `packagesDir` packages land in `perSystem.packages`. A local
  `perSystem.packages.<name>` replaces only that output; hosts keep the
  `packagesDir` version as `pkgs.<name>`.
- The options are typed: a typo such as `omninix.hostDir` fails with the file
  location instead of being ignored.

### Path A′ — `mkFlake`, no flake-parts

The same engine as a plain function, if you don't want flake-parts:

```nix
{
  inputs.omninix.url = "github:marcolongol/omninix";
  # + nixpkgs, home-manager, sops-nix, … (see Dependencies)

  outputs = { omninix, ... }@inputs:
    omninix.lib.omninix.mkFlake inputs {
      hostsDir    = ./hosts;
      rolesDir    = ./roles;
      usersDir    = ./users;
      profilesDir = ./profiles;
      secretsPath = ./secrets;

      # hostSystems = { rpi = "aarch64-linux"; };    # per-host arch
      # allowUnfree = true;                           # off by default
    };
}
```

### Path B — à la carte

Keep your own flake structure (flake-parts, a hand-rolled `outputs`, whatever)
and call the builders directly. You stay in control of the outputs; OmniNix just
does the heavy lifting and still imports the secure-by-default module for you:

```nix
nixosConfigurations = omninix.lib.omninix.mkNixosConfigurations {
  inherit inputs;
  hosts    = omninix.lib.omninix.forAllNixFiles ./hosts (p: p);
  roles    = omninix.lib.omninix.forAllNixFiles ./roles (p: p);
  users    = omninix.lib.omninix.forAllNixFiles ./users (p: p);
  profiles = omninix.lib.omninix.forAllNixFiles ./profiles (p: p);
  secretsPath = ./secrets;
};
```

Mix freely: discover most roles from disk, then graft a few from a shared
library with `pick` / `drop`:

```nix
# only these from the library:
roles = omninix.lib.omninix.pick [ "docker" "nginx" ] omninix.roles;
# or the whole library except the ones you override locally:
roles = omninix.lib.omninix.drop [ "docker" ] omninix.roles;
```

---

## The four concepts

All four are plain modules. A role/profile is "always imported, self-declares
`options.<…>.enable`, gates its config with `lib.mkIf`." Turning it on is
`<name>.enable = true`.

### Hosts — what a machine *is*

```nix
# hosts/laptop/default.nix
{
  system.stateVersion = "25.11";
  imports = [ ./hardware-config.nix ];

  boot.loader.systemd-boot.enable = true;

  roles = { common.enable = true; docker.enable = true; };

  omninix.hostUsers.lucas = {
    enable = true;
    extraGroups = [ "wheel" "docker" ];   # sudo/docker are opt-in, never default
  };
}
```

`config.omninix.activeUsers` (read-only) lists the enabled users, so roles and
hosts can do per-user config without re-filtering `hostUsers`:

```nix
home-manager.users = lib.genAttrs config.omninix.activeUsers (_: {
  wayland.windowManager.hyprland.settings.monitor = [ ",preferred,auto,1" ];
});
```

### Roles — what it *does* (system level)

```nix
# roles/docker.nix
{ config, lib, pkgs, ... }: {
  options.roles.docker.enable = lib.mkEnableOption "Docker container runtime";
  config = lib.mkIf config.roles.docker.enable {
    virtualisation.docker = { enable = true; autoPrune.enable = true; };
    environment.systemPackages = [ pkgs.docker-compose ];
  };
}
```

OmniNix ships **no roles** — they're all yours. The template starts you with a
`common` role and an example `impermanent` role (see Impermanence below) to copy.

### Users — *who* uses it

```nix
# users/lucas/default.nix
{ pkgs, ... }: {
  home.stateVersion = "25.11";
  profiles = { common.enable = true; developer.enable = true; };

  programs.git.settings.user = { name = "Lucas"; email = "lucas@example.com"; };

  # persisted across reboots when impermanence is active (see Persistence below)
  omninix.persistence.directories = [ ".config/1Password" ];
}
```

This file builds both as the host's HM submodule **and** as
`homeConfigurations.lucas` for a non-NixOS box:
`home-manager switch --flake .#lucas`. (`username`/`homeDirectory`/`stateVersion`
default from the directory name and platform; override in the file.)

### Profiles — *how* they like it (user level)

```nix
# profiles/developer.nix
{ config, lib, pkgs, ... }: {
  options.profiles.developer.enable = lib.mkEnableOption "developer tools";
  config = lib.mkIf config.profiles.developer.enable {
    home.packages = with pkgs; [ kubectl k9s ];
    programs.direnv.enable = true;
    omninix.persistence.directories = [ ".claude" ];
  };
}
```

A role or profile can also be a **directory** with `default.nix` that imports
its siblings — discovery treats it as one unit, so you can split a big profile.

### Roles with a home side

Some capabilities live on both sides of the split: a desktop needs the
compositor, display manager and audio (system) *and* each user's bar, terminal
and browser config (home). Modelling that as a `desktop` role plus a
`desktop` profile means two flags that must agree — enable the profile on a
host without the role and you get config for a compositor that isn't there.

Instead, let the role ship its home half through Home Manager's
`sharedModules`:

```nix
# roles/desktop/default.nix
{ config, lib, inputs, ... }: {
  options.roles.desktop.enable = lib.mkEnableOption "Sway desktop";
  config = lib.mkIf config.roles.desktop.enable (lib.mkMerge [
    { programs.sway.enable = true; services.pipewire.enable = true; }
    (lib.optionalAttrs (inputs ? home-manager) {
      home-manager.sharedModules = [ ./home.nix ];
    })
  ]);
}
```

```nix
# roles/desktop/home.nix — plain HM module, no enable option
{ ... }: {
  programs.foot.enable = true;
  programs.firefox.enable = true;
  omninix.persistence.directories = [ ".mozilla" ];
}
```

One host flag now drives both halves, for every user on that host. Discovery
only looks at `roles/desktop/default.nix`, so `home.nix` is never imported as a
NixOS module. The template ships this as `roles/desktop/`.

Trade-offs: every HM user on the host gets the home half (no per-user opt-out
— use a profile when that matters), and standalone `homeConfigurations` don't
see it, since there's no host role there. Keep identity (git name, keys) in the
user file; the role's home half should be generic.

### Scaffolding

Templates are static file copies, scaffolded with the native CLI:

```bash
nix flake new -t github:marcolongol/omninix#host    hosts/laptop
nix flake new -t github:marcolongol/omninix#role    roles/webserver
nix flake new -t github:marcolongol/omninix#user    users/alice
nix flake new -t github:marcolongol/omninix#profile profiles/desktop
```

Rename the placeholder `enable` option to match the directory after scaffolding;
the skeleton says exactly what to change.

---

## Secure by default

The OmniNix NixOS module enforces these whether you use the flake-parts module,
`mkFlake`, or the builders directly:

- **No privileged groups by default.** Active users get only
  `omninix.defaultUserGroups` (empty). Grant `wheel`/`docker` per user via
  `extraGroups`, or per host via `omninix.defaultUserGroups`.
- **Fail-closed passwords.** The build **errors** if an active user has no
  password (sops secret, `hashedPassword`, …). First install only: opt out with
  `omninix.allowInsecureBootstrap = true;` and remove it once a password is set.
- **Mutable users** (`users.mutableUsers = true`) so `passwd` works during
  bootstrap; override per host for fully declarative users.
- **Unfree off by default.** `omninix.allowUnfree = true;` (or `allowUnfree` for
  `mkFlake`) opts the whole flake in.

### Secrets (sops-nix)

When `secretsPath` is set, OmniNix wires the sops plumbing so you just declare
secrets:

- Host: `secrets/<hostname>.yaml` · Shared: `secrets/shared.yaml` · User:
  `secrets/users/<username>.yaml`
- User passwords decrypt automatically (`neededForUsers`).
- `sops.age.sshKeyPaths`, `defaultSopsFormat`, and `defaultSopsFile` (when the
  host file exists) are set for you — impermanence-aware for the SSH key.

```nix
sops.secrets.my-api-key = {};                                   # host file
sops.secrets.db-password.sopsFile = ./secrets/shared.yaml;      # shared file
```

sops-nix is the batteries-included path, not a requirement: the secrets plumbing
only activates when you set `secretsPath` **and** declare the `sops-nix` input.
Leave both out and OmniNix touches nothing secrets-related.

### Bring your own secrets

The fail-closed password check accepts **any** NixOS password mechanism, not just
sops — it only asks that an active user has *one*. So you can skip sops entirely
and use agenix, a plain file, or whatever you like; OmniNix doesn't care where
the hash comes from:

```nix
# users.users.<name> is set by OmniNix; add the password yourself in any host/role:
users.users.alice.hashedPasswordFile = "/run/secrets/alice";       # agenix, systemd-creds, …
# or, fully declarative:
users.users.alice.hashedPassword = "$6$…";                         # from `mkpasswd -m sha-512`
```

Wiring a non-sops secrets tool (e.g. `agenix`) is just [bringing your own
module](#bringing-your-own-modules) — import it, declare your secret, point
`hashedPasswordFile` at its runtime path.

### Impermanence (persistence aggregation)

OmniNix ships no impermanence role in the *library* — the role is opinion (which
base dirs, which `/persist` backend), so it's yours to own. What OmniNix provides
is the one piece you can't do in userland: the **`omninix.persistence.*`
aggregation**. Any role, host, user, or profile declares what it needs persisted:

```nix
omninix.persistence.directories = [ ".ssh" "/var/lib/docker" ];
omninix.persistence.files       = [ ".kube/config" ];
```

- **System-level** contributions (from roles/hosts) are read into
  `environment.persistence."/persist"` by your impermanence role.
- **User-level** contributions (from users/profiles) are wired into
  `home.persistence."/persist"` **for you** by the NixOS+HM bridge — relativized
  per user (`/persist/home/<user>`), and gated on the host actually having a
  `/persist` store enabled. That cross-layer wiring is the part a plain module
  import can't reach. The bridge keys on `/persist` being enabled, **not** on the
  role's name — call your role whatever you like.

**You don't have to write the role from scratch.** `nix flake init` scaffolds a
ready-to-own one at `roles/impermanent.nix` that reads the aggregation above. To
turn it on:

1. Uncomment the `impermanence` input in `flake.nix`.
2. Set `roles.impermanent.enable = true;` on the host.

Edit the base-dir list in that file to taste — it's yours. (Standalone
`homeConfigurations` have no `osConfig`, so user persistence applies only on
NixOS hosts.)

### Packages

Set `omninix.packagesDir = ./packages;` (or `packagesDir` for `mkFlake`). Every
`.nix` there is `callPackage`-d into `packages.<system>.<name>` **and** added to `pkgs` on every
host and home config (`pkgs.<name>`), so modules can use your packages without
an overlay. That overlay runs before `overlaysDir`, so you can still override
them there:

```nix
# packages/hello.nix
{ writeShellScriptBin }: writeShellScriptBin "hello" ''echo hi''
```

### Overlays

Set `omninix.overlaysDir = ./overlays;` (or `overlaysDir` for `mkFlake`). Every `.nix` file there is one
overlay, applied in name order to every host, home config and package build:

```nix
# overlays/overrides.nix
final: prev: { hello = prev.hello.overrideAttrs (_: { doCheck = false; }); }
```

If the directory has a `default.nix` (or you point it at a file), that is
imported instead and must return a **list** of overlays.

---

## Dependencies

**Bundled** (OmniNix's own inputs): `flake-parts`, `nix-systems/default`.

**Foundational** — auto-wire when you declare them as inputs: `home-manager`,
`sops-nix`.

**Everything else** — `impermanence`, `disko`, `stylix`, `nixos-hardware`,
`agenix`, … — is a plain module you import yourself (see [Bringing your own
modules](#bringing-your-own-modules)). There's no blessed-integration list.

OmniNix bundles none of these into *your* flake — add the inputs you want. The
template ships home-manager and sops-nix to start.

---

## Bringing your own modules

OmniNix keeps no curated list of blessed third-party integrations — for
**anything** beyond the two foundational inputs (`impermanence`, `disko`,
`stylix`, `nixos-hardware`, `agenix`, a private flake, some random `nixosModule`)
there's no special support to wait for: hosts, roles, users, and profiles are
plain modules, and your flake `inputs` are already in scope as a module
argument. You just import.

**Opt-in, per host (idiomatic):** wrap the third-party module in a role so hosts
turn it on with a flag.

```nix
# roles/secrets.nix
{ inputs, config, lib, ... }: {
  options.roles.secrets.enable = lib.mkEnableOption "agenix secrets";
  config = lib.mkIf config.roles.secrets.enable {
    imports = [ inputs.agenix.nixosModules.default ];
    # … your age.secrets.* here
  };
}
```

**One specific host:** import it straight into the host file.

```nix
# hosts/laptop/default.nix
{ inputs, ... }: {
  imports = [ inputs.nixos-hardware.nixosModules.dell-xps-13-9310 ];
}
```

**Fleet-wide (every host / every user):** drop a wrapper file into
`nixosModulesDir` or `homeManagerModulesDir`. Every `.nix` there is imported
into *all* hosts (or all users) automatically.

```nix
# flake.nix (flake-parts; same names as mkFlake arguments)
omninix = {
  hostsDir              = ./hosts;
  nixosModulesDir       = ./modules/nixos;   # every .nix → every host
  homeManagerModulesDir = ./modules/home;    # every .nix → every user's HM
};
```

```nix
# modules/nixos/nix-index.nix — applied to all hosts
{ inputs, ... }: { imports = [ inputs.nix-index-database.nixosModules.nix-index ]; }
```

The user file's HM config and standalone `homeConfigurations` get `inputs` the
same way, so `inputs.<x>.homeManagerModules.<y>` works inside any profile or in
`homeManagerModulesDir`. (À la carte, the equivalent is the `extraModules` list
on `mkNixosConfigurations` / `mkHomeConfigurations`.)

---

## Status

Maturing from a personal config into a small reusable library. Stable enough to
build real fleets; the surface above is the committed API.

**Next up:**
- [ ] Expose `nixosModules.default` / `homeModules.default` so the secure module
      can be imported standalone (today it's reached only through the builders).
- [ ] Migration guide from a hand-rolled NixOS config.
- [ ] More worked examples.

Feedback and ideas welcome via issues.

## License

MIT
