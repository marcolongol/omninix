{ config, lib, pkgs, ... }:

{
  options.roles.common.enable = lib.mkEnableOption "common system configuration";

  config = lib.mkIf config.roles.common.enable {
    # Timezone
    time.timeZone = lib.mkDefault "America/New_York";

    # Networking
    networking.networkmanager.enable = lib.mkDefault true;

    # Essential system packages
    environment.systemPackages = with pkgs; [
      vim
      git
      curl
      wget
      htop
    ];

    # SSH configuration
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    # Nix settings
    nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };

    # Garbage collection
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };

    # NOTE: wheelNeedsPassword is left at its secure NixOS default (true).
    # If you want passwordless sudo, opt in explicitly here:
    #   security.sudo.wheelNeedsPassword = false;
  };
}
