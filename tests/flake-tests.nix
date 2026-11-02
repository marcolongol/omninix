# OmniNix Layer 2b — flake entry point tests (lib.runTests format).
#
# Pins mkFlake's output shape on a small fixture so the engine can be
# refactored (and wrapped) without changing what consumers get.
{
  inputs,
  omninix,
  lib,
  system,
}: let
  fixture = ./fixtures/flake;
  settings = {
    hostsDir = fixture + "/hosts";
    usersDir = fixture + "/users";
    packagesDir = fixture + "/packages";
    defaultSystem = system;
  };

  viaMkFlake = omninix.mkFlake inputs settings;
in {
  testMkFlakeOutputNames = {
    expr = builtins.attrNames viaMkFlake;
    expected = ["homeConfigurations" "hosts" "nixosConfigurations" "packages" "profiles" "roles" "users"];
  };

  testMkFlakeNoPackagesWithoutDir = {
    expr = omninix.mkFlake inputs {inherit (settings) hostsDir defaultSystem;} ? packages;
    expected = false;
  };

  testMkFlakeSystemsDefaultToDefaultSystem = {
    expr = builtins.attrNames viaMkFlake.packages;
    expected = [system];
  };

  testMkFlakePackagesMatchHostPkgs = {
    expr = viaMkFlake.packages.${system}.hello-fixture.drvPath;
    expected = viaMkFlake.nixosConfigurations.test.pkgs.hello-fixture.drvPath;
  };
}
