{
  config,
  lib,
  ...
}: {
  options.roles.docker.enable = lib.mkEnableOption "docker";
  config = lib.mkIf config.roles.docker.enable {virtualisation.docker.enable = true;};
}
