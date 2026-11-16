# Home Manager users, on NixOS and nix-darwin hosts: every active user gets
# a home, from fleet.homeModulesFor (the same modules as standalone homes).
#
# Applied with importApply, like every OmniNix module that needs the fleet.
# The builder imports Home Manager's own module next to it.
{fleet}: {
  config,
  lib,
  inputs,
  ...
}: let
  inherit (config.omninix) activeUsers;
in {
  config = lib.mkIf (activeUsers != []) {
    home-manager = {
      # One nixpkgs for the system and every home, installed into each
      # user's profile.
      useGlobalPkgs = true;
      useUserPackages = true;

      # User files get the flake inputs, like host files do.
      extraSpecialArgs = {inherit inputs;};

      users = lib.genAttrs activeUsers (name: {
        imports = fleet.homeModulesFor name ++ [../home/persistence-host.nix];
      });
    };
  };
}
