# Portable profile.
{
  config,
  lib,
  ...
}: {
  options.profiles.tool.enable = lib.mkEnableOption "tool";
  config = lib.mkIf config.profiles.tool.enable {home.sessionVariables.TOOL = "1";};
}
