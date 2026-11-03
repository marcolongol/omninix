# Portability fixture: a third-party module a shared role may require.
{lib, ...}: {options.fixtureDep.value = lib.mkOption {type = lib.types.str; default = "";};}
