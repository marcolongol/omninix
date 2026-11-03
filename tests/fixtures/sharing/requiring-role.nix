# Sharing fixture: a role that needs fixtureDep and guards its settings on it.
{
  config,
  lib,
  options,
  ...
}: {
  options.roles.requiring.enable = lib.mkEnableOption "requiring";
  config = lib.mkIf config.roles.requiring.enable (lib.mkMerge [
    {
      omninix.requirements = [
        {
          by = "roles.requiring";
          option = "fixtureDep.value";
          module = "the fixture dependency";
        }
      ];
    }
    (lib.optionalAttrs (options ? fixtureDep) {fixtureDep.value = "set";})
  ]);
}
