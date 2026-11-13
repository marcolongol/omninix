# A role file: NixOS hosts only.
{lib, ...}: {options.roles.linux-only.enable = lib.mkEnableOption "linux-only";}
