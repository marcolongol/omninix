# Another flake's role that is safe to share.
{lib, ...}: {options.roles.theirs.enable = lib.mkEnableOption "theirs";}
