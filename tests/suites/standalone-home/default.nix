# mkHomeConfigurations: the same user files as on hosts, as standalone
# homes for `home-manager switch`.
{
  lib,
  inputs,
  ...
}: let
  # Build `users` as standalone homes and return each one's config.
  homes = args: lib.mapAttrs (_: home: home.config) (lib.omninix.mkHomeConfigurations ({inherit inputs;} // args));
in {
  # Identity comes from the user's name, defaulted so the file can change it.
  testIdentityFromName = {
    expr = let
      c = (homes {users.alice = {};}).alice;
    in {inherit (c.home) username homeDirectory stateVersion;};
    expected = {
      username = "alice";
      homeDirectory = "/home/alice";
      stateVersion = "26.05";
    };
  };

  testHomeDirectoryByPlatform = {
    expr = lib.mapAttrs (_: c: c.home.homeDirectory) (homes {
      users = {
        alice = {};
        mac = {};
        root = {};
      };
      userSystems.mac = "aarch64-darwin";
    });
    expected = {
      alice = "/home/alice";
      mac = "/Users/mac";
      root = "/root";
    };
  };

  testUserFileApplied = {
    expr = (homes {users.alice = {home.file.greeting.text = "hi";};}).alice.home.file.greeting.text;
    expected = "hi";
  };

  testUserFileCanOverrideIdentity = {
    expr = (homes {users.alice = {home.homeDirectory = "/srv/alice";};}).alice.home.homeDirectory;
    expected = "/srv/alice";
  };

  # pkgs follows the user's system: defaultSystem unless userSystems says so.
  testPkgsFollowUserSystem = {
    expr = lib.mapAttrs (_: c: c.home.file.probe.text) (homes {
      users = let
        probe = {pkgs, ...}: {home.file.probe.text = pkgs.stdenv.hostPlatform.system;};
      in {
        alice = probe;
        mac = probe;
      };
      userSystems.mac = "aarch64-darwin";
    });
    expected = {
      alice = "x86_64-linux";
      mac = "aarch64-darwin";
    };
  };

  testUserFileGetsInputs = {
    expr =
      (homes {
        users.alice = {inputs, ...}: {home.file.probe.text = toString (inputs ? nixpkgs);};
      })
      .alice
      .home
      .file
      .probe
      .text;
    expected = "1";
  };

  testUnknownUserSystemThrows = {
    expr =
      (builtins.tryEval (homes {
        users.alice = {};
        userSystems.alcie = "aarch64-darwin";
      }))
      .success;
    expected = false;
  };

  testNoHomeManagerThrows = {
    expr =
      (builtins.tryEval (homes {
        users.alice = {};
        inputs = removeAttrs inputs ["home-manager"];
      }))
      .success;
    expected = false;
  };
}
