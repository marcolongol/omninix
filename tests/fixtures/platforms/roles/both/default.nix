# NixOS half: both halves declare roles.both.enable.
{lib, ...}: {
  options.roles.both.enable = lib.mkEnableOption "both";
  options.fixture.bothNixos = lib.mkOption {default = true;};
}
