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

    # Anything beyond the foundational inputs above is a plain module you import
    # yourself in a host/role/profile (see the README, "Bringing your own
    # modules"). For example, for ephemeral-root setups:
    # impermanence.url = "github:nix-community/impermanence";
    # disko = { url = "github:nix-community/disko"; inputs.nixpkgs.follows = "nixpkgs"; };
  };

  outputs = {
    flake-parts,
    omninix,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      # nixosConfigurations.<host> and, from ./users, homeConfigurations.<user>
      # for standalone Home Manager (`home-manager switch --flake .#<user>`).
      imports = [omninix.flakeModules.default];

      # Systems for perSystem outputs (packages, formatter, devShells, ...).
      systems = ["x86_64-linux" "aarch64-linux"];

      omninix = {
        hostsDir = ./hosts;
        rolesDir = ./roles;
        extraRoles = omninix.roles;
        usersDir = ./users;
        profilesDir = ./profiles;
        extraProfiles = omninix.profiles;
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
