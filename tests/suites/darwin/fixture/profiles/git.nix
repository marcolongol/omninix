{
  config,
  lib,
  ...
}: {
  options.profiles.git.enable = lib.mkEnableOption "git";
  config = lib.mkIf config.profiles.git.enable {programs.git.enable = true;};
}
