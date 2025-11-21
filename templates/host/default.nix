{ config, lib, pkgs, ... }:

{
  system.stateVersion = "26.05";

  imports = [
    ./hardware-config.nix
  ];

  # Boot — adjust for your hardware.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Set this to match this host directory's name.
  networking.hostName = "CHANGEME";

  # Roles this host assumes (enable-based).
  roles = {
    common.enable = true;
    # docker.enable = true;
  };

  # Users on this host. Privileged groups (wheel/docker) are opt-in via
  # extraGroups; omninix.defaultUserGroups applies to every active user.
  omninix.hostUsers = {
    # your-username = { enable = true; extraGroups = [ "wheel" ]; };
  };

  # OmniNix fails the build if an active user has no password. For the very
  # first install you can bootstrap with passwordless login — REMOVE once a
  # password is set (see the project README, "Users & Security"):
  # omninix.allowInsecureBootstrap = true;
}
