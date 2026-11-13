# OmniNix's NixOS module: users and the password rule.
#
# A host enables users with omninix.hostUsers. Each active user becomes a
# normal user with no privileged groups unless granted, and the host refuses
# to build while an active user has no password (unless it explicitly opts
# into an insecure bootstrap).
{
  config,
  lib,
  ...
}: let
  cfg = config.omninix;

  activeUsers = lib.attrNames (lib.filterAttrs (_: u: u.enable) cfg.hostUsers);

  # Does the user have a password, by any of NixOS' five options? This reads
  # the final option values (whatever set them), so a mkForce null still
  # fails. An empty string doesn't count: it logs in without a password.
  hasPassword = name: let
    u = config.users.users.${name};
    set = v: v != null && v != "";
  in
    lib.any set [u.hashedPasswordFile u.hashedPassword u.initialHashedPassword u.initialPassword u.password];

  usersWithoutPassword = lib.filter (name: !(hasPassword name)) activeUsers;
  bootstrapping = cfg.allowInsecureBootstrap && usersWithoutPassword != [];
in {
  options.omninix = {
    hostUsers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "this user on this host";
          extraGroups = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Groups for this user on top of omninix.defaultUserGroups. Grant privileged groups (wheel, docker) here, per user.";
          };
        };
      });
      default = {};
      example = {
        alice = {
          enable = true;
          extraGroups = ["wheel"];
        };
      };
      description = "Users to enable on this host.";
    };

    activeUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = activeUsers;
      defaultText = lib.literalExpression "names of the enabled omninix.hostUsers";
      description = "Names of the users enabled on this host. Read-only; use it instead of filtering omninix.hostUsers again.";
    };

    defaultUserGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Groups every active user joins. Empty by default: no one gets wheel or docker without asking.";
    };

    allowInsecureBootstrap = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Build even if an active user has no password, allowing passwordless login. For a first install only.";
    };
  };

  # Only hosts that use hostUsers are touched.
  config = lib.mkIf (activeUsers != []) {
    users = {
      users = lib.genAttrs activeUsers (name: {
        isNormalUser = true;
        extraGroups = cfg.defaultUserGroups ++ cfg.hostUsers.${name}.extraGroups;
      });

      # Users come from the config alone, so a password change in the config
      # reaches the machine. A host can turn this back on.
      mutableUsers = lib.mkDefault false;

      # Passwordless login only while bootstrapping AND someone lacks a
      # password.
      allowNoPasswordLogin = lib.mkDefault bootstrapping;
    };

    assertions = [
      {
        assertion = cfg.allowInsecureBootstrap || usersWithoutPassword == [];
        message = ''
          OmniNix: no password for active user(s): ${toString usersWithoutPassword}

          Set one with an encrypted `hashed-password` in <secretsPath>/users/<name>.yaml,
          or with users.users.<name>.hashedPasswordFile (or hashedPassword).
          For a first install only, omninix.allowInsecureBootstrap = true builds
          with passwordless login instead.
        '';
      }
    ];

    warnings = lib.optional bootstrapping ''
      OmniNix: omninix.allowInsecureBootstrap is on and ${toString usersWithoutPassword} can log in
      without a password. Set a password and turn it off before deploying.
    '';
  };
}
