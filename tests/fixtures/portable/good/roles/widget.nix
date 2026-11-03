# Portable role: options only, requirement asserted, dep settings gated on the option.
# Not personal values (lint regression): version 10.1.1.339, path roles/desktop/home/browser.nix.
{
  config,
  lib,
  options,
  ...
}: {
  options.roles.widget.enable = lib.mkEnableOption "widget";

  config = lib.mkIf config.roles.widget.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = options ? fixtureDep;
          message = "roles.widget needs the fixtureDep module";
        }
      ];
    }
    (lib.optionalAttrs (options ? fixtureDep) {fixtureDep.value = "widget";})
  ]);
}
