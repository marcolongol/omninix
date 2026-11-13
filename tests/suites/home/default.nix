# Home Manager users on NixOS hosts: every active user gets a home, built
# from their file in `users` when they have one.
{
  lib,
  inputs,
  evalHosts,
  ...
}: let
  # A host enabling `names` (with a password, so nothing else fails).
  hostWith = names: {
    omninix.hostUsers = lib.genAttrs names (_: {enable = true;});
    users.users = lib.genAttrs names (_: {hashedPassword = "$y$fake";});
  };

  # One host, `test`, with `enabled` users and the given user files.
  host = {
    enabled,
    users ? {},
    flakeInputs ? inputs,
  }:
    (evalHosts {
      hosts.test = hostWith enabled;
      inherit users;
      inputs = flakeInputs;
    })
    .test;

  aliceFile = {home.file.greeting.text = "hi";};
in {
  testUserFileApplied = {
    expr =
      (host {
        enabled = ["alice"];
        users.alice = aliceFile;
      })
      .home-manager
      .users
      .alice
      .home
      .file
      .greeting
      .text;
    expected = "hi";
  };

  # A user file only applies where the user is enabled.
  testInactiveUserHasNoHome = {
    expr =
      (host {
        enabled = [];
        users.alice = aliceFile;
      })
      .home-manager
      .users
      ? alice;
    expected = false;
  };

  # An active user without a file still gets a home (for profiles later).
  testActiveUserWithoutFileGetsHome = {
    expr = lib.attrNames (host {enabled = ["bob"];}).home-manager.users;
    expected = ["bob"];
  };

  testStateVersionDefault = {
    expr = (host {enabled = ["bob"];}).home-manager.users.bob.home.stateVersion;
    expected = "26.05";
  };

  testUserCanSetStateVersion = {
    expr =
      (host {
        enabled = ["alice"];
        users.alice = {home.stateVersion = "25.11";};
      })
      .home-manager
      .users
      .alice
      .home
      .stateVersion;
    expected = "25.11";
  };

  # Homes use the host's pkgs and install into the user's profile.
  testSharedPkgs = {
    expr = let
      hm = (host {enabled = ["bob"];}).home-manager;
    in {inherit (hm) useGlobalPkgs useUserPackages;};
    expected = {
      useGlobalPkgs = true;
      useUserPackages = true;
    };
  };

  # User files receive the flake inputs, like host files do.
  testUserFileGetsInputs = {
    expr =
      (host {
        enabled = ["alice"];
        users.alice = {inputs, ...}: {home.file.probe.text = toString (inputs ? nixpkgs);};
      })
      .home-manager
      .users
      .alice
      .home
      .file
      .probe
      .text;
    expected = "1";
  };

  # Without a home-manager input, user files can't be applied: say so.
  testUsersWithoutHomeManagerThrows = {
    expr =
      (builtins.tryEval (host {
        enabled = ["alice"];
        users.alice = aliceFile;
        flakeInputs = removeAttrs inputs ["home-manager"];
      }))
      .success;
    expected = false;
  };

  # ...but with no user files, a flake without home-manager is fine.
  testNoUsersNoHomeManagerIsFine = {
    expr =
      (host {
        enabled = ["bob"];
        flakeInputs = removeAttrs inputs ["home-manager"];
      })
      .omninix
      .activeUsers;
    expected = ["bob"];
  };
}
