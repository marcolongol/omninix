{ config, lib, pkgs, ... }:

{
  home.stateVersion = "26.05";

  # Profiles this user wants enabled (enable-based)
  profiles = {
    common.enable = true;
    # Add more profiles as needed:
    # developer.enable = true;
    # gamer.enable = true;
  };

  # User-specific packages
  home.packages = with pkgs; [
    # Add your packages here
  ];

  # Git configuration
  programs.git = {
    enable = true;
    settings.user = {
      name = "Your Name";
      email = "your.email@example.com";
    };
  };

  # Add your user-specific configuration here
}
