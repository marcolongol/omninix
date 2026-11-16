# A Mac with a Home Manager user, built for real. Darwin only: Linux can
# evaluate a nix-darwin system (the darwin suite does) but not build one.
{
  pkgs,
  lib,
  inputs,
}:
lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
  build-darwin =
    (lib.omninix.mkDarwinConfigurations {
      inherit inputs;
      defaultSystem = pkgs.stdenv.hostPlatform.system;
      hosts.mac = {
        system.stateVersion = 6;
        omninix.hostUsers.alice.enable = true;
      };
      users.alice = {home.file.greeting.text = "hi";};
    })
    .mac
    .config
    .system
    .build
    .toplevel;
}
