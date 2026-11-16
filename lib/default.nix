# nixpkgs' lib, extended with the `omninix` namespace. Each file under lib/
# gets `final` (the finished, extended lib) as its `lib`, so files can call
# each other through `lib.omninix.*`.
#
# Internal only: the flake exports just `lib.omninix` (see modules/flake).
#
# The files, in the order a flake's settings flow through them:
{inputs}:
inputs.nixpkgs.lib.extend (final: _: {
  omninix =
    # directories -> pieces ({ name = path; }), internal/, role halves
    (import ./discovery.nix {lib = final;})
    # misspelt names in per-host and per-user maps
    // (import ./names.nix {lib = final;})
    # another flake's pieces, and the guard on borrowed `inputs`
    // (import ./sharing.nix {lib = final;})
    # packages and overlays
    // (import ./packages.nix {lib = final;})
    # settings -> the fleet: every default, merged pieces, collected errors
    // (import ./fleet.nix {lib = final;})
    # the fleet -> NixOS and nix-darwin systems
    // (import ./hosts.nix {lib = final;})
    # the fleet -> standalone homes
    // (import ./home.nix {lib = final;});
})
