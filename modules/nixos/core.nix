# OmniNix secure core (nixosModules.default)
#
# The omninix.* host options and the security model, with no builder
# arguments: usable in any nixosSystem. modules/nixos adds the builder-only
# wiring (sops passwords, Home Manager users) on top.
{
  config,
  lib,
  ...
}: let
  cfg = config.omninix;

  # Users activated on this host (enable-based). Roles and profiles likewise
  # declare their own `options.roles.<name>.enable` / `profiles.<name>.enable`.
  activeUsers = lib.attrNames (lib.filterAttrs (_: u: u.enable) cfg.hostUsers);

  # Does an active user have a usable password? Checks the resolved options
  # (the sops wiring in modules/nixos sets hashedPasswordFile), not merely that
  # a secret file exists, so a mkForce null still fails closed. Empty strings
  # don't count: an empty (or empty-hashed) password logs in without one.
  # Reading each option lazily avoids a cycle with the users.users block we set.
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
in {
  imports = [../requirements.nix];

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

    activeUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = activeUsers;
      defaultText = lib.literalExpression "names of the enabled omninix.hostUsers";
      description = ''
        Names of the users enabled on this host (read-only). Use it in roles
        and hosts instead of re-filtering omninix.hostUsers, e.g.
        lib.genAttrs config.omninix.activeUsers (_: { ... }).
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
        description = "System directories to persist under /persist. Applied by roles.impermanent when it is enabled.";
      };
      files = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "System files to persist under /persist. Applied by roles.impermanent when it is enabled.";
      };
    };

    # Set by modules/nixos so the no-password message can name the real path.
    internal.secretsPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      internal = true;
      description = "The builders' secretsPath, for the no-password message only.";
    };
  };

  config = lib.mkIf (activeUsers != []) {
    # Fail closed: refuse to build with passwordless users unless the user
    # explicitly opted into insecure bootstrap.
    assertions = [
      {
        assertion = cfg.allowInsecureBootstrap || usersWithoutPassword == [];
        message = ''
          OmniNix: no password set for active user(s): ${toString usersWithoutPassword}

          Give each active user a password via one of:
            1. An encrypted secret at ${
            if cfg.internal.secretsPath == null
            then "<secretsPath>"
            else toString cfg.internal.secretsPath
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

    users.users = lib.genAttrs activeUsers (userName: {
      isNormalUser = true;
      home = "/home/${userName}";
      # No privileged groups by default — wheel/docker are opt-in via
      # omninix.defaultUserGroups (global) or per-user extraGroups.
      extraGroups = cfg.defaultUserGroups ++ cfg.hostUsers.${userName}.extraGroups;
    });
  };
}
