# A profile: imported by every home, off until a user sets
# profiles.common.enable.
{
  config,
  lib,
  ...
}: {
  options.profiles.common.enable = lib.mkEnableOption "what every user here wants";

  config = lib.mkIf config.profiles.common.enable {
    programs.bash.enable = true;
    programs.direnv.enable = true;
  };
}
