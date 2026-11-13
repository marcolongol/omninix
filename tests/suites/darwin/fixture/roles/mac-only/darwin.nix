# Only a darwin half: Macs only.
{lib, ...}: {options.roles.mac-only.enable = lib.mkEnableOption "mac-only";}
