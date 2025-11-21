# Rename `myprofile` below to match this directory's name, then enable it for a
# user with `profiles.<name>.enable = true;`.
{ config, lib, pkgs, ... }:

{
  options.profiles.myprofile.enable = lib.mkEnableOption "myprofile";

  config = lib.mkIf config.profiles.myprofile.enable {
    # Home Manager configuration for this profile:
    # home.packages = with pkgs; [ ];
    # programs.foo.enable = true;
  };
}
