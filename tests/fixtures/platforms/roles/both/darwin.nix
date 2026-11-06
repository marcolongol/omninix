# darwin half: both halves declare roles.both.enable.
{lib, ...}: {
  options.roles.both.enable = lib.mkEnableOption "both";
  options.fixture.bothDarwin = lib.mkOption {default = true;};
}
