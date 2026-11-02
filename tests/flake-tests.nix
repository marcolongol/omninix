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
in {
  testMkFlakeOutputNames = {
    expr = builtins.attrNames viaMkFlake;
    expected = ["homeConfigurations" "hosts" "nixosConfigurations" "packages" "profiles" "roles" "users"];
  };

  testMkFlakeNoPackagesWithoutDir = {
    expr = omninix.mkFlake inputs {hostsDir = settings.hostsDir; defaultSystem = system;} ? packages;
    expected = false;
  };

  testMkFlakeSystemsDefaultToDefaultSystem = {
    expr = builtins.attrNames viaMkFlake.packages;
    expected = [system];
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
    expected = ["extra" "hello-fixture"];
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

  testFlakeModuleRequiresHostsDir = {
    expr = bare.options.omninix.hostsDir.isDefined;
    expected = false;
  };

  testFlakeModuleTypeChecksOptions = {
    expr = bare.options.omninix.allowUnfree.type.check "yes";
    expected = false;
  };

  testFlakeModuleExtraRolesKeepPaths = {
    expr = (evalFlake {omninix.extraRoles.a = ./fixtures/discovery/role-a.nix;}).roles.a;
    expected = ./fixtures/discovery/role-a.nix;
  };

  testFlakeModuleExtraRolesOneDefinitionPerName = {
    expr =
      (builtins.tryEval (evalFlake {
        imports = [{omninix.extraRoles.a = ./fixtures/discovery/role-a.nix;}];
        omninix.extraRoles.a = ./fixtures/discovery/sub;
      })
      .roles
      .a)
      .success;
    expected = false;
  };
}
