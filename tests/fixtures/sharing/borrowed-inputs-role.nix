# Sharing fixture: a role written for another flake that reads its `inputs`.
{
  config,
  lib,
  inputs,
  ...
}: {
  options.roles.borrowed.enable = lib.mkEnableOption "borrowed";
  config = lib.mkIf config.roles.borrowed.enable {environment.etc.borrowed.text = toString inputs.self;};
}
