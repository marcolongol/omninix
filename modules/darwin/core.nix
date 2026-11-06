# OmniNix darwin core (darwinModules.default)
#
# The omninix.* host user options for nix-darwin, with no builder arguments:
# usable in any darwinSystem. OmniNix doesn't create macOS accounts; it
# describes existing ones, as nix-darwin does by default. macOS manages
# passwords and groups itself, so the NixOS password and group checks have
# no darwin counterpart. modules/darwin adds the builder-only wiring.
{
  config,
  lib,
  ...
}: let
  cfg = config.omninix;
  activeUsers = lib.attrNames (lib.filterAttrs (_: u: u.enable) cfg.hostUsers);
  usersWithGroups = lib.filter (userName: cfg.hostUsers.${userName}.extraGroups != []) activeUsers;
in {
  imports = [../requirements.nix];

  options.omninix = {
    hostUsers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "this user on this host";
          # Declared so that setting it fails with an explanation rather
          # than "option does not exist".
          extraGroups = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "NixOS only. On darwin hosts, setting it is an error: macOS manages groups itself.";
          };
        };
      });
      default = {};
      description = ''
        Users to enable on this host, e.g. { alice.enable = true; }. They
        must already exist on the Mac.
      '';
    };

    activeUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = activeUsers;
      defaultText = lib.literalExpression "names of the enabled omninix.hostUsers";
      description = "Names of the users enabled on this host (read-only).";
    };
  };

  config = lib.mkIf (activeUsers != []) {
    assertions = [
      {
        assertion = usersWithGroups == [];
        message = ''
          OmniNix: omninix.hostUsers.<name>.extraGroups is NixOS only, but is set for
          ${toString usersWithGroups} on a darwin host. macOS manages groups itself
          (System Settings > Users & Groups); remove extraGroups here.
        '';
      }
    ];

    users.users = lib.genAttrs activeUsers (userName: {
      home = lib.mkDefault "/Users/${userName}";
    });

    # User-level nix-darwin settings (system.defaults, homebrew, …) apply to
    # the primary user; with a single user there's only one candidate.
    system.primaryUser = lib.mkIf (builtins.length activeUsers == 1) (lib.mkDefault (builtins.head activeUsers));
  };
}
