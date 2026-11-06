# darwinModulesDir internal/ entry, not exported.
{lib, ...}: {
  options.fixture.darwinModulePrivate = lib.mkOption {default = true;};
}
