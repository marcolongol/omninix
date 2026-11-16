{
  description = "";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    systems.url = "github:nix-systems/default";

    # For the tests only: consumers bring their own. Must match the nixpkgs
    # release, or Home Manager warns.
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # For the tests only, like home-manager.
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # For the tests only, like home-manager.
    impermanence.url = "github:nix-community/impermanence";

    # For the tests only, like home-manager.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    systems,
    flake-parts,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = import systems;
      imports = [./modules/flake];

      # OmniNix on itself: the roles it ships are exported like any
      # consumer's.
      omninix.rolesDir = ./roles;
    };
}
