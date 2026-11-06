# OmniNix darwin module for the builders: the darwin core (core.nix, also
# exported as darwinModules.default) plus Home Manager users
# (../home-manager.nix, shared with NixOS hosts) and sops defaults.
{
  lib,
  hostName,
  secretsPath,
  ...
}: {
  imports = [./core.nix ../home-manager.nix];

  # As on NixOS: `sops` is only referenced when secretsPath is set. There are
  # no password secrets here; nix-darwin has no password options.
  config = lib.optionalAttrs (secretsPath != null) {
    sops =
      {
        age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
        defaultSopsFormat = "yaml";
      }
      // lib.optionalAttrs (builtins.pathExists (secretsPath + "/${hostName}.yaml")) {
        defaultSopsFile = secretsPath + "/${hostName}.yaml";
      };
  };
}
