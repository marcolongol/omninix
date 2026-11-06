# Sharing fixture: a third-party module a piece may require.
{lib, ...}: {
  options.fixtureDep.value = lib.mkOption {
    type = lib.types.str;
    default = "";
  };
}
