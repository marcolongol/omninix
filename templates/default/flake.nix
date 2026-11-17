{
  description = "My fleet, built with OmniNix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Home Manager must match the nixpkgs release.
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    omninix = {
      url = "github:marcolongol/omninix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
  };

  outputs = {
    flake-parts,
    omninix,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [omninix.flakeModules.default];
      systems = ["x86_64-linux" "aarch64-linux"];

      # Each file or directory in these becomes a host, user, role or profile.
      omninix = {
        hostsDir = ./hosts;
        usersDir = ./users;
        rolesDir = ./roles;
        profilesDir = ./profiles;
        secretsPath = ./secrets;
      };

      perSystem = {pkgs, ...}: {
        formatter = pkgs.alejandra;
      };
    };
}
