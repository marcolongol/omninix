{ config, lib, pkgs, ... }:

{
  system.stateVersion = "26.05";

  imports = [
    ./hardware-config.nix
  ];

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking
  networking.hostName = "example-host";

  # ⚠️  BOOTSTRAP ONLY — REMOVE BEFORE DEPLOYING.
  # Lets this example build with a passwordless user. Set a real password
  # first (a sops secret at secrets/users/<name>.yaml, or
  # users.users.<name>.hashedPassword), then delete this line. With it gone,
  # OmniNix fails the build until every active user has a password.
  omninix.allowInsecureBootstrap = true;

  # Roles this host should assume (enable-based)
  roles = {
    common.enable = true;
    # Add more roles as needed:
    # desktop.enable = true;     # example role in roles/desktop/ — also
    #                            # configures every user's home (see home.nix)
    # impermanent.enable = true;   # omninix.roles.impermanent: ephemeral root, /persist kept.
    #                              # Uncomment the impermanence input in flake.nix and its
    #                              # extraNixosModules line there.
    #                              # Optional btrfs root wipe, after seeding /persist (docs/impermanence.md):
    #                              # impermanent.wipe = { enable = true; acknowledgeDataLoss = true; };
  };

  # Users who can access this host (enable-based).
  # Privileged groups are opt-in: grant wheel (sudo) / docker per user via
  # extraGroups. defaultUserGroups applies to every active user.
  omninix.hostUsers = {
    example-user = {
      enable = true;
      extraGroups = [ "wheel" ]; # this user can sudo; add "docker" etc. as needed
    };
  };

  # Host-specific configuration goes here
}
