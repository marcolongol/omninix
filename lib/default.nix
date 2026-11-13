# nixpkgs' lib, extended with the `omninix` namespace. Each file under lib/
# gets `final` (the finished, extended lib) as its `lib`, so files can call
# each other through `lib.omninix.*`.
#
# Internal only: the flake exports just `lib.omninix` (see modules/flake).
{inputs}:
inputs.nixpkgs.lib.extend (final: _: {
  omninix =
    (import ./discovery.nix {lib = final;})
    // (import ./names.nix {lib = final;})
    // (import ./nixos.nix {lib = final;})
    // (import ./home.nix {lib = final;})
    // (import ./secrets.nix {lib = final;})
    // (import ./packages.nix {lib = final;});
})
