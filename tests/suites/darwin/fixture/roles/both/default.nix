# The NixOS half.
{lib, ...}: {options.roles.both.enable = lib.mkEnableOption "both (NixOS half)";}
