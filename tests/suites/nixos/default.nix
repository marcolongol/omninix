# mkNixosConfigurations: one nixosSystem per host, built with the caller's
# nixpkgs, named and placed on the right platform.
{
  lib,
  inputs,
}: let
  inherit (lib.omninix) mkNixosConfigurations unknownNames;

  # Build `hosts` and return each host's evaluated config. Each test host is
  # wrapped with a stateVersion, which NixOS warns about when unset.
  configs = args:
    lib.mapAttrs (_: host: host.config) (mkNixosConfigurations ({inherit inputs;}
      // args
      // {
        hosts =
          lib.mapAttrs (_: host: {
            imports = [host];
            system.stateVersion = "26.05";
          })
          args.hosts;
      }));
in {
  # The attribute name is the hostname unless the host says otherwise.
  testHostNameDefaultsToName = {
    expr = (configs {hosts.laptop = {};}).laptop.networking.hostName;
    expected = "laptop";
  };

  testHostCanOverrideHostName = {
    expr = (configs {hosts.laptop = {networking.hostName = "work-laptop";};}).laptop.networking.hostName;
    expected = "work-laptop";
  };

  # Platform: defaultSystem, unless hostSystems names the host.
  testPlatforms = {
    expr = lib.mapAttrs (_: c: c.nixpkgs.hostPlatform.system) (configs {
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
        (configs {hosts.pi = {nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";};}).pi.nixpkgs.hostPlatform.system)
      .success;
    expected = false;
  };

  # Host modules receive their own name and the flake inputs as arguments.
  testModuleArguments = {
    expr =
      (configs {
        hosts.laptop = {
          hostName,
          inputs,
          ...
        }: {
          environment.etc.probe.text = "${hostName} ${toString (inputs ? nixpkgs)}";
        };
      })
      .laptop
      .environment
      .etc
      .probe
      .text;
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
      (builtins.tryEval (configs {
        hosts.laptop = {};
        hostSystems.lpatop = "aarch64-linux";
      }))
      .success;
    expected = false;
  };
}
