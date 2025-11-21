{
  description = "OmniNix NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";
    omninix.url = "github:marcolongol/omninix";

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
    self,
    nixpkgs,
    omninix,
    ...
  } @ inputs:
    # mkFlake produces `nixosConfigurations.<host>` and, from ./users, also
    # `homeConfigurations.<user>` for standalone Home Manager use on non-NixOS
    # machines (`home-manager switch --flake .#<user>`). No extra config needed.
    omninix.lib.omninix.mkFlake inputs {
      hostsDir = ./hosts;
      rolesDir = ./roles;
      extraRoles = omninix.roles;
      usersDir = ./users;
      profilesDir = ./profiles;
      extraProfiles = omninix.profiles;
      # Auto-discovered packages -> packages.<system>.<name>
      packagesDir = ./packages;
      # Uncomment once you've set up sops-nix secrets:
      # secretsPath = ./secrets;
      # Unfree packages are off by default. Set true if you enable something
      # that needs them (e.g. the developer profile's dbeaver/ngrok, nvidia):
      # allowUnfree = true;
    };
}
