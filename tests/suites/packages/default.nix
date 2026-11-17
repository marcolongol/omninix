# packagesDir, overlaysDir and allowUnfree: one package set for hosts, homes
# and the flake's own packages.
{
  lib,
  inputs,
  evalFlake,
  ...
}: let
  system = "x86_64-linux";
  fixture = ./fixture;

  # The fixture flake, plus `extra` (more modules or settings).
  fixtureFlake = extra:
    evalFlake {
      imports = [extra];
      omninix = {
        hostsDir = fixture + "/hosts";
        usersDir = fixture + "/users";
        packagesDir = fixture + "/packages";
        overlaysDir = fixture + "/overlays";
      };
    };

  flake = fixtureFlake {};

  # A flake whose perSystem exposes its pkgs, so tests can read it.
  withProbe = extra:
    fixtureFlake {
      imports = [extra];
      perSystem = {pkgs, ...}: {legacyPackages.pkgs = pkgs;};
    };

  # The three package sets that should agree.
  pkgsOf = f: {
    host = f.nixosConfigurations.laptop.pkgs;
    home = f.homeConfigurations.alice.pkgs;
    perSystem = f.legacyPackages.${system}.pkgs;
  };
in {
  # Packages and overlays reach hosts, standalone homes and perSystem alike.
  testEveryPackageSetHasThem = {
    expr = lib.mapAttrs (_: pkgs: {
      hello = pkgs ? hello-fixture;
      order = pkgs.omninixOrder;
    }) (pkgsOf (withProbe {}));
    expected = let
      same = {
        hello = true;
        order = ["a" "b"];
      };
    in {
      host = same;
      home = same;
      perSystem = same;
    };
  };

  # Overlays come after the packages, so they can override them.
  testOverlaysOverridePackages = {
    expr = flake.nixosConfigurations.laptop.pkgs.hello-fixture.overridden or false;
    expected = true;
  };

  # A package asking for `inputs` gets the flake's.
  testPackageGetsInputs = {
    expr = flake.nixosConfigurations.laptop.pkgs.inputs-fixture.text;
    expected = "1";
  };

  # packages.<system>: every package that builds there.
  testPackagesOutput = {
    expr = lib.attrNames flake.packages.${system};
    expected = ["hello-fixture" "inputs-fixture"];
  };

  # overlays.packages: for other flakes. Adds packages and nothing else; a
  # package needing our inputs can't be shared.
  testExportedOverlay = {
    expr = let
      pkgs = inputs.nixpkgs.legacyPackages.${system}.extend flake.overlays.packages;
    in {
      names = lib.attrNames flake.overlays;
      shared = pkgs ? hello-fixture && !(pkgs ? omninixOrder);
      inputs = (builtins.tryEval pkgs.inputs-fixture.name).success;
    };
    expected = {
      names = ["packages"];
      shared = true;
      inputs = false;
    };
  };

  testAllowUnfree = {
    expr = lib.mapAttrs (_: pkgs: pkgs.config.allowUnfree) (pkgsOf (withProbe {omninix.allowUnfree = true;}));
    expected = {
      host = true;
      home = true;
      perSystem = true;
    };
  };

  # Off by default, without overriding a host that turns it on itself.
  testHostCanAllowUnfreeAlone = {
    expr =
      (lib.omninix.mkNixosConfigurations {
        inherit inputs;
        hosts.h = {
          system.stateVersion = "26.05";
          nixpkgs.config.allowUnfree = true;
        };
      }).h.pkgs.config.allowUnfree;
    expected = true;
  };

  # Nothing set: no packages and no overlays outputs.
  testNothingConfigured = {
    expr = let
      f = evalFlake {};
    in {
      packages = f.packages.${system};
      overlays = f ? overlays && f.overlays != {};
    };
    expected = {
      packages = {};
      overlays = false;
    };
  };
}
