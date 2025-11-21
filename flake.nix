{
  description = "OmniNix, a small Nix library for composing NixOS + Home Manager fleets from hosts, roles, users, and profiles";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";

    systems.url = "github:nix-systems/default";

    flake-parts.url = "github:hercules-ci/flake-parts";

    home-manager = {
      # Match the nixpkgs release (master HM tracks unstable and rejects the
      # 26.05 stateVersion).
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    systems,
    flake-parts,
    ...
  } @ inputs: let
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = import systems;
      imports = [
        ./modules/flake
      ];
    };
}
