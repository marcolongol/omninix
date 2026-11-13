{
  system.stateVersion = "26.05";
  omninix.hostUsers.alice.enable = true;
  users.users.alice.hashedPassword = "$y$fake";
  roles.docker.enable = true;
}
