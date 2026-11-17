# omninix.secrets on NixOS and nix-darwin hosts: where the secretsPath
# conventions put files a host's own modules may want by path. Imported by
# each platform's secrets module, with the fleet.
{fleet}: {lib, ...}: {
  options.omninix.secrets.shared = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    readOnly = true;
    default = fleet.secretFile "shared";
    defaultText = lib.literalExpression ''"<secretsPath>/shared.yaml", or null without one'';
    example = lib.literalExpression "{ sops.secrets.wifi.sopsFile = config.omninix.secrets.shared; }";
    description = "`<secretsPath>/shared.yaml`, for secrets every host uses; null when there's no such file. Each secret in it is declared as usual, with this as its sopsFile.";
  };
}
