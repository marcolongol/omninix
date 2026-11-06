# darwinModulesDir entry, exported.
{lib, ...}: {
  options.fixture.darwinModule = lib.mkOption {default = true;};
}
