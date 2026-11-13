# hostInputs / userInputs: one host or home built from different inputs,
# e.g. a Pi on nixpkgs-unstable while the fleet stays on stable.
{
  lib,
  inputs,
  evalHosts,
  ...
}: let
  # Stand-ins for "another nixpkgs" / "another home-manager": the real ones,
  # marking what they build so a test can tell which was used.
  markedNixpkgs =
    inputs.nixpkgs
    // {
      lib =
        inputs.nixpkgs.lib
        // {
          nixosSystem = args:
            inputs.nixpkgs.lib.nixosSystem (args // {modules = args.modules ++ [{environment.etc.marker.text = "nixpkgs";}];});
        };
      # An overlay, not `//`: Home Manager rebuilds the package set it's given,
      # which keeps overlays but drops attributes added with `//`.
      legacyPackages = lib.mapAttrs (_: pkgs: pkgs.extend (_: _: {omninixMarker = "nixpkgs";})) inputs.nixpkgs.legacyPackages;
    };
  markedHomeManager =
    inputs.home-manager
    // {
      nixosModules.home-manager = {
        imports = [inputs.home-manager.nixosModules.home-manager];
        environment.etc.marker-hm.text = "home-manager";
      };
    };

  # Host modules and user files that report what they were given.
  reportInputs = {inputs, ...}: {environment.etc.has-extra.text = toString (inputs ? extra);};

  hosts = evalHosts {
    hosts = {
      pi = reportInputs;
      laptop = reportInputs;
    };
    hostInputs.pi = {
      nixpkgs = markedNixpkgs;
      home-manager = markedHomeManager;
      extra = {};
    };
  };

  homes = lib.omninix.mkHomeConfigurations {
    inherit inputs;
    users = let
      probe = {
        pkgs,
        inputs,
        ...
      }: {
        home.file.probe.text = "${toString (pkgs ? omninixMarker)} ${toString (inputs ? extra)}";
      };
    in {
      alice = probe;
      bob = probe;
    };
    userInputs.alice = {
      nixpkgs = markedNixpkgs;
      extra = {};
    };
  };
in {
  # Only the overridden host is built from the other inputs...
  testHostBuiltFromItsInputs = {
    expr =
      lib.mapAttrs (_: c: {
        nixpkgs = c.environment.etc ? marker;
        home-manager = c.environment.etc ? marker-hm;
      })
      hosts;
    expected = {
      pi = {
        nixpkgs = true;
        home-manager = true;
      };
      laptop = {
        nixpkgs = false;
        home-manager = false;
      };
    };
  };

  # ...and its modules see them as `inputs`.
  testHostModulesSeeItsInputs = {
    expr = lib.mapAttrs (_: c: c.environment.etc.has-extra.text) hosts;
    expected = {
      pi = "1";
      laptop = "";
    };
  };

  # Standalone homes: pkgs and `inputs` both follow userInputs.
  testHomeBuiltFromItsInputs = {
    expr = lib.mapAttrs (_: h: h.config.home.file.probe.text) homes;
    expected = {
      alice = "1 1";
      bob = " ";
    };
  };

  # Every per-name map is checked, and all the bad names are reported.
  testUnknownNamesIn = {
    expr = lib.omninix.unknownNamesIn {laptop = {};} {
      hostSystems = {lpatop = "aarch64-linux";};
      hostInputs = {
        laptop = {};
        pie = {};
      };
    };
    expected = {
      hostSystems = ["lpatop"];
      hostInputs = ["pie"];
    };
  };

  testUnknownHostInputsThrows = {
    expr =
      (builtins.tryEval (evalHosts {
        hosts.laptop = {};
        hostInputs.pie = {};
      }))
      .success;
    expected = false;
  };

  testUnknownUserInputsThrows = {
    expr =
      (builtins.tryEval (lib.omninix.mkHomeConfigurations {
        inherit inputs;
        users.alice = {};
        userInputs.alcie = {};
      }))
      .success;
    expected = false;
  };
}
