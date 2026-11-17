# A new NixOS host: its directory name is its name and hostname. Replace the
# placeholder hardware-configuration.nix on the machine with:
#   nixos-generate-config --show-hardware-config
{
  imports = [./hardware-configuration.nix];

  system.stateVersion = "26.05";
  boot.loader.systemd-boot.enable = true;

  # Roles and users for this host:
  # roles.common.enable = true;
  # omninix.hostUsers.<user> = { enable = true; extraGroups = ["wheel"]; };
}
