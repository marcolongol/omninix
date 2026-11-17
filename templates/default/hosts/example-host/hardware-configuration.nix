# A placeholder. On the machine, replace it with the real one:
#   nixos-generate-config --show-hardware-config > hosts/<host>/hardware-configuration.nix
{lib, ...}: {
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
  };
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
