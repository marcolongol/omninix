# Reference

- [Flake-parts module options](#flake-parts-module-options)
- [Host options](#host-options-nixos)
- [Mac host options](#mac-host-options-nix-darwin)
- [User options](#user-options-home-manager)
- [Shipped roles and profiles](#shipped-roles-and-profiles)
- [Just the modules](#just-the-modules)
- [Library functions](#library-functions)
- [Flake outputs](#flake-outputs)

## Flake-parts module options

Set under `omninix` in a flake-parts flake that imports
`omninix.flakeModules.default`. The options are typed, so a misspelled name
fails with its file location.

| Option | Type | Default | Meaning |
|---|---|---|---|
| `hostsDir` | path or null | `null` | one host per `.nix` file or `<name>/default.nix` → `nixosConfigurations.<name>`, or `darwinConfigurations.<name>` when its system is darwin |
| `rolesDir` | path or null | `null` | roles, imported into every host: a file or `<name>/default.nix` for NixOS, `<name>/darwin.nix` for Macs |
| `extraRoles` | attrs of modules | `{}` | more roles by name, e.g. `omninix.roles`; `rolesDir` wins on a name clash. Pass role directories (paths) to bring their darwin halves too |
| `usersDir` | path or null | `null` | users → host users and `homeConfigurations.<name>` |
| `profilesDir` | path or null | `null` | profiles, imported for every user |
| `extraProfiles` | attrs of modules | `{}` | more profiles by name, e.g. `omninix.profiles` |
| `nixosModulesDir` | path or null | `null` | always-on NixOS modules and option libraries, imported into every host and exported as `nixosModules` |
| `extraNixosModules` | attrs of modules | `{}` | more NixOS modules by name, e.g. another flake's `nixosModules`; `nixosModulesDir` wins on a name clash |
| `darwinModulesDir` | path or null | `null` | the same for nix-darwin: imported into every Mac host, exported as `darwinModules` |
| `extraDarwinModules` | attrs of modules | `{}` | more nix-darwin modules by name, e.g. another flake's `darwinModules` |
| `homeManagerModulesDir` | path or null | `null` | the same for Home Manager: imported for every user, exported as `homeModules` |
| `extraHomeManagerModules` | attrs of modules | `{}` | more Home Manager modules by name, e.g. another flake's `homeModules` |
| `overlaysDir` | path or null | `null` | one overlay per `.nix` file ([details](packages-and-overlays.md)) |
| `packagesDir` | path or null | `null` | packages → `pkgs.<name>` everywhere and `packages.<system>.<name>` |
| `secretsPath` | path or null | `null` | sops secrets directory ([details](secrets.md)) |
| `defaultSystem` | string | `"x86_64-linux"` | system for hosts and users not listed below |
| `hostSystems` | attrs of strings | `{}` | per-host system, e.g. `{rpi = "aarch64-linux"; macbook = "aarch64-darwin";}`; a `-darwin` system makes a Mac host |
| `userSystems` | attrs of strings | `{}` | per-user system for standalone home configs |
| `hostInputs` | attrs of input sets | `{}` | per-host input overrides, e.g. `{desktop = {nixpkgs = …; home-manager = …;};}` ([details](packages-and-overlays.md#a-different-nixpkgs-per-host)) |
| `userInputs` | attrs of input sets | `{}` | the same, for standalone home configs |
| `allowUnfree` | bool | `false` | allow unfree packages everywhere |
| `debug` | bool | `false` | trace discovery and builds |

The flake's per-system outputs (`packages`, `formatter`, …) cover flake-parts'
own `systems`. List every system your hosts and users run on.

`perSystem`'s `pkgs` is OmniNix's package set (overlays, packages, unfree
setting). See [Packages and overlays](packages-and-overlays.md#persystem-pkgs-flake-parts).

### What your flake exports

| Output | Contents |
|---|---|
| `nixosConfigurations`, `darwinConfigurations`, `homeConfigurations` | your hosts and standalone users |
| `roles`, `profiles` | your own roles and profiles, as paths (a role directory carries both its halves) |
| `nixosModules`, `darwinModules`, `homeModules` | your own `nixosModulesDir` / `darwinModulesDir` / `homeManagerModulesDir` entries |
| `overlays.packages` | your `packagesDir` as an add-only overlay ([details](packages-and-overlays.md#sharing-them)) |
| `hosts`, `users` | the discovered paths |

Another flake can use them with `extraRoles`, `extraProfiles`,
`extraNixosModules`, `extraDarwinModules` and `extraHomeManagerModules`.

Exports never include `extra*` entries (another flake's pieces stay theirs), or
anything under an **`internal/`** subdirectory of `rolesDir`, `profilesDir`,
`nixosModulesDir`, `darwinModulesDir` or `homeManagerModulesDir`. `internal/` entries are still
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
| `omninix.requirements` | `[{ by; option; module; }]`: modules the enabled pieces need; each missing one fails with a readable message ([details](sharing.md#3-guard-dependencies-on-their-option)) |

Hosts, roles and modules also receive `inputs`, `hostName` and `secretsPath` as
module arguments.

## Mac host options (nix-darwin)

| Option | Meaning |
|---|---|
| `omninix.hostUsers.<name>.enable` | an existing macOS account on this host: sets its home to `/Users/<name>` and builds its Home Manager config |
| `omninix.hostUsers.<name>.extraGroups` | NixOS only: setting it on a Mac is an error |
| `omninix.activeUsers` | read-only list of the enabled users |
| `omninix.requirements` | as on NixOS |

With exactly one active user, `system.primaryUser` defaults to it. OmniNix
doesn't create macOS accounts, and macOS manages passwords and groups itself,
so the NixOS password check has no Mac counterpart. Mac hosts get the darwin
halves of roles (`<name>/darwin.nix`); a role without one doesn't exist there.
They're built with the host's `nix-darwin` input and packages from its
`nixpkgs`; `hostInputs` overrides both per host.

## User options (Home Manager)

| Option | Meaning |
|---|---|
| `omninix.persistence.directories` / `.files` | home paths to keep with [impermanence](impermanence.md) |
| `omninix.requirements` | the same, for Home Manager pieces |

`home.username`, `home.homeDirectory` and `home.stateVersion` default from the
user's directory name and the platform; set them in the user file to override.
User files and profiles receive `inputs` and `secretsPath`.

## Shipped roles and profiles

Pull them in with `extraRoles = omninix.roles;` and
`extraProfiles = omninix.profiles;`, pick single ones with
`extraRoles = {inherit (omninix.roles) impermanent;};`, or take all but some
with `builtins.removeAttrs omninix.profiles ["developer"]`.

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

## Just the modules

No directories and no builders: `nixosModules.default` adds the `omninix.*`
host options and the security model to any `nixosSystem`. Use it to harden a
hand-rolled config, or to run OmniNix roles and profiles from another flake in
one.

```nix
nixosConfigurations.laptop = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    omninix.nixosModules.default
    omninix.roles.impermanent # any OmniNix role works the same way
    ./configuration.nix
  ];
};
```

```nix
# configuration.nix
omninix.hostUsers.alice = {
  enable = true;
  extraGroups = ["wheel"];
};
users.users.alice.hashedPasswordFile = "/run/secrets/alice-password";
```

That gives you the [host options](#host-options-nixos) and the guarantees: the
user is created with only the groups you list, and the build fails if any
active user has no password. The builders' extras stay with the builders: sops
passwords from `secretsPath`, and Home Manager users from `usersDir`.

For Home Manager, `homeModules.default` adds the [user options](#user-options-home-manager)
that profiles use (`omninix.persistence`, `omninix.requirements`):

```nix
home-manager.users.alice.imports = [
  omninix.homeModules.default
  omninix.profiles.developer
  {profiles.developer.enable = true;}
];
```

For a hand-rolled `darwinSystem`, `darwinModules.default` adds the
[Mac host options](#mac-host-options-nix-darwin).

These modules are the same files the builders import, so importing them into an
OmniNix host or user as well is harmless.

## Library functions

`omninix.lib` is nixpkgs' `lib` plus `lib.omninix`, which is internal: the
builders behind `flakeModules.default`, which may change at any time. To pick
pieces from another flake, use plain Nix: `inherit (their.roles) desktop;`, or
`builtins.removeAttrs` for all but some.

## Flake outputs

| Output | Contents |
|---|---|
| `flakeModules.default` | the flake-parts module |
| `nixosModules.default` | the secure core and host options, without the builders ([details](#just-the-modules)) |
| `darwinModules.default` | the Mac host options, without the builders |
| `homeModules.default` | the user options, without the builders |
| `lib` | nixpkgs `lib` plus `lib.omninix` ([internal](#library-functions)) |
| `roles`, `profiles` | the shipped roles (`impermanent`) and profiles (`developer`) |
| `templates` | `default` (a whole config), `host`, `darwin-host`, `role`, `user`, `profile` |
