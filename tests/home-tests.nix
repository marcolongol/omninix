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
  }:
    (omninix.mkHomeConfigurations {
      inherit inputs;
      defaultSystem = system;
      userSystems.alice = userSystem;
      users.alice = ./fixtures/flake/users/alice.nix;
      extraModules = modules;
    })
    .alice;
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

  # homeModules.default is the module the builders import, so importing it
  # again (as a hand-rolled config would) dedups instead of redeclaring.
  testHomeModuleDefaultDedups = {
    expr = (builtins.tryEval (home {modules = [inputs.self.homeModules.default];}).config.omninix.persistence.files).success;
    expected = true;
  };
}
