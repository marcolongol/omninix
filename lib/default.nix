# OmniNix Library
#
# This library provides utilities for building NixOS configurations using the
# OmniNix framework. It extends nixpkgs.lib with custom functions for managing
# hosts, roles, users, and profiles.
#
# Type: { nixpkgs :: Flake, ... } -> Lib
#
# Usage:
#   { inputs }: let
#     lib = import ./lib { inherit inputs; };
#   in lib.omninix.mkFlake inputs { ... }
#
# Structure: the `omninix` namespace is assembled from focused files, each merged
# into a single `lib.extend` fixpoint so cross-references (final.omninix.*) resolve
# uniformly. This mirrors how nixpkgs' own lib is organized.
#
#   validations.nix            - assert* input guards
#   utils.nix                  - generic helpers (mapAttrsMaybe, mkDebugTrace)
#   discovery.nix              - directory scanning (forAllNixFiles, mkDirMap)
#   mkNixosConfigurations.nix  - mkNixosConfigurations
#   mkHomeModules.nix          - mkHomeModules (shared per-user HM module set)
#   mkHomeConfigurations.nix   - mkHomeConfigurations (standalone HM)
#   mkFlake.nix                - mkFlake (high-level entry point) + internal mkFlakeCore engine
{inputs}: let
  # Extend the Nixpkgs lib with OmniNix custom functions. `final` is the fixpoint
  # of the extended lib; each fragment receives what it needs (the fixpoint
  # and/or flake inputs) and contributes members to the `omninix` namespace.
  lib = inputs.nixpkgs.lib.extend (
    final: _: {
      omninix =
        (import ./validations.nix {inherit final;})
        // (import ./utils.nix {inherit final;})
        // (import ./discovery.nix {inherit final;})
        // (import ./mkNixosConfigurations.nix {inherit final;})
        // (import ./mkHomeModules.nix)
        // (import ./mkHomeConfigurations.nix {inherit final;})
        // (import ./mkFlake.nix {inherit final;});
    }
  );
in
  # Return the extended lib for use in flakes
  lib
