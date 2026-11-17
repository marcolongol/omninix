# A new role. Rename `myrole` to this directory's name; a host turns it on
# with roles.<name>.enable = true. For Macs, add a darwin.nix next to this
# file declaring the same option.
{
  config,
  lib,
  ...
}: {
  options.roles.myrole.enable = lib.mkEnableOption "myrole";

  config = lib.mkIf config.roles.myrole.enable {
    # services.foo.enable = true;
  };
}
