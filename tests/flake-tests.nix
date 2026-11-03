# OmniNix Layer 2b — flake entry point tests (lib.runTests format).
#
# mkFlake output shape, and flakeModules.default checked against mkFlake on
# the same fixture.
{
  inputs,
  omninix,
  lib,
  system,
}: let
  fixture = ./fixtures/flake;
  settings = {
    hostsDir = fixture + "/hosts";
    usersDir = fixture + "/users";
    packagesDir = fixture + "/packages";
  };

  # Consumer-only input: proves the module builds with the consumer's inputs.
  consumerInputs = inputs // {marker = {};};

  evalFlake = module:
    inputs.flake-parts.lib.mkFlake {inputs = consumerInputs;} {
      imports = [inputs.self.flakeModules.default module];
      systems = [system];
      omninix = settings // {defaultSystem = system;};
    };

  plain = evalFlake {};
  bare = inputs.flake-parts.lib.evalFlakeModule {inputs = consumerInputs;} {
    imports = [inputs.self.flakeModules.default];
    systems = [system];
  };
  viaMkFlake = omninix.mkFlake consumerInputs (settings // {defaultSystem = system;});

  probe = module:
    (evalFlake {
      imports = [module];
      perSystem = {pkgs, ...}: {
        legacyPackages.probe = {
          inherit (pkgs.config) allowUnfree;
          hasPackage = pkgs ? hello-fixture;
        };
      };
    })
    .legacyPackages
    .${
      system
    }
    .probe;

  toplevel = c: c.nixosConfigurations.test.config.system.build.toplevel.drvPath;

  # A consumer's own nixpkgs with the exported overlay (twice: shadowing).
  withOverlays = overlays: import inputs.nixpkgs {inherit system overlays;};
  consumerPkgs = withOverlays [viaMkFlake.overlays.packages];

  # Sharing fixture: each piece declares options.fixture.<name>, so a probe of
  # which options exist shows what was imported.
  sharing = ./fixtures/sharing;
  sharingSettings =
    settings
    // {
      rolesDir = sharing + "/roles";
      profilesDir = sharing + "/profiles";
      nixosModulesDir = sharing + "/nixos";
      homeManagerModulesDir = sharing + "/home";
      extraRoles.extra = sharing + "/extra-role.nix";
      extraNixosModules.extra = sharing + "/extra-nixos.nix";
      extraHomeManagerModules.extra = sharing + "/extra-home.nix";
      defaultSystem = system;
    };
  sharingMkFlake = omninix.mkFlake consumerInputs sharingSettings;
  evalSharing = module:
    inputs.flake-parts.lib.mkFlake {inputs = consumerInputs;} {
      imports = [inputs.self.flakeModules.default module];
      systems = [system];
      omninix = sharingSettings;
    };
  sharingPlain = evalSharing {};
  fixtureOptions = c: builtins.attrNames c.options.fixture;
  # Leaf paths of a flake-parts module export, one per definition
  # (wrapper -> deferredModule -> one entry per definition -> path).
  definitionPaths = m: map (d: builtins.head d.imports) (builtins.head m.imports).imports;
  exportNames = out: {
    roles = builtins.attrNames out.roles;
    profiles = builtins.attrNames out.profiles;
    nixosModules = builtins.attrNames out.nixosModules;
    homeModules = builtins.attrNames out.homeModules;
  };
in {
  testMkFlakeOutputNames = {
    expr = builtins.attrNames viaMkFlake;
    expected = ["homeConfigurations" "homeModules" "hosts" "nixosConfigurations" "nixosModules" "overlays" "packages" "profiles" "roles" "users"];
  };

  testMkFlakeNoPackagesWithoutDir = {
    expr = omninix.mkFlake inputs {hostsDir = settings.hostsDir; defaultSystem = system;} ? packages;
    expected = false;
  };

  testMkFlakeNoOverlaysWithoutDir = {
    expr = omninix.mkFlake inputs {hostsDir = settings.hostsDir; defaultSystem = system;} ? overlays;
    expected = false;
  };

  # overlays.packages gives a consumer's own pkgs the same packages.
  testOverlayPackagesMatchPackages = {
    expr = consumerPkgs.hello-fixture.drvPath;
    expected = viaMkFlake.packages.${system}.hello-fixture.drvPath;
  };

  # A package taking `inputs` can't be shared; it throws on use only.
  testOverlayPackagesRejectInputsLazily = {
    expr = {
      inputs = (builtins.tryEval consumerPkgs.inputs-fixture.drvPath).success;
      others = consumerPkgs ? hello-fixture;
    };
    expected = {
      inputs = false;
      others = true;
    };
  };

  testOverlayPackagesRejectShadowing = {
    expr = (builtins.tryEval (withOverlays [viaMkFlake.overlays.packages viaMkFlake.overlays.packages]).hello-fixture.drvPath).success;
    expected = false;
  };

  testFlakeModuleOverlayPackagesMatchMkFlake = {
    expr = (withOverlays [plain.overlays.packages]).hello-fixture.drvPath;
    expected = consumerPkgs.hello-fixture.drvPath;
  };

  testFlakeModuleConsumerOverlayWins = {
    expr = (evalFlake {flake.overlays.packages = final: prev: {marker = true;};}).overlays.packages {} {};
    expected = {marker = true;};
  };

  testMkFlakeSystemsDefaultToDefaultSystem = {
    expr = builtins.attrNames viaMkFlake.packages;
    expected = [system];
  };

  # Packages asking for `inputs` get the consumer's (consumerInputs has marker).
  testMkFlakePackageGetsInputs = {
    expr = builtins.readFile viaMkFlake.packages.${system}.inputs-fixture;
    expected = "true";
  };

  # meta.platforms filters packages.<system>, but pkgs.<name> remains.
  testMkFlakePackagesFilteredByPlatform = {
    expr = {
      output = viaMkFlake.packages.${system} ? other-platform-fixture;
      pkgs = viaMkFlake.nixosConfigurations.test.pkgs ? other-platform-fixture;
    };
    expected = {
      output = false;
      pkgs = true;
    };
  };

  testMkFlakePackagesMatchHostPkgs = {
    expr = viaMkFlake.packages.${system}.hello-fixture.drvPath;
    expected = viaMkFlake.nixosConfigurations.test.pkgs.hello-fixture.drvPath;
  };

  testFlakeModuleDedupsDoubleImport = {
    expr = builtins.attrNames (evalFlake {imports = [inputs.self.flakeModules.default];}).nixosConfigurations;
    expected = ["test"];
  };

  testFlakeModuleHostMatchesMkFlake = {
    expr = toplevel plain == toplevel viaMkFlake;
    expected = true;
  };

  # Guards path coercion: discovered paths must match mkFlake's exactly.
  testFlakeModuleDiscoveredPathsMatchMkFlake = {
    expr = {inherit (plain) hosts users roles profiles;};
    expected = {inherit (viaMkFlake) hosts users roles profiles;};
  };

  # Standalone homeConfigurations get the same HM sops default.
  testMkFlakeHomeSopsDefaultFile = {
    expr =
      toString (omninix.mkFlake consumerInputs (settings
        // {
          secretsPath = ./fixtures/secrets;
          defaultSystem = system;
        }))
      .homeConfigurations
      .alice
      .config
      .sops
      .defaultSopsFile;
    expected = toString (./fixtures/secrets + "/users/alice.yaml");
  };

  testFlakeModuleUsesConsumerInputs = {
    expr = plain.nixosConfigurations.test._module.specialArgs.inputs ? marker;
    expected = true;
  };

  testFlakeModuleHomeMatchesMkFlake = {
    expr = plain.homeConfigurations.alice.activationPackage.drvPath;
    expected = viaMkFlake.homeConfigurations.alice.activationPackage.drvPath;
  };

  testFlakeModuleHomeConfigurationsMerge = {
    expr = builtins.attrNames (evalFlake {flake.homeConfigurations.extra = {};}).homeConfigurations;
    expected = ["alice" "extra"];
  };

  testFlakeModuleHomeFlakeModuleReimport = {
    expr = builtins.attrNames (evalFlake {imports = [inputs.home-manager.flakeModules.home-manager];}).homeConfigurations;
    expected = ["alice"];
  };

  testFlakeModuleKeepsMkFlakeOutputs = {
    expr = builtins.all (n: plain ? ${n}) (builtins.attrNames viaMkFlake);
    expected = true;
  };

  testFlakeModulePackagesMatchHostPkgs = {
    expr = plain.packages.${system}.hello-fixture.drvPath;
    expected = plain.nixosConfigurations.test.pkgs.hello-fixture.drvPath;
  };

  testFlakeModulePackagesMergeWithPerSystem = {
    expr =
      builtins.attrNames
      (evalFlake {
        perSystem = {pkgs, ...}: {packages.extra = pkgs.hello;};
      })
    .packages
    .${
        system
      };
    expected = ["extra" "hello-fixture" "inputs-fixture"];
  };

  testFlakeModuleLocalPackageWins = {
    expr =
      (evalFlake {
        perSystem = {pkgs, ...}: {packages.hello-fixture = pkgs.hello;};
      })
      .packages
      .${
        system
      }
      .hello-fixture
      .pname;
    expected = "hello";
  };

  testFlakeModulePerSystemPkgsOverlaid = {
    expr = probe {omninix.allowUnfree = true;};
    expected = {
      allowUnfree = true;
      hasPackage = true;
    };
  };

  testFlakeModulePerSystemPkgsOverridable = {
    expr = probe {
      perSystem = {
        _module.args.pkgs = import inputs.nixpkgs {inherit system;};
      };
    };
    expected = {
      allowUnfree = false;
      hasPackage = false;
    };
  };

  # No hostsDir: a users-only (or roles/profiles-only) flake still evaluates.
  testFlakeModuleHostsDirOptional = {
    expr = let
      out = inputs.flake-parts.lib.mkFlake {inputs = consumerInputs;} {
        imports = [inputs.self.flakeModules.default];
        systems = [system];
        omninix = {
          inherit (settings) usersDir;
          defaultSystem = system;
        };
      };
    in {
      hosts = out.nixosConfigurations;
      users = builtins.attrNames out.homeConfigurations;
    };
    expected = {
      hosts = {};
      users = builtins.attrNames plain.homeConfigurations;
    };
  };

  testFlakeModuleTypeChecksOptions = {
    expr = bare.options.omninix.allowUnfree.type.check "yes";
    expected = false;
  };

  # extraRoles are imported, not exported, so check the option value itself.
  testFlakeModuleExtraRolesKeepPaths = {
    expr =
      (inputs.flake-parts.lib.evalFlakeModule {inputs = consumerInputs;} {
        imports = [inputs.self.flakeModules.default];
        systems = [system];
        omninix.extraRoles.a = ./fixtures/discovery/role-a.nix;
      })
      .config
      .omninix
      .extraRoles
      .a;
    expected = ./fixtures/discovery/role-a.nix;
  };

  testFlakeModuleExtraRolesOneDefinitionPerName = {
    expr =
      (builtins.tryEval
        (inputs.flake-parts.lib.evalFlakeModule {inputs = consumerInputs;} {
          imports = [inputs.self.flakeModules.default {omninix.extraRoles.a = ./fixtures/discovery/role-a.nix;}];
          systems = [system];
          omninix.extraRoles.a = ./fixtures/discovery/sub;
        })
      .config
      .omninix
      .extraRoles
      .a)
      .success;
    expected = false;
  };

  # Hosts import every role and NixOS module: own, internal/ and extra*.
  testSharingHostImportsAll = {
    expr = fixtureOptions sharingMkFlake.nixosConfigurations.test;
    expected = ["nixosExtra" "nixosPrivate" "nixosPublic" "roleExtra" "rolePrivate" "rolePublic"];
  };

  # Users get every profile and HM module: own, internal/ and extra*.
  testSharingHomeImportsAll = {
    expr = fixtureOptions sharingMkFlake.homeConfigurations.alice;
    expected = ["homeExtra" "homePrivate" "homePublic" "profilePrivate" "profilePublic"];
  };

  # Exports are this flake's own pieces only: no internal/, no extra*.
  testSharingMkFlakeExportsOwnOnly = {
    expr = exportNames sharingMkFlake;
    expected = {
      roles = ["public"];
      profiles = ["pub"];
      nixosModules = ["mod"];
      homeModules = ["hmod"];
    };
  };

  testSharingFlakeModuleExportsOwnOnly = {
    expr = exportNames sharingPlain;
    expected = exportNames sharingMkFlake;
  };

  # flake-parts wraps module exports (_class, imports = [path]).
  testSharingFlakeModuleWrapsModules = {
    expr = {
      nixos = {
        inherit (sharingPlain.nixosModules.mod) _class;
        paths = definitionPaths sharingPlain.nixosModules.mod;
      };
      home = {
        inherit (sharingPlain.homeModules.hmod) _class;
        paths = definitionPaths sharingPlain.homeModules.hmod;
      };
    };
    expected = {
      nixos = {
        _class = "nixos";
        paths = [sharingMkFlake.nixosModules.mod];
      };
      home = {
        _class = "homeManager";
        paths = [sharingMkFlake.homeModules.hmod];
      };
    };
  };

  # A consumer's own same-named export replaces ours instead of merging.
  testSharingConsumerExportWins = {
    expr = let
      out = evalSharing {
        flake.nixosModules.mod = sharing + "/extra-nixos.nix";
        flake.homeModules.hmod = sharing + "/extra-home.nix";
      };
    in {
      nixos = definitionPaths out.nixosModules.mod;
      home = definitionPaths out.homeModules.hmod;
    };
    expected = {
      nixos = [(sharing + "/extra-nixos.nix")];
      home = [(sharing + "/extra-home.nix")];
    };
  };

  # Without home-manager's flakeModule, flake.homeModules is a plain value.
  testSharingHomeModulesWithoutHmFlakeModule = {
    expr =
      builtins.attrNames
      (inputs.flake-parts.lib.mkFlake {inputs = builtins.removeAttrs consumerInputs ["home-manager"];} {
        imports = [inputs.self.flakeModules.default];
        systems = [system];
        omninix = {
          homeManagerModulesDir = sharing + "/home";
          defaultSystem = system;
        };
      })
      .homeModules;
    expected = ["hmod"];
  };

  # The same name in a dir and its internal/ throws instead of one winning.
  testSharingInternalClashThrows = {
    expr =
      (builtins.tryEval (builtins.attrNames
        (omninix.mkFlake consumerInputs {
          inherit (settings) hostsDir;
          rolesDir = ./fixtures/sharing-clash/roles;
          defaultSystem = system;
        })
        .roles))
      .success;
    expected = false;
  };
}
