# Minimal container host: evaluates to a toplevel without disks or a bootloader.
{
  boot.isContainer = true;
  system.stateVersion = "26.05";
}
