# flakeModules.default: a consumer flake points omninix.*Dir at its
# directories and gets its fleet, with the pieces exported.
{
  lib,
  inputs,
  ...
}: let
  fixture = ./fixture;

  settings = {
    hostsDir = fixture + "/hosts";
    usersDir = fixture + "/users";
    rolesDir = fixture + "/roles";
    profilesDir = fixture + "/profiles";
    nixosModulesDir = fixture + "/nixos-modules";
    homeModulesDir = fixture + "/home-modules";
  };

  # A consumer flake: our module, plus `extra` (more modules or settings).
  evalFlake = extra:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [inputs.self.flakeModules.default extra];
      systems = ["x86_64-linux"];
      omninix = settings;
    };

  flake = evalFlake {};
  laptop = flake.nixosConfigurations.laptop.config;
in {
  testOutputs = {
    expr = {
      hosts = lib.attrNames flake.nixosConfigurations;
      homes = lib.attrNames flake.homeConfigurations;
    };
    expected = {
      hosts = ["laptop"];
      homes = ["alice"];
    };
  };

  # The pieces are exported for other flakes, as paths.
  testExports = {
    expr = lib.mapAttrs (_: lib.attrNames) {inherit (flake) roles profiles nixosModules homeModules;};
    expected = {
      roles = ["docker"];
      profiles = ["git"];
      nixosModules = ["motd"];
      homeModules = ["editor"];
    };
  };

  # Roles and always-on NixOS modules reach the host.
  testHostGetsRolesAndModules = {
    expr = {
      docker = laptop.virtualisation.docker.enable;
      motd = laptop.users.motd;
    };
    expected = {
      docker = true;
      motd = "managed by OmniNix";
    };
  };

  # Profiles and always-on home modules reach both kinds of home.
  testHomesGetProfilesAndModules = {
    expr =
      lib.mapAttrs (_: c: {
        git = c.programs.git.enable;
        editor = c.home.sessionVariables.EDITOR;
      }) {
        host = laptop.home-manager.users.alice;
        standalone = flake.homeConfigurations.alice.config;
      };
    expected = {
      host = {
        git = true;
        editor = "vim";
      };
      standalone = {
        git = true;
        editor = "vim";
      };
    };
  };

  testSystemsForwarded = {
    expr = let
      f = evalFlake {
        omninix = {
          hostSystems.laptop = "aarch64-linux";
          userSystems.alice = "aarch64-darwin";
        };
      };
    in {
      host = f.nixosConfigurations.laptop.config.nixpkgs.hostPlatform.system;
      home = f.homeConfigurations.alice.config.home.homeDirectory;
    };
    expected = {
      host = "aarch64-linux";
      home = "/Users/alice";
    };
  };

  # hostInputs / userInputs reach the builders: a misspelt name is caught
  # there.
  testInputsForwarded = {
    expr = {
      host = (builtins.tryEval (evalFlake {omninix.hostInputs.lpatop = {};}).nixosConfigurations).success;
      home = (builtins.tryEval (evalFlake {omninix.userInputs.alcie = {};}).homeConfigurations).success;
    };
    expected = {
      host = false;
      home = false;
    };
  };

  # A flake that sets no directories gets no fleet, and no stray outputs.
  testNothingConfigured = {
    expr = let
      f = inputs.flake-parts.lib.mkFlake {inherit inputs;} {
        imports = [inputs.self.flakeModules.default];
        systems = ["x86_64-linux"];
      };
    in {
      hosts = f.nixosConfigurations;
      hasHomes = f ? homeConfigurations;
    };
    expected = {
      hosts = {};
      hasHomes = false;
    };
  };

  # A flake's own nixosModules entry replaces the discovered one of the same
  # name instead of merging into it. The export is checked by evaluating it
  # against a stand-in option.
  testOwnNixosModuleWins = {
    expr =
      (lib.evalModules {
        modules = [
          {options.users.motd = lib.mkOption {type = lib.types.str;};}
          (evalFlake {flake.nixosModules.motd = {users.motd = "mine";};}).nixosModules.motd
        ];
      })
      .config
      .users
      .motd;
    expected = "mine";
  };
}
