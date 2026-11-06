# OmniNix flake checks.
#
# Exposes the eval test suites (Layer 1 lib, Layer 2 config-behaviour, Layer 2b
# flake entry points, Layer 2c standalone homes, Layer 2d darwin hosts) as a
# single `eval` derivation that fails — printing the offending cases — if any
# lib.runTests case's result differs from its expected value. `home` builds a
# standalone home on every system, `darwin` a nix-darwin system on darwin; the
# VM tests (Layer 4) are added on Linux.
#
# Run everything with: nix flake check
{
  pkgs,
  system,
  inputs,
  lib,
}: let
  omninix = lib.omninix;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

  # Layer 1 (pure lib) runs everywhere. Layer 2 evaluates NixOS configs, which
  # only exist on Linux, so it is gated — otherwise `nix flake check` would try
  # to evaluate NixOS-on-darwin for the darwin systems and fail.
  evalTests =
    (import ./lib-tests.nix {inherit omninix lib;})
    // (import ./home-tests.nix {inherit inputs omninix system;})
    // (import ./darwin-tests.nix {inherit inputs lib system;})
    // (lib.optionalAttrs isLinux (import ./config-tests.nix {inherit inputs omninix lib system;}))
    // (lib.optionalAttrs isLinux (import ./flake-tests.nix {inherit inputs lib system;}));

  failures = lib.runTests evalTests;

  # Render failures with toPretty so any Nix value is safe to print (functions,
  # attrsets, …), unlike toJSON.
  report = lib.concatMapStringsSep "\n" (f: ''
    ✗ ${f.name}
        expected: ${lib.generators.toPretty {multiline = false;} f.expected}
        got:      ${lib.generators.toPretty {multiline = false;} f.result}'')
  failures;

  eval =
    pkgs.runCommand "omninix-eval-tests" {
      inherit report;
      passed =
        if failures == []
        then "1"
        else "0";
      nFail = toString (builtins.length failures);
      nTotal = toString (builtins.length (builtins.attrNames evalTests));
    } ''
      if [ "$passed" = "1" ]; then
        echo "OmniNix eval tests: all $nTotal passed"
        touch "$out"
      else
        echo "OmniNix eval tests: $nFail of $nTotal failing" >&2
        printf '%s\n' "$report" >&2
        exit 1
      fi
    '';
in
  {
    inherit eval;
    # A real standalone Home Manager build, so macOS CI proves homes activate there.
    home =
      (omninix.mkHomeConfigurations {
        inherit inputs;
        defaultSystem = system;
        users.alice = ./fixtures/flake/users/alice.nix;
      })
      .alice
      .activationPackage;
  }
  // lib.optionalAttrs isDarwin {
    # A real nix-darwin system build (with a Home Manager user), which Linux
    # can only evaluate.
    darwin =
      (omninix.mkDarwinConfigurations {
        inherit inputs;
        hosts.mac = ./fixtures/darwin/hosts/mac.nix;
        hostSystems.mac = system;
        users.alice = ./fixtures/flake/users/alice.nix;
        roles = (omninix.splitRoles (omninix.discoverRoles ./fixtures/platforms/roles).all).darwin;
      })
      .mac
      .config
      .system
      .build
      .toplevel;
  }
  // lib.optionalAttrs isLinux {
    vm = import ./vm-test.nix {inherit pkgs inputs lib;};
    vm-impermanent = import ./vm-impermanent.nix {inherit pkgs inputs lib;};
  }
