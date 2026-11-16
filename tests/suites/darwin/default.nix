# Macs: a host whose system is darwin is built with nix-darwin, from the same
# directories as NixOS hosts. Evaluated only, so it runs on Linux too.
{
  lib,
  inputs,
  ...
}: let
  fixture = ./fixture;

  evalFlake = extra:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [inputs.self.flakeModules.default extra];
      systems = ["x86_64-linux"];
      omninix = {
        hostsDir = fixture + "/hosts";
        usersDir = fixture + "/users";
        rolesDir = fixture + "/roles";
        profilesDir = fixture + "/profiles";
        darwinModulesDir = fixture + "/darwin-modules";
        secretsPath = fixture + "/secrets";
        hostSystems.mac = "aarch64-darwin";
      };
    };

  flake = evalFlake {};
  mac = flake.darwinConfigurations.mac.config;
  laptop = flake.nixosConfigurations.laptop.config;

  rolesOn = config: lib.attrNames config.roles;
in {
  # The darwin system decides: mac is a nix-darwin host, laptop a NixOS one.
  testHostsSplitBySystem = {
    expr = {
      nixos = lib.attrNames flake.nixosConfigurations;
      darwin = lib.attrNames flake.darwinConfigurations;
    };
    expected = {
      nixos = ["laptop"];
      darwin = ["mac"];
    };
  };

  # Each host gets its platform's halves of the roles.
  testRoleHalves = {
    expr = {
      laptop = rolesOn laptop;
      mac = rolesOn mac;
    };
    expected = {
      laptop = ["both" "linux-only"];
      mac = ["both" "mac-only"];
    };
  };

  testSplitRoles = {
    expr = lib.mapAttrs (_: lib.attrNames) (lib.omninix.splitRoles flake.roles);
    expected = {
      nixos = ["both" "linux-only"];
      darwin = ["both" "mac-only"];
    };
  };

  # Always-on darwin modules reach Macs, and are exported.
  testDarwinModules = {
    expr = {
      applied = mac.system.defaults.dock.autohide;
      exported = lib.attrNames flake.darwinModules;
    };
    expected = {
      applied = true;
      exported = ["dock"];
    };
  };

  # Users on a Mac: an existing account in /Users, the primary user, and a
  # home with the profiles.
  testMacUsers = {
    expr = {
      home = mac.users.users.alice.home;
      primaryUser = mac.system.primaryUser;
      homeDirectory = mac.home-manager.users.alice.home.homeDirectory;
      git = mac.home-manager.users.alice.programs.git.enable;
    };
    expected = {
      home = "/Users/alice";
      primaryUser = "alice";
      homeDirectory = "/Users/alice";
      git = true;
    };
  };

  # macOS manages groups itself: there's no extraGroups on Macs.
  testNoExtraGroupsOnMacs = {
    expr =
      (builtins.tryEval
        (lib.omninix.mkDarwinConfigurations {
          inherit inputs;
          hostSystems.mac = "aarch64-darwin";
          hosts.mac = {
            system.stateVersion = 6;
            omninix.hostUsers.alice = {
              enable = true;
              extraGroups = ["admin"];
            };
          };
        })
        .mac
        .config
        .omninix
        .activeUsers)
      .success;
    expected = false;
  };

  testMacNamedAndOnItsPlatform = {
    expr = {
      inherit (mac.networking) hostName;
      system = mac.nixpkgs.hostPlatform.system;
    };
    expected = {
      hostName = "mac";
      system = "aarch64-darwin";
    };
  };

  # Built from the flake's nixpkgs, not nix-darwin's own pin.
  testMacUsesFlakeNixpkgs = {
    expr = "${mac.nixpkgs.source}" == "${inputs.nixpkgs}";
    expected = true;
  };

  testMacDefaultSopsFile = {
    expr = mac.sops.defaultSopsFile;
    expected = fixture + "/secrets/mac.yaml";
  };

  testNoNixDarwinThrows = {
    expr =
      (builtins.tryEval
        (lib.omninix.mkDarwinConfigurations {
          inputs = removeAttrs inputs ["nix-darwin"];
          hostSystems.mac = "aarch64-darwin";
          hosts.mac = {};
        })
      .mac)
      .success;
    expected = false;
  };

  # A misspelt host is caught across both platforms.
  testUnknownHostAcrossPlatforms = {
    expr = (builtins.tryEval (evalFlake {omninix.hostSystems.mca = "aarch64-darwin";}).darwinConfigurations).success;
    expected = false;
  };
}
