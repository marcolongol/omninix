# mkNixosConfigurations: one nixosSystem per host, built with the caller's
# nixpkgs, named and placed on the right platform.
{
  lib,
  evalHosts,
  ...
}: let
  inherit (lib.omninix) unknownNames;
in {
  # The attribute name is the hostname unless the host says otherwise.
  testHostNameDefaultsToName = {
    expr = (evalHosts {hosts.laptop = {};}).laptop.networking.hostName;
    expected = "laptop";
  };

  testHostCanOverrideHostName = {
    expr = (evalHosts {hosts.laptop = {networking.hostName = "work-laptop";};}).laptop.networking.hostName;
    expected = "work-laptop";
  };

  # Platform: defaultSystem, unless hostSystems names the host.
  testPlatforms = {
    expr = lib.mapAttrs (_: c: c.nixpkgs.hostPlatform.system) (evalHosts {
      hosts = {
        laptop = {};
        pi = {};
      };
      hostSystems.pi = "aarch64-linux";
    });
    expected = {
      laptop = "x86_64-linux";
      pi = "aarch64-linux";
    };
  };

  # A generated hardware-configuration.nix sets the platform with mkDefault;
  # if it disagrees with OmniNix, evaluation fails instead of one winning.
  testPlatformMismatchThrows = {
    expr =
      (builtins.tryEval
        (evalHosts {hosts.pi = {nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";};}).pi.nixpkgs.hostPlatform.system).success;
    expected = false;
  };

  # Host modules receive their own name and the flake inputs as arguments.
  testModuleArguments = {
    expr =
      (evalHosts {
        hosts.laptop = {
          hostName,
          inputs,
          ...
        }: {
          environment.etc.probe.text = "${hostName} ${toString (inputs ? nixpkgs)}";
        };
      }).laptop.environment.etc.probe.text;
    expected = "laptop 1";
  };

  # Typos in per-host maps are reported, not ignored.
  testUnknownNames = {
    expr = unknownNames {laptop = {};} {
      laptop = "x86_64-linux";
      lpatop = "aarch64-linux";
    };
    expected = ["lpatop"];
  };

  testUnknownHostSystemThrows = {
    expr =
      (builtins.tryEval (evalHosts {
        hosts.laptop = {};
        hostSystems.lpatop = "aarch64-linux";
      })).success;
    expected = false;
  };
}
