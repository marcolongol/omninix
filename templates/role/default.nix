# Rename `myrole` below to match this directory's name, then enable it on a host
# with `roles.<name>.enable = true;`.
{ config, lib, pkgs, ... }:

{
  options.roles.myrole.enable = lib.mkEnableOption "myrole";

  config = lib.mkIf config.roles.myrole.enable {
    # System-level configuration for this role:
    # environment.systemPackages = with pkgs; [ ];
    # services.foo.enable = true;

    # System paths to persist when impermanence is active:
    # omninix.persistence.directories = [ "/var/lib/foo" ];
  };
}
