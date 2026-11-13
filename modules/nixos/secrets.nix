# sops-nix on hosts: imported whenever the flake has the input, so hosts can
# use it by hand; with secretsPath, wired by convention (lib/secrets.nix).
#
# The builder applies this with importApply, passing `secretFile`:
# lib.omninix.secretFile with secretsPath already filled in, so
# `secretFile "users/alice"` is that file or null.
{secretFile}: {
  config,
  lib,
  inputs,
  hostName,
  ...
}: let
  hostFile = secretFile hostName;
  usersWithSecret = lib.filter (name: secretFile "users/${name}" != null) config.omninix.activeUsers;
in {
  imports = [inputs.sops-nix.nixosModules.sops];

  config = lib.mkMerge [
    (lib.mkIf (hostFile != null) {
      sops.defaultSopsFile = lib.mkDefault hostFile;
    })

    {
      # Each user's password, decrypted before users are created...
      sops.secrets = lib.listToAttrs (map (name:
        lib.nameValuePair "user-password-${name}" {
          sopsFile = secretFile "users/${name}";
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
