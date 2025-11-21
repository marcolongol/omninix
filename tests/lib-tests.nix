# OmniNix Layer 1 — pure lib function tests (lib.runTests format).
#
# Each entry is { expr; expected; }; lib.runTests reports any where expr differs
# from expected. These cover the discovery/util/validation helpers that the
# launch review found broken or untested.
{
  omninix,
  lib,
}: let
  discoveryDir = ./fixtures/discovery;
in {
  # --- discovery -----------------------------------------------------------

  # H2 / L1: only `.nix` files and directories with default.nix are discovered;
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

  # A directory with default.nix keeps the original contract: it returns the list.
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

  # L2: pick throws (not a cryptic getAttrs error) on a missing name.
  testPickThrowsOnMissing = {
    expr = (builtins.tryEval (omninix.pick ["nope"] {a = 1;})).success;
    expected = false;
  };

  # --- validations (M2: now actually exercised) ----------------------------

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
