# secretsPath on darwin hosts: `<host>.yaml` is the host's default sops file,
# and shared.yaml is omninix.secrets.shared.
# There are no password secrets: macOS manages passwords itself. Applied
# with importApply, like modules/nixos/secrets.nix.
{fleet}: {
  lib,
  hostName,
  ...
}: let
  hostFile = fleet.secretFile hostName;
in {
  imports = [(lib.modules.importApply ../shared/secrets.nix {inherit fleet;})];

  config = lib.mkIf (hostFile != null) {
    sops.defaultSopsFile = lib.mkDefault hostFile;
  };
}
