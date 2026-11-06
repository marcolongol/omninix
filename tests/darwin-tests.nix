# OmniNix Layer 2d — darwin host tests (lib.runTests format).
#
# A fixture fleet with a NixOS host (`linux`) and a Mac (`mac`), through
# flakeModules.default. Darwin systems evaluate on any platform, so these run
# everywhere; checks.<darwin>.darwin builds one for real.
{
  inputs,
  lib,
  system,
}: let
  fixture = ./fixtures/darwin;
  sharing = ./fixtures/sharing;
  settings = {
    hostsDir = fixture + "/hosts";
    usersDir = ./fixtures/flake/users;
    rolesDir = ./fixtures/platforms/roles;
    hostSystems.mac = "aarch64-darwin";
    defaultSystem = "x86_64-linux";
  };

  fleet = {
    extra ? {},
    module ? {},
    flakeInputs ? inputs,
  }:
    inputs.flake-parts.lib.mkFlake {inputs = flakeInputs;} {
      imports = [inputs.self.flakeModules.default module];
      systems = [system];
      omninix = settings // extra;
    };

  plain = fleet {};
  mac = plain.darwinConfigurations.mac;
  macWith = modules: (mac.extendModules {inherit modules;}).config;
  failedAssertions = cfg: map (a: a.message) (builtins.filter (a: !a.assertion) cfg.assertions);
  fixtureOptions = c: builtins.attrNames (c.options.fixture or {});
  throws = v: !(builtins.tryEval v).success;

  # A nix-darwin whose systems carry a marker option.
  markedDarwin =
    inputs.nix-darwin
    // {
      lib =
        inputs.nix-darwin.lib
        // {
          darwinSystem = args:
            inputs.nix-darwin.lib.darwinSystem (args
              // {
                modules = args.modules ++ [({lib, ...}: {options.fixture.markedDarwin = lib.mkOption {default = true;};})];
              });
        };
    };
in {
  # -darwin hosts go to darwinConfigurations, the rest stay NixOS.
  testDarwinHostsSplit = {
    expr = {
      nixos = builtins.attrNames plain.nixosConfigurations;
      darwin = builtins.attrNames plain.darwinConfigurations;
    };
    expected = {
      nixos = ["linux"];
      darwin = ["mac"];
    };
  };

  # Each host gets its platform's role halves; roles.both works on both.
  testDarwinRoleHalves = {
    expr = {
      mac = fixtureOptions mac;
      linux = fixtureOptions plain.nixosConfigurations.linux;
    };
    expected = {
      mac = ["bothDarwin" "darwinOnly" "privDarwin"];
      linux = ["bothNixos" "file" "nixosDir"];
    };
  };

  # The user lives under /Users, in nix-darwin and in Home Manager, and is
  # the primary user; packages are the darwin platform's.
  testDarwinUser = {
    expr = {
      home = mac.config.users.users.alice.home;
      hmHome = mac.config.home-manager.users.alice.home.homeDirectory;
      primary = mac.config.system.primaryUser;
      platform = mac.pkgs.stdenv.hostPlatform.system;
      warnings = mac.config.warnings ++ mac.config.home-manager.users.alice.warnings;
    };
    expected = {
      home = "/Users/alice";
      hmHome = "/Users/alice";
      primary = "alice";
      platform = "aarch64-darwin";
      warnings = [];
    };
  };

  testDarwinToplevelEvaluates = {
    expr = lib.hasSuffix ".drv" mac.config.system.build.toplevel.drvPath;
    expected = true;
  };

  # Users on a Mac get the same profiles and HM modules as anywhere else.
  testDarwinUserGetsProfiles = {
    expr =
      builtins.attrNames
      (fleet {
        extra = {
          profilesDir = sharing + "/profiles";
          homeManagerModulesDir = sharing + "/home";
        };
      })
      .darwinConfigurations
      .mac
      .config
      .home-manager
      .users
      .alice
      .fixture;
    expected = ["homePrivate" "homePublic" "profilePrivate" "profilePublic"];
  };

  # macOS manages groups itself: extraGroups is an error, not ignored.
  testDarwinExtraGroupsFails = {
    expr = builtins.any (lib.hasInfix "extraGroups is NixOS only") (failedAssertions (macWith [{omninix.hostUsers.alice.extraGroups = ["admin"];}]));
    expected = true;
  };

  # With several users there's no obvious primary one: the host decides.
  testDarwinPrimaryUserOnlyForOneUser = {
    expr = (macWith [{omninix.hostUsers.bob.enable = true;}]).system.primaryUser;
    expected = null;
  };

  # darwinModulesDir (own and internal/) and extraDarwinModules reach Mac
  # hosts only; darwinModules exports own entries only.
  testDarwinModules = let
    out = fleet {
      extra = {
        darwinModulesDir = fixture + "/modules";
        extraDarwinModules.extra = fixture + "/extra-darwin.nix";
      };
    };
  in {
    expr = {
      mac = builtins.filter (lib.hasPrefix "darwinModule") (fixtureOptions out.darwinConfigurations.mac);
      linux = builtins.filter (lib.hasPrefix "darwinModule") (fixtureOptions out.nixosConfigurations.linux);
      exported = builtins.attrNames out.darwinModules;
    };
    expected = {
      mac = ["darwinModule" "darwinModuleExtra" "darwinModulePrivate"];
      linux = [];
      exported = ["dmod"];
    };
  };

  # hostInputs swaps nix-darwin (and anything else) for one Mac.
  testDarwinHostInputs = let
    out = fleet {
      extra.hostInputs.mac = {
        nix-darwin = markedDarwin;
        extra = {};
      };
    };
  in {
    expr = {
      marked = builtins.elem "markedDarwin" (fixtureOptions out.darwinConfigurations.mac);
      extra = out.darwinConfigurations.mac._module.specialArgs.inputs ? extra;
    };
    expected = {
      marked = true;
      extra = true;
    };
  };

  # A Mac host without a nix-darwin input fails with a message; NixOS hosts
  # and the outputs list are unaffected.
  testDarwinNeedsNixDarwinInput = let
    out = fleet {flakeInputs = builtins.removeAttrs inputs ["nix-darwin"];};
  in {
    expr = {
      macThrows = throws out.darwinConfigurations.mac.config.system.build.toplevel.drvPath;
      linux = lib.hasSuffix ".drv" out.nixosConfigurations.linux.config.system.build.toplevel.drvPath;
      names = builtins.attrNames out.darwinConfigurations;
    };
    expected = {
      macThrows = true;
      linux = true;
      names = ["mac"];
    };
  };

  # Without darwin hosts or nix-darwin, the flake has an empty darwinConfigurations.
  testNoDarwinHosts = {
    expr =
      (fleet {
        flakeInputs = builtins.removeAttrs inputs ["nix-darwin"];
        extra.hostSystems = {};
      })
      .darwinConfigurations;
    expected = {};
  };

  # nix-darwin's flake module types darwinConfigurations, so hand-written
  # darwin hosts merge with OmniNix's.
  testDarwinConfigurationsMerge = {
    expr = builtins.attrNames (fleet {module.flake.darwinConfigurations.hand = {};}).darwinConfigurations;
    expected = ["hand" "mac"];
  };

  # Typos in hostSystems are caught against all hosts, darwin ones included.
  testDarwinHostSystemsTypoThrows = {
    expr = throws (builtins.attrNames
      (fleet {
        extra.hostSystems = {
          mac = "aarch64-darwin";
          macc = "aarch64-darwin";
        };
      }).nixosConfigurations);
    expected = true;
  };

  # darwinModules.default is the file the builders import: importing it again dedups.
  testDarwinModuleDefaultDedups = {
    expr = (macWith [inputs.self.darwinModules.default]).omninix.activeUsers;
    expected = ["alice"];
  };

  # The #darwin-host template is a working Mac host, here with the default
  # template's user (and so its `common` profile) enabled.
  testDarwinHostTemplate = {
    expr = let
      template = ../templates/default;
      c =
        ((inputs.self.lib.omninix.mkDarwinConfigurations {
            inherit inputs;
            hosts.mac = ../templates/darwin-host;
            hostSystems.mac = "aarch64-darwin";
            users.example-user = template + "/users/example-user";
            profiles.common = template + "/profiles/common.nix";
          })
          .mac
          .extendModules {modules = [{omninix.hostUsers.example-user.enable = true;}];})
        .config;
    in {
      drv = lib.hasSuffix ".drv" c.system.build.toplevel.drvPath;
      primary = c.system.primaryUser;
      common = c.home-manager.users.example-user.profiles.common.enable;
    };
    expected = {
      drv = true;
      primary = "example-user";
      common = true;
    };
  };

  # darwinModules.default works in a hand-rolled darwinSystem.
  testDarwinCoreStandalone = {
    expr = let
      c =
        (inputs.nix-darwin.lib.darwinSystem {
          modules = [
            inputs.self.darwinModules.default
            {
              nixpkgs.hostPlatform = "aarch64-darwin";
              system.stateVersion = 6;
              omninix.hostUsers.alice.enable = true;
            }
          ];
        })
        .config;
    in {
      home = c.users.users.alice.home;
      primary = c.system.primaryUser;
    };
    expected = {
      home = "/Users/alice";
      primary = "alice";
    };
  };
}
