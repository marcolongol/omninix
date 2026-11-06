# OmniNix Layer 1 — pure lib function tests (lib.runTests format).
#
# Each entry is { expr; expected; }; lib.runTests reports any where expr differs
# from expected. These cover the discovery/util/validation helpers.
{
  omninix,
  lib,
}: let
  discoveryDir = ./fixtures/discovery;
  platformRoles = ./fixtures/platforms/roles;
  roleHalves = omninix.splitRoles (omninix.discoverRoles platformRoles).all;
in {
  # --- discovery -----------------------------------------------------------

  # Role directories count with a default.nix, a darwin.nix, or both;
  # internal/ works the same, and a directory with neither is ignored.
  testDiscoverRolesFindsDarwinHalves = {
    expr = {
      all = lib.attrNames (omninix.discoverRoles platformRoles).all;
      exportable = lib.attrNames (omninix.discoverRoles platformRoles).exportable;
    };
    expected = {
      all = ["both" "darwin-only" "file" "nixos-dir" "priv"];
      exportable = ["both" "darwin-only" "file" "nixos-dir"];
    };
  };

  # Other piece kinds still need default.nix: darwin.nix means nothing there.
  testDiscoverPiecesIgnoresDarwinOnly = {
    expr = lib.attrNames (omninix.discoverPieces platformRoles).all;
    expected = ["both" "file" "nixos-dir"];
  };

  # NixOS gets files and directories with default.nix, unchanged (the
  # directory path itself); darwin gets each darwin.nix.
  testSplitRolesHalves = {
    expr = {
      nixos = roleHalves.nixos;
      darwin = roleHalves.darwin;
    };
    expected = {
      nixos = {
        both = platformRoles + "/both";
        file = platformRoles + "/file.nix";
        nixos-dir = platformRoles + "/nixos-dir";
      };
      darwin = {
        both = platformRoles + "/both/darwin.nix";
        darwin-only = platformRoles + "/darwin-only/darwin.nix";
        priv = platformRoles + "/internal/priv/darwin.nix";
      };
    };
  };

  # A role given as a module, not a path, has nothing to look inside: it's
  # NixOS only, and reported as inline.
  testSplitRolesInlineIsNixosOnly = {
    expr = let
      halves = omninix.splitRoles {
        inline = {...}: {};
        both = platformRoles + "/both";
      };
    in {
      nixos = lib.attrNames halves.nixos;
      darwin = lib.attrNames halves.darwin;
      inherit (halves) inline;
    };
    expected = {
      nixos = ["both" "inline"];
      darwin = ["both"];
      inline = ["inline"];
    };
  };

  # Only `.nix` files and directories with default.nix are discovered;
  # stray README.md / notes.txt must be ignored.
  testDiscoveryIgnoresNonNix = {
    expr = lib.attrNames (omninix.forAllNixFiles discoveryDir (_: "found"));
    expected = ["role-a" "sub"];
  };

  # The discovered values are produced by the supplied function.
  testDiscoveryAppliesFunction = {
    expr = (omninix.forAllNixFiles discoveryDir (_: "x")).role-a;
    expected = "x";
  };

  # Discovered entries stay paths in the source tree, so a module can import
  # files outside its own directory.
  testDiscoveryKeepsPaths = {
    expr = (omninix.forAllNixFiles discoveryDir (fn: fn)).role-a;
    expected = discoveryDir + "/role-a.nix";
  };

  # Missing directory yields an empty set, not an error.
  testDiscoveryMissingDirEmpty = {
    expr = omninix.forAllNixFiles ./fixtures/does-not-exist (_: "x");
    expected = {};
  };

  # mkDirMap scans multiple dirs into a nested set keyed by the given names.
  testMkDirMapShape = {
    expr = lib.attrNames (omninix.mkDirMap {things = discoveryDir;}).things;
    expected = ["role-a" "sub"];
  };

  # A directory without default.nix: each .nix file is one overlay, name order.
  testLoadOverlaysDiscoversDir = {
    expr = map (o: o {} {}) (omninix.loadOverlays ./fixtures/overlays-dir);
    expected = [{a = 1;} {b = 2;}];
  };

  # A directory with default.nix is imported as-is and must return the list.
  testLoadOverlaysDefaultNixList = {
    expr = map (o: o {} {}) (omninix.loadOverlays ./fixtures/overlays-list);
    expected = [{x = 1;}];
  };

  # --- utils ---------------------------------------------------------------

  testMapAttrsMaybeDropsNulls = {
    expr = omninix.mapAttrsMaybe (n: v:
      if v
      then lib.nameValuePair n "y"
      else null) {
      a = true;
      b = false;
    };
    expected = {a = "y";};
  };

  testPickSelectsSubset = {
    expr = omninix.pick ["a" "c"] {
      a = 1;
      b = 2;
      c = 3;
    };
    expected = {
      a = 1;
      c = 3;
    };
  };

  testDropRemoves = {
    expr = omninix.drop ["a"] {
      a = 1;
      b = 2;
    };
    expected = {b = 2;};
  };

  # pick throws (not a cryptic getAttrs error) on a missing name.
  testPickThrowsOnMissing = {
    expr = (builtins.tryEval (omninix.pick ["nope"] {a = 1;})).success;
    expected = false;
  };

  # --- validations ----------------------------

  testAssertIsStringOk = {
    expr = omninix.assertIsString "x" "hello";
    expected = true;
  };

  testAssertIsStringThrows = {
    expr = (builtins.tryEval (omninix.assertIsString "x" 5)).success;
    expected = false;
  };

  testAssertOneOfOk = {
    expr = omninix.assertOneOf "x" ["a" "b"] "b";
    expected = true;
  };

  testAssertOneOfThrows = {
    expr = (builtins.tryEval (omninix.assertOneOf "x" ["a" "b"] "z")).success;
    expected = false;
  };

  testAssertNotEmptyThrowsOnEmptyList = {
    expr = (builtins.tryEval (omninix.assertNotEmpty "x" [])).success;
    expected = false;
  };

  testAssertAllStringsOk = {
    expr = omninix.assertAllStrings "x" ["a" "b"];
    expected = true;
  };
}
