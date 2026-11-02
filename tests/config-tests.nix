# OmniNix Layer 2 — config-behaviour tests (lib.runTests format).
#
# Each test evaluates a fixture host through the real mkNixosConfigurations
# builder and asserts on the resulting NixOS `config`. No VM/build — pure
# evaluation — so these are fast and cover the module logic the launch review
# changed (security fail-closed, opt-in groups, per-host system, allowUnfree,
# the omninix.* namespace).
{
  inputs,
  omninix,
  lib,
  system,
}: let
  # Evaluate one inline fixture host through the real builder and return the
  # full nixosSystem result (has `.config`, `.pkgs`, …). mkNixosConfigurations
  # places the host value directly into the module list, so a function module
  # works in place of a path.
  evalSystem = {
    module,
    hostSystems ? {},
    allowUnfree ? false,
    roles ? {},
    secretsPath ? null,
  }:
    (omninix.mkNixosConfigurations {
      inherit inputs hostSystems allowUnfree roles secretsPath;
      defaultSystem = system;
      # Wrap each fixture so it carries a stateVersion (silences the eval
      # warning) while the test's own module supplies the behaviour under test.
      hosts = {
        test = {...}: {
          imports = [module];
          system.stateVersion = "26.05";
        };
      };
    })
    .test;

  evalHost = args: (evalSystem args).config;

  # Minimal active user that passes fail-closed via the bootstrap flag.
  bootstrapUser = {...}: {
    omninix.hostUsers.alice.enable = true;
    omninix.allowInsecureBootstrap = true;
  };

  hasFailingAssertion = needle: config:
    builtins.any (a: !a.assertion && lib.hasInfix needle a.message) config.assertions;

  # Real on-disk secrets fixture. modules/nixos gates the user-password wiring on
  # the per-user file actually existing (builtins.pathExists), so this must be a
  # real path. The file is never decrypted here (pure eval) — see
  # tests/fixtures/secrets/users/alice.yaml.
  secretsFixture = ./fixtures/secrets;

  # An active user with a sops secret file present, no bootstrap.
  aliceWithSecret = {
    module = {...}: {omninix.hostUsers.alice.enable = true;};
    secretsPath = secretsFixture;
  };
in {
  # --- security model (B1/H4/M9/G2) ----------------------------------------

  # Fail closed: an active user with no password yields a failing assertion.
  testPasswordlessFailsClosed = {
    expr = hasFailingAssertion "no password" (evalHost {
      module = {...}: {omninix.hostUsers.alice.enable = true;};
    });
    expected = true;
  };

  # The bootstrap escape hatch clears that assertion...
  testBootstrapClearsAssertion = {
    expr = hasFailingAssertion "no password" (evalHost {module = bootstrapUser;});
    expected = false;
  };

  # ...and is the only thing that enables passwordless login.
  testBootstrapAllowsNoPasswordLogin = {
    expr = (evalHost {module = bootstrapUser;}).users.allowNoPasswordLogin;
    expected = true;
  };

  # mutableUsers defaults to true so `passwd` works during bootstrap.
  testMutableUsersDefaultTrue = {
    expr = (evalHost {module = bootstrapUser;}).users.mutableUsers;
    expected = true;
  };

  # --- active users --------------------------------------------------------

  # Only enabled hostUsers are listed.
  testActiveUsersListsEnabledOnly = {
    expr =
      (evalHost {
        module = {...}: {
          imports = [bootstrapUser];
          omninix.hostUsers.bob.enable = false;
        };
      })
      .omninix
      .activeUsers;
    expected = ["alice"];
  };

  # No users: empty list, not an error.
  testActiveUsersEmpty = {
    expr = (evalHost {module = {...}: {};}).omninix.activeUsers;
    expected = [];
  };

  # --- groups (H4) ---------------------------------------------------------

  # No privileged groups granted by default.
  testNoDefaultGroups = {
    expr = (evalHost {module = bootstrapUser;}).users.users.alice.extraGroups;
    expected = [];
  };

  # defaultUserGroups + per-user extraGroups compose.
  testPerUserAndDefaultGroups = {
    expr =
      (evalHost {
        module = {...}: {
          omninix.allowInsecureBootstrap = true;
          omninix.defaultUserGroups = ["networkmanager"];
          omninix.hostUsers.alice = {
            enable = true;
            extraGroups = ["wheel"];
          };
        };
      })
      .users.users.alice.extraGroups;
    expected = ["networkmanager" "wheel"];
  };

  # Empty passwords log in without one, so they must not satisfy fail-closed.
  testEmptyInitialPasswordFailsClosed = {
    expr = hasFailingAssertion "no password" (evalHost {
      module = {...}: {
        omninix.hostUsers.alice.enable = true;
        users.users.alice.initialPassword = "";
      };
    });
    expected = true;
  };

  testEmptyHashedPasswordFailsClosed = {
    expr = hasFailingAssertion "no password" (evalHost {
      module = {...}: {
        omninix.hostUsers.alice.enable = true;
        users.users.alice.hashedPassword = "";
      };
    });
    expected = true;
  };

  # A secret file on disk isn't enough: if hashedPasswordFile ends up unset
  # the account would be locked, so it must fail closed too.
  testSecretFileWithoutPasswordFileFailsClosed = {
    expr = hasFailingAssertion "no password" (evalHost (aliceWithSecret
      // {
        module = {lib, ...}: {
          omninix.hostUsers.alice.enable = true;
          users.users.alice.hashedPasswordFile = lib.mkForce null;
        };
      }));
    expected = true;
  };

  # The template impermanent role fails eval when enabled without its input.
  testImpermanentTemplateNeedsInput = {
    expr = hasFailingAssertion "impermanence` flake input is missing" (evalHost {
      roles.impermanent = ../templates/default/roles/impermanent.nix;
      module = {...}: {
        imports = [bootstrapUser];
        roles.impermanent.enable = true;
      };
    });
    expected = true;
  };

  # --- roles with a home side ----------------------------------------------

  # The template's desktop role reaches every HM user via sharedModules.
  testRoleHomeSideReachesUsers = {
    expr =
      (evalHost {
        roles.desktop = ../templates/default/roles/desktop;
        module = {...}: {
          imports = [bootstrapUser];
          roles.desktop.enable = true;
        };
      })
      .home-manager.users.alice.programs.foot.enable;
    expected = true;
  };

  # ...and stays off when the role is disabled.
  testRoleHomeSideOffWhenDisabled = {
    expr =
      (evalHost {
        roles.desktop = ../templates/default/roles/desktop;
        module = bootstrapUser;
      })
      .home-manager.users.alice.programs.foot.enable;
    expected = false;
  };

  # --- per-host system (B5) ------------------------------------------------

  testHostSystemsOverride = {
    expr =
      (evalSystem {
        module = bootstrapUser;
        hostSystems = {test = "aarch64-linux";};
      })
      .pkgs.stdenv.hostPlatform.system;
    expected = "aarch64-linux";
  };

  # --- persistence option seam (impermanence glue) -------------------------

  # The system-level omninix.persistence aggregation seam exists and defaults
  # empty. Consumers' own impermanence role reads it into environment.persistence;
  # the user-level counterpart is wired into home.persistence by modules/nixos.
  testPersistenceDefaultsEmpty = {
    expr = (evalHost {module = bootstrapUser;}).omninix.persistence;
    expected = {
      directories = [];
      files = [];
    };
  };

  # --- nixpkgs config (M4) + namespace (L3) --------------------------------

  testAllowUnfreeDefaultsFalse = {
    expr = (evalHost {module = bootstrapUser;}).nixpkgs.config.allowUnfree;
    expected = false;
  };

  testDefaultUserGroupsDefaultsEmpty = {
    expr = (evalHost {module = bootstrapUser;}).omninix.defaultUserGroups;
    expected = [];
  };

  # --- sops secrets wiring (secretsPath, M-secrets) ------------------------

  # A present per-user secret IS a password mechanism, so the fail-closed
  # assertion clears with NO bootstrap (contrast testPasswordlessFailsClosed).
  testSopsSecretClearsPasswordAssertion = {
    expr = hasFailingAssertion "no password" (evalHost aliceWithSecret);
    expected = false;
  };

  # The per-user password secret is wired from the expected encrypted file,
  # reading the documented `hashed-password` key, decrypted before login.
  testSopsSecretSopsFile = {
    expr = let
      secret = (evalHost aliceWithSecret).sops.secrets."user-password-alice";
    in {
      inherit (secret) key neededForUsers;
      sopsFile = toString secret.sopsFile;
    };
    expected = {
      key = "hashed-password";
      neededForUsers = true;
      sopsFile = toString (secretsFixture + "/users/alice.yaml");
    };
  };

  # The user's hashedPasswordFile points at that secret's runtime path, so the
  # account is password-backed from the decrypted secret.
  testSopsSecretWiredToUser = {
    expr = let
      cfg = evalHost aliceWithSecret;
    in cfg.users.users.alice.hashedPasswordFile == cfg.sops.secrets."user-password-alice".path;
    expected = true;
  };

  # secretsPath set but NO per-user file present: wiring is skipped (no secret,
  # no password), so it must still fail closed rather than crash.
  testSopsMissingSecretFailsClosed = {
    expr = hasFailingAssertion "no password" (evalHost {
      module = {...}: {omninix.hostUsers.bob.enable = true;};
      secretsPath = secretsFixture;
    });
    expected = true;
  };
}
