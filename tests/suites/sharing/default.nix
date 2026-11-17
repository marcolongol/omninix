# Sharing between flakes: what a flake exports (not internal/, not extra*),
# what it borrows (extra*, ours winning a clash), and the guards that keep a
# borrowed piece from silently reading the wrong flake.
{
  lib,
  evalHosts,
  evalFlake,
  failures,
  ...
}: let
  their = ./their;

  # Our fixture flake, borrowing some of `their` pieces, plus `extra`.
  ourFlake = extra:
    evalFlake {
      imports = [extra];
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

  flake = ourFlake {};
  laptop = flake.nixosConfigurations.laptop.config;
  alice = laptop.home-manager.users.alice;

  readsInputs = their + "/roles/reads-inputs.nix";

  # A host (or, given `users`, a host home) that requires `option`.
  requiring = option: {
    by = "roles.desktop";
    inherit option;
    module = "the module declaring ${option}";
  };
  missing = option: "OmniNix: roles.desktop needs the module declaring ${option}; import it (the option `${option}` doesn't exist).";
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
      profiles = lib.attrNames alice.profiles;
      motd = laptop.users.motd;
      editor = alice.home.sessionVariables.EDITOR;
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
    expr = let
      host = (ourFlake {omninix.extraRoles.reads-inputs = readsInputs;}).nixosConfigurations.laptop.config;
    in
      (builtins.tryEval host.environment.etc.theirs-input.text).success;
    expected = false;
  };

  # Our own pieces read our inputs as usual.
  testOwnPieceReadsInputs = {
    expr =
      (evalHosts {
        hosts.h = {};
        nixosModules.reads-inputs = readsInputs;
      }).h.environment.etc.theirs-input.text;
    expected = "1";
  };

  # --- requirements ----------------------------------------------------------

  testRequirementMissing = {
    expr = failures (evalHosts {hosts.h.omninix.requirements = [(requiring "stylix.image")];}).h;
    expected = [(missing "stylix.image")];
  };

  testRequirementMet = {
    expr =
      failures
      (evalHosts {
        hosts.h = {
          imports = [{options.stylix.image = lib.mkOption {default = null;};}];
          omninix.requirements = [(requiring "stylix.image")];
        };
      }).h;
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
        users.alice.omninix.requirements = [(requiring "programs.nixievim.enable")];
      }).h.home-manager.users.alice;
    expected = [(missing "programs.nixievim.enable")];
  };
}
