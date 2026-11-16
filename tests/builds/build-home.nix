# A standalone home, built for real on every system (activation package).
{
  pkgs,
  lib,
  inputs,
}: {
  build-home =
    (lib.omninix.mkHomeConfigurations {
      inherit inputs;
      defaultSystem = pkgs.stdenv.hostPlatform.system;
      users.alice = {home.file.greeting.text = "hi";};
    })
    .alice
    .activationPackage;
}
