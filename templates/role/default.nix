# Rename `myrole` below to match this directory's name, then enable it on a host
# with `roles.<name>.enable = true;`.
{
  config,
  lib,
  pkgs,
  ...
}: {
  options.roles.myrole.enable = lib.mkEnableOption "myrole";

  config = lib.mkIf config.roles.myrole.enable {
    # System-level configuration for this role:
    # environment.systemPackages = with pkgs; [ ];
    # services.foo.enable = true;

    # System paths to persist when impermanence is active:
    # omninix.persistence.directories = [ "/var/lib/foo" ];

    # Configuring a third-party module? Add `options` to the arguments above,
    # set its options only when it's imported, and say what's missing if the
    # role can't work without it (docs/sharing.md):
    #   omninix.requirements = [{ by = "roles.myrole"; option = "foo.enable"; module = "foo's NixOS module"; }];
    #   with lib.mkMerge [ { ... } (lib.optionalAttrs (options ? foo) { foo.enable = true; }) ]
  };
}
# Roles are exported for other flakes to reuse. One that reads your flake
# `inputs` or holds personal values belongs in roles/internal/ instead.

