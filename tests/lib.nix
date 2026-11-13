{
  pkgs,
  lib,
}: {
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
}
