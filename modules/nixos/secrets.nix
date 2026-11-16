# secretsPath on NixOS hosts, by convention:
#   <host>.yaml          the host's default sops file
#   users/<user>.yaml    key `hashed-password`: that user's password
# The builder imports sops-nix's module next to this one whenever the flake
# has the input. Applied with importApply, like every OmniNix module that
# needs the fleet; fleet.secretFile gives a file or null.
{fleet}: {
  config,
  lib,
  hostName,
  ...
}: let
  hostFile = fleet.secretFile hostName;
  usersWithSecret = lib.filter (name: fleet.secretFile "users/${name}" != null) config.omninix.activeUsers;
in {
  config = lib.mkMerge [
    (lib.mkIf (hostFile != null) {
      sops.defaultSopsFile = lib.mkDefault hostFile;
    })

    {
      # Each user's password, decrypted before users are created...
      sops.secrets = lib.listToAttrs (map (name:
        lib.nameValuePair "user-password-${name}" {
          sopsFile = fleet.secretFile "users/${name}";
          key = "hashed-password";
          neededForUsers = true;
        })
      usersWithSecret);

      # ...is their password file. The password rule in default.nix reads
      # the result like any other password.
      users.users = lib.genAttrs usersWithSecret (name: {
        hashedPasswordFile = config.sops.secrets."user-password-${name}".path;
      });
    }
  ];
}
