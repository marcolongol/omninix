# Home Manager users for builder hosts, shared by the NixOS and darwin
# modules so both wire users the same way. Each active user's imports come
# from mkHomeModules, the same set as their standalone homeConfigurations.
{
  config,
  lib,
  inputs,
  users,
  profiles,
  homeManagerModules,
  secretsPath,
  mkHomeModules,
  ...
}: let
  inherit (config.omninix) activeUsers;
in {
  options.omninix.internal.extraHomeModules = lib.mkOption {
    type = lib.types.listOf lib.types.raw;
    default = [];
    internal = true;
    description = "Platform-specific modules added to every active user's Home Manager config.";
  };

  config = lib.mkIf (activeUsers != []) {
    home-manager = {
      extraSpecialArgs = {
        inherit inputs secretsPath;
      };
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = lib.mkDefault "bak";
      # stateVersion is always defaulted (mkDefault) so a user file may
      # override it but is never required to set it.
      users = lib.genAttrs activeUsers (userName: {
        imports =
          mkHomeModules {
            inherit inputs lib profiles homeManagerModules userName secretsPath;
            userFile = users.${userName} or null;
          }
          ++ config.omninix.internal.extraHomeModules;
        # Frozen: never bump with the nixpkgs pin. Users who don't set it
        # would silently move to a newer stateVersion.
        home.stateVersion = lib.mkDefault "26.05";
      });
    };
  };
}
