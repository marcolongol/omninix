# The flake checks: the eval suites, plus the builds.
#
# Every entry of suites/ (a `<name>.nix` file or a `<name>/` directory with
# default.nix) is a suite: a function taking { lib, inputs, evalHosts,
# evalFlake, failures, ... } (the helpers below) and
# returning { testFoo = { expr = …; expected = …; }; … }. It becomes
# checks.<system>.<name>, so adding a suite needs no wiring.
#
# Every entry of builds/ is a function taking { pkgs, lib, inputs } and
# returning { checkName = derivation; }: real builds and VM tests, which
# return {} on systems they can't run on.
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

  # A consumer flake: OmniNix's flake module plus `module` (its omninix
  # settings, and anything else), for x86_64-linux.
  #
  # Example: (evalFlake {omninix.hostsDir = ./hosts;}).nixosConfigurations
  evalFlake = module:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [inputs.self.flakeModules.default module];
      systems = ["x86_64-linux"];
    };

  # OmniNix's failing assertions in a host or home config, as messages.
  # NixOS and Home Manager add their own; only ours start with "OmniNix:".
  failures = config:
    map (a: a.message) (lib.filter (a: !a.assertion && lib.hasPrefix "OmniNix:" a.message) config.assertions);

  # Turn a test set that builds if every case passes,
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

  suites =
    lib.mapAttrs (name: suite: mkSuite name (import suite {inherit lib inputs evalHosts evalFlake failures;}))
    (lib.omninix.discoverNixFiles ["default.nix"] ./suites);

  builds =
    lib.concatMapAttrs (_: build: import build {inherit pkgs lib inputs;})
    (lib.omninix.discoverNixFiles ["default.nix"] ./builds);
in
  suites // builds
