# extraDarwinModules entry.
{lib, ...}: {
  options.fixture.darwinModuleExtra = lib.mkOption {default = true;};
}
