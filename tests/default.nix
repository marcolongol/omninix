# The eval test suites, one flake check each.
#
# Every entry of suites/ (a `<name>.nix` file or a `<name>/` directory with
# default.nix) is a suite: a function taking { lib, inputs, ... } and
# returning { testFoo = { expr = …; expected = …; }; … }. It becomes
# checks.<system>.<name>, so adding a suite needs no wiring.
{
  pkgs,
  lib,
  inputs,
}: let
  # Turn a test set into a derivation that builds if every case passes,
  # printing each failure otherwise.
  mkSuite = name: tests: let
    failures = lib.runTests tests;

    report = lib.concatMapStringsSep "\n" (f: ''
      ✗ ${f.name}
          expected: ${lib.generators.toPretty {multiline = false;} f.expected}
          got:      ${lib.generators.toPretty {multiline = false;} f.result}'')
    failures;
  in
    pkgs.runCommand "omninix-tests-${name}" {
      inherit report;
      failed = toString (builtins.length failures);
    } ''
      if [ "$failed" = 0 ]; then
        touch "$out"
      else
        echo "$failed failing test(s):" >&2
        printf '%s\n' "$report" >&2
        exit 1
      fi
    '';
in
  lib.mapAttrs (name: suite: mkSuite name (import suite {inherit lib inputs;}))
  (lib.omninix.discoverNixFiles ["default.nix"] ./suites)
