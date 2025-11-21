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
  cfg = config.omninix;

  # Users activated on this host (enable-based). Each role/profile module
  # self-declares its own `options.roles.<name>.enable` /
  # `profiles.<name>.enable`, so there is no central roles list option here.
  activeUsers = lib.attrNames (lib.filterAttrs (_: u: u.enable) cfg.hostUsers);

  # Active users that actually have a password secret file on disk. The
  # user-password wiring is gated on the file existing so a host with
  # secretsPath set but a missing per-user secret still evaluates.
  usersWithSecret =
    if secretsPath == null
    then []
    else lib.filter (userName: builtins.pathExists (secretsPath + "/users/${userName}.yaml")) activeUsers;

  # Does an active user have a usable password? Checks the resolved options
  # (the sops wiring below sets hashedPasswordFile), not merely that a secret
  # file exists, so a mkForce null still fails closed. Empty strings don't count:
  # an empty (or empty-hashed) password logs in without one. Reading each option
  # lazily avoids a cycle with the users.users block we set.
  hasPassword = userName: let
    u = config.users.users.${userName} or {};
    set = v: v != null && v != "";
  in
    set (u.hashedPasswordFile or null)
    || set (u.hashedPassword or null)
    || set (u.initialHashedPassword or null)
    || set (u.initialPassword or null)
    || set (u.password or null);

  usersWithoutPassword = lib.filter (userName: !(hasPassword userName)) activeUsers;
  bootstrapping = cfg.allowInsecureBootstrap && usersWithoutPassword != [];

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
  options.omninix = {
    hostUsers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "this user on this host";
          extraGroups = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = ''
              Extra groups for this user, added on top of
              omninix.defaultUserGroups. Grant privileged groups such as wheel
              (sudo) or docker (root-equivalent) here, explicitly, per user.
            '';
          };
        };
      });
      default = {};
      description = ''
        Users to enable on this host, e.g.
        { alice = { enable = true; extraGroups = [ "wheel" ]; }; }
      '';
    };

    defaultUserGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Groups every active OmniNix user is added to. Intentionally empty by
        default: wheel (sudo) and docker (root-equivalent) are NOT granted
        automatically — add them per user via
        omninix.hostUsers.<name>.extraGroups.
      '';
    };

    allowInsecureBootstrap = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Allow the system to build when an active user has no password,
        enabling passwordless login. INSECURE — intended only for initial
        bootstrap/testing. Leave false for production: the build then fails
        with a clear error until every active user has a password.
      '';
    };

    persistence = {
      directories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "System directories to persist under /persist when impermanence is active. Read by your own impermanence role.";
      };
      files = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "System files to persist under /persist when impermanence is active. Read by your own impermanence role.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (activeUsers != []) {
      # Fail closed: refuse to build with passwordless users unless the user
      # explicitly opted into insecure bootstrap.
      assertions = [
        {
          assertion = cfg.allowInsecureBootstrap || usersWithoutPassword == [];
          message = ''
            OmniNix: no password set for active user(s): ${toString usersWithoutPassword}

            Give each active user a password via one of:
              1. An encrypted secret at ${
              if secretsPath == null
              then "<secretsPath>"
              else toString secretsPath
            }/users/<name>.yaml (key: hashed-password), and set secretsPath.
              2. users.users.<name>.hashedPasswordFile / hashedPassword / initialPassword.

            For initial setup ONLY you may set:
              omninix.allowInsecureBootstrap = true;
            which builds with PASSWORDLESS login (INSECURE — set a password
            before deployment, then remove it).
          '';
        }
      ];

      # Declarative by default, but mutable so `passwd` works during bootstrap.
      users.mutableUsers = lib.mkDefault true;

      # Only ever allow passwordless login when the user explicitly opted into
      # insecure bootstrap AND some active user actually lacks a password.
      users.allowNoPasswordLogin = lib.mkDefault bootstrapping;

      warnings = lib.optional bootstrapping ''
        OmniNix: omninix.allowInsecureBootstrap is enabled and user(s) ${toString usersWithoutPassword}
        have no password — passwordless login is allowed. This is INSECURE: set a
        password and disable omninix.allowInsecureBootstrap before deployment.
      '';

      users.users = lib.genAttrs activeUsers (userName:
        {
          isNormalUser = true;
          home = "/home/${userName}";
          # No privileged groups by default — wheel/docker are opt-in via
          # omninix.defaultUserGroups (global) or per-user extraGroups.
          extraGroups = cfg.defaultUserGroups ++ cfg.hostUsers.${userName}.extraGroups;
        }
        // lib.optionalAttrs (lib.elem userName usersWithSecret) {
          hashedPasswordFile = config.sops.secrets."user-password-${userName}".path;
        });

      home-manager = {
        extraSpecialArgs = {
          inherit inputs secretsPath;
        };
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "bak";
        # Per-user imports come from the shared mkHomeModules helper (see
        # lib/default.nix) so they stay identical to the standalone
        # homeConfigurations path. stateVersion is always defaulted (mkDefault)
        # so a user file may override it but is never required to set it.
        users = lib.genAttrs activeUsers (
          userName: let
            imports =
              mkHomeModules {
                inherit inputs lib profiles homeManagerModules;
                userFile = users.${userName} or null;
              }
              ++ lib.optional (inputs ? impermanence) impermanenceHomeModule;
          in {
            inherit imports;
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
