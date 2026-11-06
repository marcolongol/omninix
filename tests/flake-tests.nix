# OmniNix Layer 2b — flake entry point tests (lib.runTests format).
#
# flakeModules.default on the fixture flakes: outputs, packages and overlays,
# typed options, sharing.
{
  inputs,
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
  # The fixture flake with extra omninix settings on top.
  flakeWith = extra:
    inputs.flake-parts.lib.mkFlake {inputs = consumerInputs;} {
      imports = [inputs.self.flakeModules.default];
      systems = [system];
      omninix = settings // {defaultSystem = system;} // extra;
    };
  bare = inputs.flake-parts.lib.evalFlakeModule {inputs = consumerInputs;} {
    imports = [inputs.self.flakeModules.default];
    systems = [system];
  };

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

  # A host from the flake fixture with extra roles/profiles and modules.
  withExtras = extra: modules:
    ((flakeWith extra)
      .nixosConfigurations
      .test
      .extendModules {inherit modules;})
    .config;
  failedAssertions = cfg: map (a: a.message) (builtins.filter (a: !a.assertion) cfg.assertions);

  # A consumer's own nixpkgs with the exported overlay (twice: shadowing).
  withOverlays = overlays: import inputs.nixpkgs {inherit system overlays;};
  consumerPkgs = withOverlays [plain.overlays.packages];

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
  testFlakeModuleOutputNames = {
    expr = builtins.all (n: plain ? ${n}) ["homeConfigurations" "homeModules" "hosts" "nixosConfigurations" "nixosModules" "overlays" "packages" "profiles" "roles" "users"];
    expected = true;
  };

  # Without packagesDir: no packages and no overlays.packages.
  testFlakeModuleNoPackagesWithoutDir = let
    out = flakeWith {packagesDir = null;};
  in {
    expr = {
      packages = out.packages.${system};
      overlay = (out.overlays or {}) ? packages;
    };
    expected = {
      packages = {};
      overlay = false;
    };
  };

  # overlays.packages gives a consumer's own pkgs the same packages.
  testOverlayPackagesMatchPackages = {
    expr = consumerPkgs.hello-fixture.drvPath;
    expected = plain.packages.${system}.hello-fixture.drvPath;
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
    expr = (builtins.tryEval (withOverlays [plain.overlays.packages plain.overlays.packages]).hello-fixture.drvPath).success;
    expected = false;
  };

  testFlakeModuleConsumerOverlayWins = {
    expr = (evalFlake {flake.overlays.packages = final: prev: {marker = true;};}).overlays.packages {} {};
    expected = {marker = true;};
  };

  # Packages asking for `inputs` get the consumer's (consumerInputs has marker).
  testFlakeModulePackageGetsInputs = {
    expr = builtins.readFile plain.packages.${system}.inputs-fixture;
    expected = "true";
  };

  # meta.platforms filters packages.<system>, but pkgs.<name> remains.
  testFlakeModulePackagesFilteredByPlatform = {
    expr = {
      output = plain.packages.${system} ? other-platform-fixture;
      pkgs = plain.nixosConfigurations.test.pkgs ? other-platform-fixture;
    };
    expected = {
      output = false;
      pkgs = true;
    };
  };

  testFlakeModuleDedupsDoubleImport = {
    expr = builtins.attrNames (evalFlake {imports = [inputs.self.flakeModules.default];}).nixosConfigurations;
    expected = ["test"];
  };

  # Guards path coercion: discovered entries stay paths, not strings.
  testFlakeModuleDiscoveredPathsStayPaths = {
    expr = {inherit (plain) hosts users;};
    expected = {
      hosts.test = fixture + "/hosts/test.nix";
      users.alice = fixture + "/users/alice.nix";
    };
  };

  # Standalone homeConfigurations get the same HM sops default.
  testFlakeModuleHomeSopsDefaultFile = {
    expr = toString (flakeWith {secretsPath = ./fixtures/secrets;})
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

  testFlakeModuleHomeConfigurationsMerge = {
    expr = builtins.attrNames (evalFlake {flake.homeConfigurations.extra = {};}).homeConfigurations;
    expected = ["alice" "extra"];
  };

  testFlakeModuleHomeFlakeModuleReimport = {
    expr = builtins.attrNames (evalFlake {imports = [inputs.home-manager.flakeModules.home-manager];}).homeConfigurations;
    expected = ["alice"];
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

  # hostInputs/userInputs reach the builders.
  testHostAndUserInputsPassThrough = let
    overrides = {
      hostInputs.test.marker = "host";
      userInputs.alice.marker = "user";
    };
    seen = c: {
      host = c.nixosConfigurations.test._module.specialArgs.inputs.marker;
      user = c.homeConfigurations.alice._module.specialArgs.inputs.marker;
    };
  in {
    expr = seen (flakeWith overrides);
    expected = {
      host = "host";
      user = "user";
    };
  };

  # omninix.requirements: a missing module becomes one readable assertion.
  testRequirementMissing = {
    expr = failedAssertions (withExtras {extraRoles.requiring = sharing + "/requiring-role.nix";} [{roles.requiring.enable = true;}]);
    expected = ["roles.requiring needs the fixture dependency; import it (the option `fixtureDep.value` doesn't exist)."];
  };

  testRequirementSatisfied = {
    expr = let
      cfg = withExtras {extraRoles.requiring = sharing + "/requiring-role.nix";} [(sharing + "/dep.nix") {roles.requiring.enable = true;}];
    in {
      failed = failedAssertions cfg;
      inherit (cfg.fixtureDep) value;
    };
    expected = {
      failed = [];
      value = "set";
    };
  };

  # Same in Home Manager. Standalone home configs raise failed assertions
  # eagerly (with the message), so check that it fails, against a control.
  testRequirementHome = let
    home = extra: (flakeWith extra).homeConfigurations.alice;
  in {
    expr = {
      missing = (builtins.tryEval (builtins.attrNames (home {extraProfiles.requiring = sharing + "/requiring-profile.nix";}))).success;
      control = (builtins.tryEval (builtins.attrNames (home {}))).success;
    };
    expected = {
      missing = false;
      control = true;
    };
  };

  # A borrowed role reading `inputs` gets a throwing value, not this flake's.
  testBorrowedRoleInputsThrows = {
    expr = let
      cfg = withExtras {extraRoles.borrowed = sharing + "/borrowed-inputs-role.nix";};
    in {
      declared = (cfg []) ? roles;
      disabledFine = (builtins.tryEval (cfg []).environment.etc).success;
      enabledThrows = (builtins.tryEval (cfg [{roles.borrowed.enable = true;}]).environment.etc.borrowed.text).success;
    };
    expected = {
      declared = true;
      disabledFine = true;
      enabledThrows = false;
    };
  };

  # Hosts import every role and NixOS module: own, internal/ and extra*.
  testSharingHostImportsAll = {
    expr = fixtureOptions sharingPlain.nixosConfigurations.test;
    expected = ["nixosExtra" "nixosPrivate" "nixosPublic" "roleExtra" "rolePrivate" "rolePublic"];
  };

  # Users get every profile and HM module: own, internal/ and extra*.
  testSharingHomeImportsAll = {
    expr = fixtureOptions sharingPlain.homeConfigurations.alice;
    expected = ["homeExtra" "homePrivate" "homePublic" "profilePrivate" "profilePublic"];
  };

  # Exports are this flake's own pieces only: no internal/, no extra*.
  testSharingExportsOwnOnly = {
    expr = exportNames sharingPlain;
    expected = {
      roles = ["public"];
      profiles = ["pub"];
      nixosModules = ["mod"];
      homeModules = ["hmod"];
    };
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
        paths = [(sharing + "/nixos/mod.nix")];
      };
      home = {
        _class = "homeManager";
        paths = [(sharing + "/home/hmod.nix")];
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

  # NixOS hosts get NixOS halves only, so a darwin-only extra role (a
  # directory without default.nix) is skipped instead of failing to import.
  # `roles` exports every own role, darwin-only ones included.
  testPlatformRolesNixosHost = let
    out = flakeWith {
      rolesDir = ./fixtures/platforms/roles;
      extraRoles.extra-darwin = ./fixtures/platforms/roles/darwin-only;
    };
  in {
    expr = {
      options = builtins.attrNames out.nixosConfigurations.test.options.fixture;
      exported = builtins.attrNames out.roles;
    };
    expected = {
      options = ["bothNixos" "file" "nixosDir"];
      exported = ["both" "darwin-only" "file" "nixos-dir"];
    };
  };

  # The same name in a dir and its internal/ throws instead of one winning.
  testSharingInternalClashThrows = {
    expr =
      (builtins.tryEval (builtins.attrNames
        (flakeWith {rolesDir = ./fixtures/sharing-clash/roles;})
        .roles))
      .success;
    expected = false;
  };
}
