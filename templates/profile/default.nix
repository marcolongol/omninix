# A new profile. Rename `myprofile` to this directory's name; a user turns it
# on with profiles.<name>.enable = true.
{
  config,
  lib,
  ...
}: {
  options.profiles.myprofile.enable = lib.mkEnableOption "myprofile";

  config = lib.mkIf config.profiles.myprofile.enable {
    # programs.foo.enable = true;
  };
}
