# secretsPath on darwin hosts: `<host>.yaml` is the host's default sops file.
# There are no password secrets: macOS manages passwords itself. Applied
# with importApply, like modules/nixos/secrets.nix.
{fleet}: {
  lib,
  hostName,
  ...
}: let
  hostFile = fleet.secretFile hostName;
in {
  config = lib.mkIf (hostFile != null) {
    sops.defaultSopsFile = lib.mkDefault hostFile;
  };
}
