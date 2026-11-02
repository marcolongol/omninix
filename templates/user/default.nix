{ config, lib, pkgs, ... }:

{
  home.stateVersion = "26.05";

  # Profiles this user enables (enable-based).
  profiles = {
    common.enable = true;
    # developer.enable = true;   # contains unfree pkgs -> set omninix.allowUnfree = true in flake.nix
  };

  programs.git = {
    enable = true;
    settings.user = {
      name = "Your Name";
      email = "your.email@example.com";
    };
  };

  home.packages = with pkgs; [
    # personal packages
  ];

  # Files/folders to persist when impermanence is active (paths are
  # relative to $HOME):
  # omninix.persistence.directories = [ ".ssh" ".config/foo" ];
  # omninix.persistence.files = [ ".some-token" ];
}
