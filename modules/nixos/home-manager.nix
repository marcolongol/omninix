# Home Manager users: every active user gets a home.
#
# The builder applies this with importApply, passing `homeModules`: a
# function from a user's name to the modules of their home (lib/home.nix's
# userHomeModules, shared with standalone homes). It arrives as a plain
# function argument instead of being smuggled through specialArgs.
{homeModules}: {
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

      users = lib.genAttrs activeUsers (name: {imports = homeModules name;});
    };
  };
}
