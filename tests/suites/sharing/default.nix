# Sharing between flakes: what a flake exports (not internal/, not extra*),
# what it borrows (extra*, ours winning a clash), and the guards that keep a
# borrowed piece from silently reading the wrong flake.
{
  lib,
  inputs,
  evalHosts,
  ...
}: let
  their = ./their;

  evalFlake = extra:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [inputs.self.flakeModules.default extra];
      systems = ["x86_64-linux"];
      omninix = {
        hostsDir = ./fixture/hosts;
        usersDir = ./fixture/users;
        rolesDir = ./fixture/roles;
        profilesDir = ./fixture/profiles;
        extraRoles = {
          theirs = their + "/roles/theirs.nix";
          clash = their + "/roles/clash.nix";
          # An inline module rather than a path: fine on NixOS hosts.
          inline = {lib, ...}: {options.roles.inline.enable = lib.mkEnableOption "inline";};
        };
        extraProfiles.their-profile = their + "/profiles/their-profile.nix";
        extraNixosModules.motd = {users.motd = "borrowed";};
        extraHomeModules.editor = {home.sessionVariables.EDITOR = "vim";};
      };
    };

  flake = evalFlake {};
  laptop = flake.nixosConfigurations.laptop.config;

  # OmniNix's failing assertions, as messages.
  failures = config:
    map (a: a.message) (lib.filter (a: !a.assertion && lib.hasPrefix "OmniNix:" a.message) config.assertions);
in {
  # --- internal/ -------------------------------------------------------------

  testInternalUsedHere = {
    expr = laptop.roles ? private;
    expected = true;
  };

  testExportsLeaveOutInternalAndExtras = {
    expr = {
      roles = lib.attrNames flake.roles;
      profiles = lib.attrNames flake.profiles;
    };
    expected = {
      roles = ["clash" "public"];
      profiles = ["mine"];
    };
  };

  testDiscoverPieces = {
    expr = lib.mapAttrs (_: lib.attrNames) (lib.omninix.discoverPieces ["default.nix"] ./fixture/roles);
    expected = {
      all = ["clash" "private" "public"];
      exportable = ["clash" "public"];
    };
  };

  testInternalClashThrows = {
    expr = (builtins.tryEval (lib.omninix.discoverPieces ["default.nix"] ./clash)).success;
    expected = false;
  };

  # --- extra* ----------------------------------------------------------------

  testExtrasApplied = {
    expr = {
      roles = lib.attrNames laptop.roles;
      profiles = lib.attrNames laptop.home-manager.users.alice.profiles;
      motd = laptop.users.motd;
      editor = laptop.home-manager.users.alice.home.sessionVariables.EDITOR;
    };
    expected = {
      roles = ["inline" "private" "public" "theirs"];
      profiles = ["mine" "their-profile"];
      motd = "borrowed";
      editor = "vim";
    };
  };

  # Ours wins a name clash: theirs isn't imported at all.
  testOursWinsAClash = {
    expr = laptop.environment.etc.clash.text;
    expected = "ours";
  };

  # --- borrowed pieces reading `inputs` --------------------------------------

  # It would get *our* inputs without a word; instead, reading them fails.
  testBorrowedPieceReadingInputsFails = {
    expr =
      (builtins.tryEval
        (evalFlake {omninix.extraRoles.reads-inputs = their + "/roles/reads-inputs.nix";})
        .nixosConfigurations
        .laptop
        .config
        .environment
        .etc
        .theirs-input
        .text)
      .success;
    expected = false;
  };

  # Our own pieces read our inputs as usual.
  testOwnPieceReadsInputs = {
    expr =
      (evalHosts {
        hosts.h = {};
        nixosModules.reads-inputs = their + "/roles/reads-inputs.nix";
      })
      .h
      .environment
      .etc
      .theirs-input
      .text;
    expected = "1";
  };

  # --- requirements ----------------------------------------------------------

  testRequirementMissing = {
    expr =
      failures
      (evalHosts {
        hosts.h = {
          omninix.requirements = [
            {
              by = "roles.desktop";
              option = "stylix.image";
              module = "stylix's NixOS module";
            }
          ];
        };
      })
      .h;
    expected = ["OmniNix: roles.desktop needs stylix's NixOS module; import it (the option `stylix.image` doesn't exist)."];
  };

  testRequirementMet = {
    expr =
      failures
      (evalHosts {
        hosts.h = {
          imports = [{options.stylix.image = lib.mkOption {default = null;};}];
          omninix.requirements = [
            {
              by = "roles.desktop";
              option = "stylix.image";
              module = "stylix's NixOS module";
            }
          ];
        };
      })
      .h;
    expected = [];
  };

  # Homes have requirements too. Read on a host home: a standalone home
  # throws on failed assertions as soon as its config is read.
  testHomeRequirement = {
    expr =
      failures
      (evalHosts {
        hosts.h = {
          omninix.hostUsers.alice.enable = true;
          users.users.alice.hashedPassword = "$y$fake";
        };
        users.alice = {
          omninix.requirements = [
            {
              by = "profiles.editor";
              option = "programs.nixievim.enable";
              module = "nixievim's Home Manager module";
            }
          ];
        };
      })
      .h
      .home-manager
      .users
      .alice;
    expected = ["OmniNix: profiles.editor needs nixievim's Home Manager module; import it (the option `programs.nixievim.enable` doesn't exist)."];
  };
}
