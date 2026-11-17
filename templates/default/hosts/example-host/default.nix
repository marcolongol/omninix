# A host: becomes nixosConfigurations.example-host (rename the directory to
# rename the host; that's also its hostname).
{
  imports = [./hardware-configuration.nix];

  system.stateVersion = "26.05";
  boot.loader.systemd-boot.enable = true;

  roles.common.enable = true;

  # Users on this host. Groups are opt-in: wheel means sudo.
  omninix.hostUsers.example-user = {
    enable = true;
    extraGroups = ["wheel"];
  };

  # FIRST INSTALL ONLY: builds without a password for example-user, so
  # passwordless login works. Give them a password (secrets/README.md), then
  # delete this line; the build refuses passwordless users without it.
  omninix.allowInsecureBootstrap = true;
}
