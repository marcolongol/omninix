# Home Manager users, on NixOS and nix-darwin hosts: every active user gets
# a home.
#
# The builder applies this with importApply, passing:
#   - homeManagerModule: Home Manager's NixOS or darwin module
#   - homeModules: a function from a user's name to the modules of their
#     home (lib/home.nix's userHomeModules, shared with standalone homes)
# They arrive as plain function arguments instead of through specialArgs.
{
  homeManagerModule,
  homeModules,
}: {
  config,
  lib,
  inputs,
  ...
}: let
  inherit (config.omninix) activeUsers;
in {
  imports = [homeManagerModule];

  config = lib.mkIf (activeUsers != []) {
    home-manager = {
      # One nixpkgs for the system and every home, installed into each
      # user's profile.
      useGlobalPkgs = true;
      useUserPackages = true;

      # User files get the flake inputs, like host files do.
      extraSpecialArgs = {inherit inputs;};

      users = lib.genAttrs activeUsers (name: {
        imports = homeModules name ++ [../home/persistence-host.nix];
      });
    };
  };
}
