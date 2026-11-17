# A role: imported by every host, off until a host sets roles.common.enable.
{
  config,
  lib,
  pkgs,
  ...
}: {
  options.roles.common.enable = lib.mkEnableOption "what every host here needs";

  config = lib.mkIf config.roles.common.enable {
    nix.settings.experimental-features = ["nix-command" "flakes"];
    networking.networkmanager.enable = true;
    environment.systemPackages = [pkgs.git pkgs.vim];

    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };
  };
}
