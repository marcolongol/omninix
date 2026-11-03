# Not portable: sets a dependency's option without checking it exists.
{
  config,
  lib,
  ...
}: {
  options.roles.x.enable = lib.mkEnableOption "x";
  config = lib.mkIf config.roles.x.enable {fixtureDep.value = "x";};
}
