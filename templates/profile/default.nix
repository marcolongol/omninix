# Rename `myprofile` below to match this directory's name, then enable it for a
# user with `profiles.<name>.enable = true;`.
{ config, lib, pkgs, ... }:

{
  options.profiles.myprofile.enable = lib.mkEnableOption "myprofile";

  config = lib.mkIf config.profiles.myprofile.enable {
    # Home Manager configuration for this profile:
    # home.packages = with pkgs; [ ];
    # programs.foo.enable = true;

    # Same patterns as roles for third-party modules (docs/sharing.md):
    # omninix.requirements, and lib.optionalAttrs (options ? programs.foo) { ... }.
  };
}

# Profiles are exported for other flakes to reuse. One that reads your flake
# `inputs` or holds personal values belongs in profiles/internal/ instead.
