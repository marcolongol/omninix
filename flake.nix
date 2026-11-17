{
  description = "OmniNix: NixOS machines, Macs and Home Manager users from a few directories";

  # Only what OmniNix itself needs: everything here ends up in the lock file
  # of every flake that uses it. The checks' inputs live in dev/flake.nix.
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    systems.url = "github:nix-systems/default";
  };

  outputs = {
    systems,
    flake-parts,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = import systems;
      imports = [
        ./modules/flake
        flake-parts.flakeModules.partitions
      ];

      # OmniNix on itself: the roles it ships are exported like any
      # consumer's.
      omninix.rolesDir = ./roles;

      # `checks` and `packages` (the docs) come from the dev partition: a
      # second evaluation that also has dev/flake.nix's inputs, fetched only
      # when those outputs are.
      partitionedAttrs = {
        checks = "dev";
        packages = "dev";
      };
      partitions.dev = {
        extraInputsFlake = ./dev;
        module = ./dev/flake-module.nix;
      };
    };
}
