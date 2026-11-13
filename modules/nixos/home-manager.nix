# Home Manager users: every active user gets a home, built from their file
# in `users` when they have one.
#
# The builder applies this with importApply, so `users` arrives as a plain
# function argument instead of being smuggled through specialArgs.
{users}: {
  config,
  lib,
  inputs,
  ...
}: let
  inherit (config.omninix) activeUsers;
in {
  imports = [inputs.home-manager.nixosModules.home-manager];

  config = lib.mkIf (activeUsers != []) {
    home-manager = {
      # One nixpkgs for the system and every home, installed into each
      # user's profile.
      useGlobalPkgs = true;
      useUserPackages = true;

      # User files get the flake inputs, like host files do.
      extraSpecialArgs = {inherit inputs;};

      users = lib.genAttrs activeUsers (name: {
        imports = lib.optional (users ? ${name}) users.${name};
        # Frozen: never bump this with the nixpkgs pin, or users who don't
        # set it would silently move to a newer stateVersion.
        home.stateVersion = lib.mkDefault "26.05";
      });
    };
  };
}
