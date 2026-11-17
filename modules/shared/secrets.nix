# shared.yaml on NixOS and nix-darwin hosts: secrets every host uses. Each of
# its top-level keys becomes sops.secrets.<key> on every host, read from it
# (root-only, as sops-nix defaults); a host adds owner, mode, etc. as usual.
# Imported by each platform's secrets module, with the fleet.
{fleet}: {lib, ...}: {
  options.omninix.secrets.shared = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    readOnly = true;
    default = fleet.sharedSecretsFile;
    defaultText = lib.literalExpression ''"<secretsPath>/shared.yaml", or null without one'';
    description = "`<secretsPath>/shared.yaml`, whose top-level keys OmniNix declares as secrets on every host; null when there's no such file.";
  };

  config.sops.secrets = lib.genAttrs fleet.sharedSecrets (_: {sopsFile = fleet.sharedSecretsFile;});
}
