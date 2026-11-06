# Minimal NixOS host next to the Mac, with the same role on.
{
  boot.isContainer = true;
  system.stateVersion = "26.05";
  omninix.hostUsers.alice.enable = true;
  omninix.allowInsecureBootstrap = true;
  roles.both.enable = true;
}
