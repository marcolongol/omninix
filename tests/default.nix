# The eval test suites, one flake check each.
#
# Every entry of suites/ (a `<name>.nix` file or a `<name>/` directory with
# default.nix) is a suite: a function taking { lib, inputs, evalHosts, ... } and
# returning { testFoo = { expr = …; expected = …; }; … }. It becomes
# checks.<system>.<name>, so adding a suite needs no wiring.
{
  pkgs,
  lib,
  inputs,
}: let
  # Build test hosts with mkNixosConfigurations and return each one's
  # evaluated config. Each host is wrapped with a stateVersion, which NixOS
  # warns about when unset.
  #
  # Example: (evalHosts {hosts.laptop = {};}).laptop.networking.hostName
  evalHosts = args:
    lib.mapAttrs (_: host: host.config) (lib.omninix.mkNixosConfigurations ({inherit inputs;}
      // args
      // {
        hosts =
          lib.mapAttrs (_: host: {
            imports = [host];
            system.stateVersion = "26.05";
          })
          args.hosts;
      }));

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
  lib.mapAttrs (name: suite: mkSuite name (import suite {inherit lib inputs evalHosts;}))
  (lib.omninix.discoverNixFiles ["default.nix"] ./suites)
