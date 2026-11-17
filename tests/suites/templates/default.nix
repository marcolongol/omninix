# The templates, as a new user gets them: the default template's own
# flake.nix, and each component template dropped into a fleet. Everything is
# evaluated down to its derivation (assertions included), not built.
{
  lib,
  inputs,
  ...
}: let
  templates = ../../../templates;

  # The default template's flake, with this checkout as its `omninix` input.
  fleet = (import (templates + "/default/flake.nix")).outputs (inputs // {omninix = inputs.self;});

  # Evaluating a derivation's path runs every assertion; the path itself
  # doesn't matter.
  evaluates = drv: builtins.isString (builtins.unsafeDiscardStringContext drv.drvPath);
in {
  testExported = {
    expr = lib.attrNames inputs.self.templates;
    expected = ["darwin-host" "default" "host" "profile" "role" "user"];
  };

  testDefaultOutputs = {
    expr = {
      hosts = lib.attrNames fleet.nixosConfigurations;
      homes = lib.attrNames fleet.homeConfigurations;
    };
    expected = {
      hosts = ["example-host"];
      homes = ["example-user"];
    };
  };

  # The host builds as shipped (bootstrap on), named after its directory.
  testDefaultHost = {
    expr = let
      host = fleet.nixosConfigurations.example-host;
    in {
      evaluates = evaluates host.config.system.build.toplevel;
      hostName = host.config.networking.hostName;
      git = host.config.home-manager.users.example-user.programs.git.enable;
    };
    expected = {
      evaluates = true;
      hostName = "example-host";
      git = true;
    };
  };

  testDefaultHome = {
    expr = evaluates fleet.homeConfigurations.example-user.activationPackage;
    expected = true;
  };

  # Each component template, as `nix flake new -t …#<template>` would add it,
  # with its placeholder names (myrole, myprofile) kept.
  testComponentsFitInAFleet = {
    expr = let
      host =
        (lib.omninix.mkNixosConfigurations {
          inherit inputs;
          hosts.new = {
            imports = [(templates + "/host")];
            roles.myrole.enable = true;
            omninix.hostUsers.new-user.enable = true;
            omninix.allowInsecureBootstrap = true;
          };
          users.new-user = {
            imports = [(templates + "/user")];
            profiles.myprofile.enable = true;
          };
          roles.myrole = templates + "/role";
          profiles.myprofile = templates + "/profile";
        })
        .new;
    in
      evaluates host.config.system.build.toplevel;
    expected = true;
  };

  testDarwinHost = {
    expr =
      evaluates
      (lib.omninix.mkDarwinConfigurations {
        inherit inputs;
        hosts.new-mac = templates + "/darwin-host";
        hostSystems.new-mac = "aarch64-darwin";
      }).new-mac.config.system.build.toplevel;
    expected = true;
  };
}
