# Home Manager users on NixOS hosts: every active user gets a home, built
# from their file in `users` when they have one.
{
  lib,
  inputs,
  evalHosts,
  ...
}: let
  # A host `test` enabling `enabled` (with passwords, so nothing else fails),
  # given these user files, optionally without a home-manager input.
  host = {
    enabled,
    users ? {},
    withHomeManager ? true,
  }:
    (evalHosts {
      inherit users;
      inputs =
        if withHomeManager
        then inputs
        else removeAttrs inputs ["home-manager"];
      hosts.test = {
        omninix.hostUsers = lib.genAttrs enabled (_: {enable = true;});
        users.users = lib.genAttrs enabled (_: {hashedPassword = "$y$fake";});
      };
    })
    .test;

  # The host's homes, by user.
  homes = args: (host args).home-manager.users;

  aliceFile = {home.file.greeting.text = "hi";};
in {
  testUserFileApplied = {
    expr =
      (homes {
        enabled = ["alice"];
        users.alice = aliceFile;
      }).alice.home.file.greeting.text;
    expected = "hi";
  };

  # A user file only applies where the user is enabled.
  testInactiveUserHasNoHome = {
    expr =
      homes {
        enabled = [];
        users.alice = aliceFile;
      } ? alice;
    expected = false;
  };

  # An active user without a file still gets a home (for profiles).
  testActiveUserWithoutFileGetsHome = {
    expr = lib.attrNames (homes {enabled = ["bob"];});
    expected = ["bob"];
  };

  testStateVersionDefault = {
    expr = (homes {enabled = ["bob"];}).bob.home.stateVersion;
    expected = "26.05";
  };

  testUserCanSetStateVersion = {
    expr =
      (homes {
        enabled = ["alice"];
        users.alice = {home.stateVersion = "25.11";};
      }).alice.home.stateVersion;
    expected = "25.11";
  };

  # Homes use the host's pkgs and install into the user's profile.
  testSharedPkgs = {
    expr = {inherit ((host {enabled = ["bob"];}).home-manager) useGlobalPkgs useUserPackages;};
    expected = {
      useGlobalPkgs = true;
      useUserPackages = true;
    };
  };

  # User files receive the flake inputs, like host files do.
  testUserFileGetsInputs = {
    expr =
      (homes {
        enabled = ["alice"];
        users.alice = {inputs, ...}: {home.file.probe.text = toString (inputs ? nixpkgs);};
      }).alice.home.file.probe.text;
    expected = "1";
  };

  # Without a home-manager input, user files can't be applied: say so.
  testUsersWithoutHomeManagerThrows = {
    expr =
      (builtins.tryEval (host {
        enabled = ["alice"];
        users.alice = aliceFile;
        withHomeManager = false;
      })).success;
    expected = false;
  };

  # ...but with no user files, a flake without home-manager is fine.
  testNoUsersNoHomeManagerIsFine = {
    expr =
      (host {
        enabled = ["bob"];
        withHomeManager = false;
      }).omninix.activeUsers;
    expected = ["bob"];
  };
}
