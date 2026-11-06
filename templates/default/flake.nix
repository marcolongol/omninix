{
  description = "OmniNix NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    omninix.url = "github:marcolongol/omninix";
    omninix.inputs.flake-parts.follows = "flake-parts";

    # Foundational: auto-wired when present.
    home-manager = {
      # Match the nixpkgs release channel.
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Anything beyond the foundational inputs above is a plain module: list it in
    # omninix.extraNixosModules / extraHomeManagerModules below to import it for
    # every host / user, or import it in one host (docs/third-party-modules.md).
    # For example, for ephemeral-root setups:
    # impermanence.url = "github:nix-community/impermanence";
    # disko = { url = "github:nix-community/disko"; inputs.nixpkgs.follows = "nixpkgs"; };

    # For Mac hosts (nix flake new -t github:marcolongol/omninix#darwin-host hosts/<name>):
    # nix-darwin = { url = "github:nix-darwin/nix-darwin/nix-darwin-26.05"; inputs.nixpkgs.follows = "nixpkgs"; };
  };

  outputs = {
    flake-parts,
    omninix,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      # nixosConfigurations.<host> (darwinConfigurations.<host> for Macs) and,
      # from ./users, homeConfigurations.<user> for standalone Home Manager
      # (`home-manager switch --flake .#<user>`).
      imports = [omninix.flakeModules.default];

      # Systems for perSystem outputs (packages, formatter, devShells, ...).
      systems = ["x86_64-linux" "aarch64-linux"];

      omninix = {
        hostsDir = ./hosts;
        # A host with a darwin system is a Mac, built with nix-darwin:
        # hostSystems.macbook = "aarch64-darwin";
        rolesDir = ./roles;
        extraRoles = omninix.roles;
        usersDir = ./users;
        profilesDir = ./profiles;
        extraProfiles = omninix.profiles;
        # Third-party modules for every host / every user, e.g.:
        # extraNixosModules.impermanence = inputs.impermanence.nixosModules.impermanence;
        # Auto-discovered packages -> packages.<system>.<name> and pkgs.<name>
        packagesDir = ./packages;
        # Uncomment once you've set up sops-nix secrets:
        # secretsPath = ./secrets;
        # Unfree packages are off by default. Set true if you enable something
        # that needs them (e.g. the developer profile's dbeaver/ngrok, nvidia):
        # allowUnfree = true;
      };

      # perSystem pkgs is OmniNix's: overlays, packagesDir and allowUnfree applied.
      perSystem = {pkgs, ...}: {
        formatter = pkgs.alejandra;
      };
    };
}
