# Sharing between flakes

Your roles, profiles and modules can be used by other OmniNix fleets, and
theirs by yours.

## What your flake exports

| Output | From |
|---|---|
| `roles`, `profiles` | `rolesDir`, `profilesDir` |
| `nixosModules`, `darwinModules`, `homeModules` | `nixosModulesDir`, `darwinModulesDir`, `homeModulesDir` |
| `overlays.packages` | `packagesDir` ([details](packages.md#sharing-them)) |

Two things are never exported:

- **Anything under `internal/`.** Each of those directories may have an
  `internal/` subdirectory. Its pieces are used by your hosts and users like
  the others, under their own names, but not exported. Put there what only
  makes sense in your flake: pieces that read your `inputs`, personal values,
  glue between your machines. A name in both a directory and its `internal/`
  is an error.

  ```
  modules/nixos/
  ├── amd/              exported
  └── internal/
      └── site.nix      used here only
  ```

- **Pieces you use from others** (below): they stay theirs.

## Using someone else's pieces

Pick them by name, so pieces they add later don't appear on your machines
unasked:

```nix
inputs.their-fleet = {
  url = "github:someone/their-fleet";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.omninix.follows = "omninix";
};

omninix = {
  extraRoles = {inherit (inputs.their-fleet.roles) desktop;};
  extraProfiles = {inherit (inputs.their-fleet.profiles) developer;};
  extraNixosModules = {inherit (inputs.their-fleet.nixosModules) surfshark;};
  extraHomeModules = {inherit (inputs.their-fleet.homeModules) tmux;};
  extraDarwinModules = {inherit (inputs.their-fleet.darwinModules) dock;};
};
```

Then enable them like your own (`roles.desktop.enable = true;`). If one of
yours has the same name, yours wins and the build warns.

A role from another flake keeps both halves: give it as the role's directory
(as their `roles` output does) and your Macs get its `darwin.nix`. A role given
as a module instead of a path reaches NixOS hosts only.

`extra*` takes any module, not only OmniNix pieces, which is also how
[third-party modules](third-party-modules.md) go fleet-wide.

## Writing a shareable piece

### 1. No inputs

Don't take `inputs` or `hostName` (or `osConfig` in a Home Manager piece): in
someone else's flake those are *their* values. Make them options, and let the
flake using the piece set them. If a role or profile from another flake does
read `inputs`, OmniNix stops it with:

```
OmniNix: roles.foo comes from another flake and reads `inputs`, which only
that flake has. It isn't shareable as is: pass what it needs some other way.
```

### 2. No personal values

Hosts, IPs, domains, emails, keys, time zones (including in `example`s). Make
them options without a personal default, or leave them to the upstream option
(`time.timeZone`). Pieces that only make sense with your values belong in
`internal/`.

### 3. Guard what you configure

Setting an option that doesn't exist is an error, **even under `mkIf false`**,
so a piece configuring another module checks it's there, with `options`.

When the dependency is optional, wrap the settings in `optionalAttrs`:

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

When the piece is useless without it, declare it in `omninix.requirements`
(on hosts and in homes), and still guard the settings:

```nix
{config, lib, options, ...}: {
  config = lib.mkIf config.roles.desktop.enable (lib.mkMerge [
    {
      omninix.requirements = [
        {
          by = "roles.desktop";
          option = "stylix.image";
          module = "stylix's NixOS module (inputs.stylix.nixosModules.stylix)";
        }
      ];
    }
    (lib.optionalAttrs (options ? stylix.image) {
      stylix.polarity = "dark";
    })
  ]);
}
```

Without stylix, the build fails with one readable message:

```
OmniNix: roles.desktop needs stylix's NixOS module (inputs.stylix.nixosModules.stylix);
import it (the option `stylix.image` doesn't exist).
```

Guard on `options`, never `config`, and only inside `config = …`.

### 4. Inert until enabled

Importing a piece without enabling it changes nothing. Roles and profiles get
this from their `enable` option; give always-on modules one too, so others can
import them everywhere.

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

Nix imports a path only once, so your own flake discovering it too is fine.

### 6. Safe defaults

No open ports, extra privileges or listeners unless an option asks for them.
Enabling your role should give what its name says, and nothing more exposed.
