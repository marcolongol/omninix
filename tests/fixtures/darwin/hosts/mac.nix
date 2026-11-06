# Minimal Mac host: one OmniNix user, the role with halves on both platforms.
{
  system.stateVersion = 6;
  omninix.hostUsers.alice.enable = true;
  roles.both.enable = true;
}
