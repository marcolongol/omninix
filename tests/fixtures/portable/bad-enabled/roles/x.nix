# Not portable: an unreadable error when enabled.
{
  config,
  lib,
  ...
}: {
  options.roles.x.enable = lib.mkEnableOption "x";
  config = lib.mkIf config.roles.x.enable {assertions = [(throw "boom")];};
}
