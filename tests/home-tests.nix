# OmniNix Layer 2c — standalone Home Manager tests (lib.runTests format).
#
# No NixOS involved, so unlike config-tests these run on every system,
# darwin included.
{
  inputs,
  omninix,
  system,
}: let
  home = {
    userSystem ? system,
    modules ? [],
    userInputs ? {},
  }:
    (omninix.mkHomeConfigurations {
      inherit inputs userInputs;
      defaultSystem = system;
      userSystems.alice = userSystem;
      users.alice = ./fixtures/flake/users/alice.nix;
      extraModules = modules;
    })
    .alice;

  # A home-manager whose standalone builds carry a marker option.
  markedHomeManager =
    inputs.home-manager
    // {
      lib =
        inputs.home-manager.lib
        // {
          homeManagerConfiguration = args:
            inputs.home-manager.lib.homeManagerConfiguration (args
              // {
                modules = args.modules ++ [({lib, ...}: {options.fixtureMarker = lib.mkOption {default = true;};})];
              });
        };
    };
in {
  # Standalone homes on macOS live under /Users and build a real activation
  # package (evaluated here, built by the macOS CI runner via checks.home).
  testHomeDarwinIdentity = {
    expr = let
      cfg = (home {userSystem = "aarch64-darwin";}).config;
    in {
      inherit (cfg.home) homeDirectory username;
      platform = cfg.home.activationPackage.system;
    };
    expected = {
      homeDirectory = "/Users/alice";
      username = "alice";
      platform = "aarch64-darwin";
    };
  };

  testHomeLinuxIdentity = {
    expr = (home {userSystem = "x86_64-linux";}).config.home.homeDirectory;
    expected = "/home/alice";
  };

  # userInputs builds the home from the user's home-manager and passes the
  # merged inputs to their modules.
  testUserInputsOverride = {
    expr = let
      cfg =
        (home {
          userInputs.alice = {
            home-manager = markedHomeManager;
            extra = {};
          };
          modules = [({inputs, ...}: {home.sessionVariables.EXTRA = builtins.toJSON (inputs ? extra);})];
        })
        .config;
    in {
      marked = cfg.fixtureMarker or false;
      extra = cfg.home.sessionVariables.EXTRA;
    };
    expected = {
      marked = true;
      extra = "true";
    };
  };

  testUserInputsUnknownUserThrows = {
    expr =
      (builtins.tryEval (builtins.attrNames (omninix.mkHomeConfigurations {
        inherit inputs;
        users.alice = ./fixtures/flake/users/alice.nix;
        userInputs.bob = {};
      }))).success;
    expected = false;
  };

  testUserSystemsUnknownUserThrows = {
    expr =
      (builtins.tryEval (builtins.attrNames (omninix.mkHomeConfigurations {
        inherit inputs;
        users.alice = ./fixtures/flake/users/alice.nix;
        userSystems.bob = "aarch64-darwin";
      }))).success;
    expected = false;
  };

  # homeModules.default is the module the builders import, so importing it
  # again (as a hand-rolled config would) dedups instead of redeclaring.
  testHomeModuleDefaultDedups = {
    expr = (builtins.tryEval (home {modules = [inputs.self.homeModules.default];}).config.omninix.persistence.files).success;
    expected = true;
  };
}
