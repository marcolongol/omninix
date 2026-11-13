# sops-nix on darwin hosts: imported whenever the flake has the input; with
# secretsPath, `<host>.yaml` is the host's default sops file. There are no
# password secrets: macOS manages passwords itself.
#
# Applied with importApply, like modules/nixos/secrets.nix.
{secretFile}: {
  lib,
  inputs,
  hostName,
  ...
}: let
  hostFile = secretFile hostName;
in {
  imports = [inputs.sops-nix.darwinModules.sops];

  config = lib.mkIf (hostFile != null) {
    sops.defaultSopsFile = lib.mkDefault hostFile;
  };
}
