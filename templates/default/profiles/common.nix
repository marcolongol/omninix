{ config, lib, pkgs, ... }:

{
  options.profiles.common.enable = lib.mkEnableOption "common home configuration";

  config = lib.mkIf config.profiles.common.enable {
    # Enable Home Manager
    programs.home-manager.enable = true;

    # Basic user packages
    home.packages = with pkgs; [
      vim
    ];

    # Shell configuration
    programs.bash.enable = lib.mkDefault true;

    # Co-located persistence: any profile/user adds dirs here; OmniNix routes them
    # to /persist/home/<user> when an impermanence role is on (inert otherwise).
    # omninix.persistence.directories = [ ".config/example-app" ];
    # omninix.persistence.files       = [ ".config/example-app/token" ];

    # Add common user environment configuration here
  };
}
