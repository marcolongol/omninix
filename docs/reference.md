# Reference

- [Flake-parts module options](#flake-parts-module-options)
- [Host options](#host-options-nixos)
- [User options](#user-options-home-manager)
- [Shipped roles and profiles](#shipped-roles-and-profiles)
- [Without flake-parts](#without-flake-parts)
- [Library functions](#library-functions)
- [Flake outputs](#flake-outputs)

## Flake-parts module options

Set under `omninix` in a flake-parts flake that imports
`omninix.flakeModules.default`. The options are typed, so a misspelled name
fails with its file location.

| Option | Type | Default | Meaning |
|---|---|---|---|
| `hostsDir` | path or null | `null` | one host per `.nix` file or `<name>/default.nix` → `nixosConfigurations.<name>` |
| `rolesDir` | path or null | `null` | roles, imported into every host |
| `extraRoles` | attrs of modules | `{}` | more roles by name, e.g. `omninix.roles`; `rolesDir` wins on a name clash |
| `usersDir` | path or null | `null` | users → host users and `homeConfigurations.<name>` |
| `profilesDir` | path or null | `null` | profiles, imported for every user |
| `extraProfiles` | attrs of modules | `{}` | more profiles by name, e.g. `omninix.profiles` |
| `nixosModulesDir` | path or null | `null` | NixOS modules imported into every host |
| `extraNixosModules` | attrs of modules | `{}` | more NixOS modules by name, e.g. another flake's `nixosModules`; `nixosModulesDir` wins on a name clash |
| `homeManagerModulesDir` | path or null | `null` | Home Manager modules imported for every user |
| `extraHomeManagerModules` | attrs of modules | `{}` | more Home Manager modules by name, e.g. another flake's `homeModules` |
| `overlaysDir` | path or null | `null` | one overlay per `.nix` file ([details](packages-and-overlays.md)) |
| `packagesDir` | path or null | `null` | packages → `pkgs.<name>` everywhere and `packages.<system>.<name>` |
| `secretsPath` | path or null | `null` | sops secrets directory ([details](secrets.md)) |
| `defaultSystem` | string | `"x86_64-linux"` | system for hosts and users not listed below |
| `hostSystems` | attrs of strings | `{}` | per-host system, e.g. `{rpi = "aarch64-linux";}` |
| `userSystems` | attrs of strings | `{}` | per-user system for standalone home configs |
| `allowUnfree` | bool | `false` | allow unfree packages everywhere |
| `debug` | bool | `false` | trace discovery and builds |
| `checks.portable.enable` | bool | `false` | add checks proving your exported pieces work in other flakes ([below](#portability-check)) |
| `checks.portable.requires` | attrs | `{}` | modules a consumer must bring, per piece: `{ roles.desktop = [stylix…]; }` |
| `checks.portable.scenarios` | attrs | `{}` | named deep evals: `{ nixos; home; requires; homeRequires; }` |
| `checks.portable.exclude` | list of strings | `[]` | pieces not checked yet, e.g. `"roles.desktop"` (warns) |
| `checks.portable.enableOptions` | attrs | `{}` | enable option per piece when it isn't `roles/profiles.<camelName>.enable` |
| `checks.portable.allow` | list of strings | `[]` | strings the personal-value lint ignores |
| `checks.portable.system` | string | `defaultSystem` | system the checks run on (Linux) |

The flake's per-system outputs (`packages`, `formatter`, …) cover flake-parts'
own `systems`. List every system your hosts and users run on.

`perSystem`'s `pkgs` is OmniNix's package set (overlays, packages, unfree
setting). See [Packages and overlays](packages-and-overlays.md#persystem-pkgs-flake-parts).

### Portability check

With `checks.portable.enable`, `nix flake check` also proves that your exported
roles, profiles and modules work in someone else's flake. Each is a separate
`checks.<system>.omninix-portable-*` attribute:

| Check | Fails when |
|---|---|
| `-static` | a piece takes `inputs`, `secretsPath`, `hostName`, … (or `osConfig` in Home Manager), reads them through `_module.specialArgs`, fetches at eval time, imports from `internal/`, or contains an email, private IP, `/home/<name>` path, key or coordinates |
| `-inert` | importing every piece without enabling any changes the system |
| `-<kind>-<name>` | the piece doesn't evaluate on its own (with its `requires`), or pulls in an `internal/` file |
| `-<kind>-<name>-enabled` | enabling it **without** its `requires` throws instead of failing a readable assertion |
| `-scenario-<name>` | a scenario doesn't evaluate |

### What your flake exports

| Output | Contents |
|---|---|
| `nixosConfigurations`, `homeConfigurations` | your hosts and standalone users |
| `roles`, `profiles` | your own roles and profiles, as paths |
| `nixosModules`, `homeModules` | your own `nixosModulesDir` / `homeManagerModulesDir` entries |
| `overlays.packages` | your `packagesDir` as an add-only overlay ([details](packages-and-overlays.md#sharing-them)) |
| `hosts`, `users` | the discovered paths |

Another flake can use them with `extraRoles`, `extraProfiles`,
`extraNixosModules` and `extraHomeManagerModules`.

Exports never include `extra*` entries (another flake's pieces stay theirs), or
anything under an **`internal/`** subdirectory of `rolesDir`, `profilesDir`,
`nixosModulesDir` or `homeManagerModulesDir`. `internal/` entries are still
imported here, under their own names, so use it for pieces that only make sense
in your flake: files that take `inputs`, personal values, site glue. A name that
exists both in a directory and in its `internal/` is an error. Module exports are
`mkDefault`, so your own `flake.nixosModules.<name>` replaces the discovered one.

## Host options (NixOS)

| Option | Meaning |
|---|---|
| `omninix.hostUsers.<name>.enable` | create this user on the host and build their Home Manager config |
| `omninix.hostUsers.<name>.extraGroups` | groups for this user, e.g. `["wheel"]` |
| `omninix.defaultUserGroups` | groups for every active user on the host (default `[]`) |
| `omninix.activeUsers` | read-only list of the enabled users |
| `omninix.allowInsecureBootstrap` | build even if a user has no password (first install only; allows passwordless login) |
| `omninix.persistence.directories` / `.files` | system paths to keep with [impermanence](impermanence.md) |

Hosts, roles and modules also receive `inputs`, `hostName` and `secretsPath` as
module arguments.

## User options (Home Manager)

| Option | Meaning |
|---|---|
| `omninix.persistence.directories` / `.files` | home paths to keep with [impermanence](impermanence.md) |

`home.username`, `home.homeDirectory` and `home.stateVersion` default from the
user's directory name and the platform; set them in the user file to override.
User files and profiles receive `inputs` and `secretsPath`.

## Shipped roles and profiles

Pull them in with `extraRoles = omninix.roles;` and
`extraProfiles = omninix.profiles;`, or pick single ones with
`omninix.lib.omninix.pick`.

### `roles.impermanent`

| Option | Default | Meaning |
|---|---|---|
| `enable` | `false` | keep state in `/persist` |
| `persistCoredumps` | `false` | also keep `/var/lib/systemd/coredump` |
| `wipe.enable` | `false` | roll the btrfs root back on every boot |
| `wipe.acknowledgeDataLoss` | `false` | required by `wipe.enable` |
| `wipe.device` | `fileSystems."/".device` | the btrfs device holding `/` |
| `wipe.keepDays` | `30` | how long archived roots are kept |

See [Impermanence and root wipe](impermanence.md) before enabling the wipe.

### `profiles.developer`

CLI developer tools: git and shell tooling, Docker and Kubernetes CLIs, and
more. It contains **unfree** packages, so it needs `allowUnfree = true`, plus a
recent Home Manager.

## Without flake-parts

### `mkFlake`

The same engine as a plain function. It takes the options above as arguments,
plus `systems`:

```nix
outputs = {omninix, ...} @ inputs:
  omninix.lib.omninix.mkFlake inputs {
    hostsDir = ./hosts;
    rolesDir = ./roles;
    usersDir = ./users;
    profilesDir = ./profiles;
    systems = ["x86_64-linux"];
  };
```

It returns `nixosConfigurations`, `homeConfigurations`, `hosts`, `roles`,
`users`, `profiles`, `nixosModules`, `homeModules`, and `packages` plus
`overlays.packages` when `packagesDir` is set. It also takes `extraNixosModules` and
`extraHomeManagerModules`.

### À la carte

Call the builders yourself and keep full control of your outputs. They still
include OmniNix's NixOS module, so the secure defaults apply.

```nix
let o = omninix.lib.omninix; in {
  nixosConfigurations = o.mkNixosConfigurations {
    inherit inputs;
    hosts = o.forAllNixFiles ./hosts (p: p);
    roles = o.forAllNixFiles ./roles (p: p);
    users = o.forAllNixFiles ./users (p: p);
    profiles = o.forAllNixFiles ./profiles (p: p);
    secretsPath = ./secrets;
    extraModules = [ /* more NixOS modules */ ];
  };
}
```

`mkNixosConfigurations` takes `inputs`, `hosts`, `roles`, `users`, `profiles`,
`nixosModules`, `homeManagerModules`, `overlays`, `extraModules`,
`specialArgs`, `secretsPath`, `defaultSystem`, `hostSystems`, `allowUnfree` and
`debug`. `mkHomeConfigurations` takes the user-side equivalents, plus
`userSystems`.

## Library functions

Under `omninix.lib.omninix`:

| Function | What it does |
|---|---|
| `mkFlake inputs { … }` | discover the directories and build everything (above) |
| `mkNixosConfigurations { … }` | build NixOS systems from host/role/user/profile sets |
| `mkHomeConfigurations { … }` | build standalone Home Manager configs |
| `mkHomeModules { … }` | the module list one user's Home Manager config is built from |
| `forAllNixFiles dir f` | `{ <name> = f path; }` for each `.nix` file or `<dir>/default.nix` |
| `mkDirMap { name = dir; }` | `forAllNixFiles` over several directories |
| `loadOverlays path` | overlays from a directory (one per file) or a file returning a list |
| `mkPortableCheck { inputs; system; pieces; … }` | the portability checks above, for flakes without the flake-parts module |
| `discoverPieces dir` | `{ all; exportable; }`: like `forAllNixFiles`, plus `dir/internal/` in `all` only |
| `pick [names] attrs` | only the named entries (throws on a typo) |
| `drop [names] attrs` | everything except the named entries |

`omninix.lib` is nixpkgs' `lib` with these added.

## Flake outputs

| Output | Contents |
|---|---|
| `flakeModules.default` | the flake-parts module |
| `lib` | nixpkgs `lib` plus `lib.omninix` |
| `roles`, `profiles` | the shipped roles (`impermanent`) and profiles (`developer`) |
| `templates` | `default` (a whole config), `host`, `role`, `user`, `profile` |
