# OmniNix NixOS module for the builders: the secure core (core.nix, also
# exported as nixosModules.default) plus the wiring that needs the builders'
# arguments: sops-backed passwords and Home Manager users.
{
  config,
  inputs,
  lib,
  hostName,
  users,
  profiles,
  homeManagerModules,
  secretsPath,
  mkHomeModules,
  ...
}: let
  inherit (config.omninix) activeUsers;

  # Active users that actually have a password secret file on disk. The
  # user-password wiring is gated on the file existing so a host with
  # secretsPath set but a missing per-user secret still evaluates.
  usersWithSecret =
    if secretsPath == null
    then []
    else lib.filter (userName: builtins.pathExists (secretsPath + "/users/${userName}.yaml")) activeUsers;

  # Home Manager module that maps a user's omninix.persistence.{directories,files}
  # into impermanence's home.persistence whenever the host actually has a
  # "/persist" store enabled (impermanence relativizes "/persist" to the user's
  # home -> /persist/home/<user>). Keyed on the persistence store being active,
  # NOT on any particular role name, so it works no matter what the consumer
  # calls their impermanence role.
  #
  # This lives here rather than in modules/home because modules/home is also
  # imported by standalone homeConfigurations, where impermanence's HM module —
  # and thus the home.persistence option — does not exist. It is added per-user
  # only when the impermanence input is present (osConfig and home.persistence
  # are both guaranteed in that NixOS+HM context).
  impermanenceHomeModule = {
    config,
    lib,
    options,
    osConfig,
    ...
  }: {
    # optionalAttrs: home.persistence only exists where impermanence's NixOS
    # module is imported, so hosts without it must not define it at all.
    config = lib.optionalAttrs (options.home ? persistence) (lib.mkIf (osConfig.environment.persistence."/persist".enable or false) {
      home.persistence."/persist" = {
        directories = config.omninix.persistence.directories;
        files = config.omninix.persistence.files;
      };
    });
  };
in {
  imports = [./core.nix];

  config = lib.mkMerge [
    {omninix.internal.secretsPath = secretsPath;}

    (lib.mkIf (activeUsers != []) {
      # sops-backed passwords for users with a secret file (see core.nix for
      # the fail-closed check that reads them).
      users.users = lib.genAttrs usersWithSecret (userName: {
        hashedPasswordFile = config.sops.secrets."user-password-${userName}".path;
      });

      home-manager = {
        extraSpecialArgs = {
          inherit inputs secretsPath;
        };
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = lib.mkDefault "bak";
        # Per-user imports come from the shared mkHomeModules helper (see
        # lib/mkHomeModules.nix) so they stay identical to the standalone
        # homeConfigurations path. stateVersion is always defaulted (mkDefault)
        # so a user file may override it but is never required to set it.
        users = lib.genAttrs activeUsers (
          userName: let
            imports =
              mkHomeModules {
                inherit inputs lib profiles homeManagerModules userName secretsPath;
                userFile = users.${userName} or null;
              }
              ++ lib.optional (inputs ? impermanence) impermanenceHomeModule;
          in {
            inherit imports;
            # Frozen: never bump with the nixpkgs pin. Users who don't set it
            # would silently move to a newer stateVersion.
            home.stateVersion = lib.mkDefault "26.05";
          }
        );
      };
    })

    # sops plumbing — referenced ONLY when secretsPath is set. Uses optionalAttrs
    # (not mkIf) so the `sops` option is genuinely absent otherwise: a `mkIf
    # false` would still register the option path and force every secret-less
    # host to import the sops-nix module (which is only auto-wired when present).
    (lib.optionalAttrs (secretsPath != null) {
      sops =
        {
          # Per-user password secrets, decrypted before login. Empty (no-op)
          # when secretsPath is set but no per-user secret files exist.
          secrets = lib.mkMerge (map (userName: {
              "user-password-${userName}" = {
                sopsFile = secretsPath + "/users/${userName}.yaml";
                key = "hashed-password";
                neededForUsers = true;
              };
            })
            usersWithSecret);

          # Age key source (impermanence-aware) + default format, so consumers
          # can declare `sops.secrets.<name> = {}` against the host file.
          age.sshKeyPaths =
            if (config.environment.persistence."/persist".enable or false)
            then ["/persist/etc/ssh/ssh_host_ed25519_key"]
            else ["/etc/ssh/ssh_host_ed25519_key"];
          defaultSopsFormat = "yaml";
        }
        # Host-default sops file, only when it actually exists. Keys are disjoint
        # from the set above, so this shallow merge is safe.
        // lib.optionalAttrs (builtins.pathExists (secretsPath + "/${hostName}.yaml")) {
          defaultSopsFile = secretsPath + "/${hostName}.yaml";
        };
    })
  ];
}
