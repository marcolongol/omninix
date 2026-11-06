# omninix.requirements: a piece declares the modules it needs, and gets one
# readable error when they aren't imported. Shared by the NixOS, darwin and
# Home Manager modules (all have `assertions`).
{
  config,
  lib,
  options,
  ...
}: {
  options.omninix.requirements = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        by = lib.mkOption {
          type = lib.types.str;
          example = "roles.desktop";
          description = "What needs it, for the error message.";
        };
        option = lib.mkOption {
          type = lib.types.str;
          example = "stylix.image";
          description = "An option the module declares; its absence means the module isn't imported.";
        };
        module = lib.mkOption {
          type = lib.types.str;
          example = "stylix's NixOS module (inputs.stylix.nixosModules.stylix)";
          description = "What to import, for the error message.";
        };
      };
    });
    default = [];
    description = ''
      Modules the enabled pieces need. Declare them under the piece's enable
      condition; each missing one becomes a failed assertion. Settings for the
      module must still be guarded with `lib.optionalAttrs (options ? …)`,
      since setting an undeclared option is an error of its own.
    '';
  };

  config.assertions =
    map (r: {
      assertion = lib.hasAttrByPath (lib.splitString "." r.option) options;
      message = "${r.by} needs ${r.module}; import it (the option `${r.option}` doesn't exist).";
    })
    config.omninix.requirements;
}
