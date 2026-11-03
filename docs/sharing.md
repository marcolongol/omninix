# Sharing roles, profiles and modules

Your roles, profiles and modules can be used by other OmniNix flakes, and
theirs by yours. This page covers how sharing works, how to write pieces that
are safe to share, and the check that proves it.

A worked example is [nix-config](https://github.com/marcolongol/nix-config):
its roles, profiles and modules are all shared, and its personal parts live
under `internal/`.

## What your flake exports

| Output | From |
|---|---|
| `roles`, `profiles` | your `rolesDir` / `profilesDir` |
| `nixosModules`, `homeModules` | your `nixosModulesDir` / `homeManagerModulesDir` |
| `overlays.packages` | your `packagesDir` ([details](packages-and-overlays.md#sharing-them)) |

Two things are never exported:

- **`extra*` entries.** Another flake's pieces stay theirs; re-exporting them
  would pin them at your version.
- **Anything under `internal/`.** A subdirectory named `internal` in any of
  those four directories is imported into your hosts and users, under the
  file's own name, but never exported. Use it for files that read your flake
  `inputs`, hold personal values, or glue your machines together. A name that
  exists both in a directory and in its `internal/` is an error.

```
modules/nixos/
├── amd/              exported
├── surfshark/        exported
└── internal/
    ├── identity.nix  used here only
    └── site.nix      used here only
```

## Using someone else's pieces

Pick them by name with the `extra*` options. Your own directories win on a name
clash:

```nix
inputs.their-config = {
  url = "github:someone/their-config";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.omninix.follows = "omninix";
};

omninix = {
  extraRoles = {inherit (their-config.roles) desktop;};
  extraProfiles = {inherit (their-config.profiles) developer;};
  extraNixosModules = {inherit (their-config.nixosModules) surfshark;};
  extraHomeManagerModules = {inherit (their-config.homeModules) tmux;};
};
```

Then enable them like your own (`roles.desktop.enable = true;`) and bring what
they ask for. Pick by name rather than taking a whole set, so pieces added to
theirs later don't appear on your machines unasked.

The `extra*` options also work for third-party flakes' modules (disko, stylix,
…): they're the simplest way to import a module into every host or user, once.

## Writing a shareable piece

A role, profile or module is shareable when it follows six rules.

### 1. No flake inputs or other OmniNix extras

Don't take `inputs`, `self`, `secretsPath`, `hostName`, `users`, `profiles` or
`homeManagerModules` (or `osConfig` in a Home Manager piece). In someone else's
flake these are **their** values, or absent. Use options, and let the flake
using the piece supply the value.

| Instead of | Do |
|---|---|
| importing `inputs.foo.nixosModules.foo` | let the consumer import it (`extraNixosModules`), and guard on it (rule 3) |
| reading `inputs.self + "/wallpapers"` | set the upstream option (`stylix.image`) in your own config |
| `secretsPath + "/shared.yaml"` | declare the secret in your own config |
| `networking.hostName = hostName` | leave it to the flake: OmniNix passes `hostName` to your own modules |

### 2. No personal values

Hosts, IPs, domains, emails, home paths, coordinates, keys, time zones,
employer names, including in `example`s. Make them options without a personal
default, or leave them to the upstream option (`time.timeZone`,
`services.comin`). Add an option only when the piece computes something from
the value, like nix-config's `roles.nfsClient.server` and `.shares`, which
build the mounts.

### 3. Guard dependencies on their option

Setting an option that doesn't exist is an error, **even under `mkIf false`**.
So a piece that configures another module checks the module is there first,
with `options`:

**Optional dependency**: use it when present, skip it otherwise. Wrap the
attribute itself in `optionalAttrs`, never `mkIf`:

```nix
{config, lib, options, ...}: {
  config = lib.mkIf config.roles.common.enable (lib.mkMerge [
    { /* … */ }
    (lib.optionalAttrs (options ? programs.nix-index-database) {
      programs.nix-index-database.comma.enable = true;
    })
  ]);
}
```

**Required dependency**: the piece is useless without it. Assert it, so a
consumer gets a readable message, and guard the settings anyway:

```nix
{config, lib, options, ...}: {
  config = lib.mkIf config.roles.desktop.enable (lib.mkMerge [
    {
      assertions = [{
        assertion = options ? stylix.image;
        message = "roles.desktop needs the stylix NixOS module";
      }];
      # A home half that also uses stylix only comes with it; otherwise Home
      # Manager's "option does not exist" error would hide the assertion.
      home-manager.sharedModules = lib.optional (options ? stylix.image) ./home;
    }
    (lib.optionalAttrs (options ? stylix.image) {
      stylix.polarity = "dark";
    })
  ]);
}
```

Security-bearing dependencies (secrets, deploy tooling, impermanence, PAM) are
always required, so a missing import fails loudly instead of silently dropping
secrets or state. OmniNix's own `roles.impermanent` works this way.

Guard on `options`, never on `config`, and inside `config = …`: a module whose
top level depends on `options` recurses.

### 4. Inert until enabled

Importing a piece without enabling it changes nothing. Roles and profiles get
this from their `enable` option. Give modules one too (nix-config's
`shell.zsh.enable`, `lang.go.enable`), so `extraHomeManagerModules` can import
them everywhere without side effects.

### 5. Import what you configure

A piece that sets another piece's options imports it by relative path, so it
works on its own:

```nix
# profiles/developer.nix
{
  imports = [../modules/home/lang];
  # … lang.go.enable = true; …
}
```

In your own flake the module is also discovered; Nix imports a path only once.

### 6. Safe defaults

No open ports, extra privileges (sudo rules, capability wrappers), listeners or
auto-deploy unless an option asks for it. A consumer enabling your role should
get what its name says, nothing more exposed.

### Packages

A module that needs one of your `packagesDir` packages builds it itself, so it
works without your overlay:

```nix
package = lib.mkOption {
  type = lib.types.package;
  default = pkgs.callPackage ../../../packages/surfshark.nix {};
};
```

That's the same derivation as your `pkgs.surfshark`.

## The portability check

`nix flake check` can prove your exported pieces follow these rules:

```nix
omninix.checks.portable = {
  enable = true;
  # What a consumer must bring, per piece.
  requires.roles.desktop = [inputs.stylix.nixosModules.stylix];
  # Deep evaluations with pieces enabled and sample values.
  scenarios.base.nixos = {
    roles.nfsClient = {
      enable = true;
      server = "nas.example:/export";
      shares = ["Media"];
    };
  };
  scenarios.base.home.profiles.developer.enable = true;
  # Pieces not converted yet (warns while non-empty).
  exclude = [];
};
```

It evaluates your pieces in a bare OmniNix host, a container with one probe user,
where the OmniNix extras throw if a piece uses them. Each check is its own
`checks.<system>.omninix-portable-*` attribute:

| Check | Fails when |
|---|---|
| `-static` | a file takes a banned argument or reads it via `_module.specialArgs`, fetches at eval time, imports from `internal/`, or contains personal values (emails, private IPs, `/home/<name>`, keys, coordinates) |
| `-inert` | importing every piece without enabling any changes the system (rule 4) |
| `-<kind>-<name>` | the piece doesn't evaluate alone with its `requires` (an unguarded dependency, rule 3), or pulls in an `internal/` file |
| `-<kind>-<name>-enabled` | enabling it **without** its `requires` throws instead of failing an assertion (rule 3) |
| `-scenario-<name>` | a scenario doesn't evaluate |

Use `exclude` while converting existing pieces; it lists what's left. `allow`
exempts strings from the personal-value lint, and `enableOptions` names a
module's enable option when it isn't `roles/profiles.<camelName>.enable`.

What it can't check: whether a value is personal beyond those patterns, and
whether a default is safe (rules 2 and 6). Review those by hand.

Without the flake-parts module, call `omninix.lib.omninix.mkPortableCheck`
directly ([reference](reference.md#portability-check)).
