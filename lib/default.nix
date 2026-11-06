# OmniNix Library
#
# nixpkgs.lib extended with an `omninix` namespace: the builders and the
# engine behind flakeModules.default (internal), plus the helpers documented
# (internal: the public API is the flake's modules).
#
# Type: { inputs :: { nixpkgs :: Flake, ... } } -> Lib
#
# Structure: the `omninix` namespace is assembled from focused files, each merged
# into a single `lib.extend` fixpoint so cross-references (final.omninix.*) resolve
# uniformly.
#
#   validations.nix            - assert* input guards, validate* path helpers
#   utils.nix                  - generic helpers (mapAttrsMaybe, mkDebugTrace)
#   discovery.nix              - directory scanning (forAllNixFiles, mkDirMap, loadOverlays)
#   mkNixosConfigurations.nix  - mkNixosConfigurations
#   mkDarwinConfigurations.nix - mkDarwinConfigurations (nix-darwin hosts)
#   mkHomeModules.nix          - mkHomeModules (shared per-user HM module set)
#   mkHomeConfigurations.nix   - mkHomeConfigurations (standalone HM)
#   mkFlakeCore.nix            - mkFlakeCore, the engine behind flakeModules.default (internal)
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
        // (import ./mkDarwinConfigurations.nix {inherit final;})
        // (import ./mkHomeModules.nix)
        // (import ./mkHomeConfigurations.nix {inherit final;})
        // (import ./mkFlakeCore.nix {inherit final;});
    }
  );
in
  lib
