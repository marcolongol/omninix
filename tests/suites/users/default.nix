# The secure core: users a host enables get no privileged groups unless
# granted, and a host refuses to build while an active user has no password.
{
  lib,
  evalHosts,
  ...
}: let
  # Evaluate one host and return its config.
  host = module: (evalHosts {hosts.test = module;}).test;

  # OmniNix's failing assertions, as their messages. NixOS adds its own
  # assertions, so keep only ours.
  failures = config:
    map (a: a.message) (lib.filter (a: !a.assertion && lib.hasPrefix "OmniNix:" a.message) config.assertions);

  alice = extra: {omninix.hostUsers.alice = {enable = true;} // extra;};
  withPassword = {users.users.alice.hashedPassword = "$y$fake";};
in {
  # --- which users exist -----------------------------------------------------

  testActiveUsersAreTheEnabledOnes = {
    expr =
      (host {
        omninix.hostUsers = {
          alice.enable = true;
          bob.enable = false;
        };
      })
      .omninix
      .activeUsers;
    expected = ["alice"];
  };

  testActiveUserIsANormalUser = {
    expr = (host (alice {})).users.users.alice.isNormalUser;
    expected = true;
  };

  # --- groups ----------------------------------------------------------------

  # No wheel, no docker: privileged groups are always opt-in.
  testNoGroupsByDefault = {
    expr = (host (alice {})).users.users.alice.extraGroups;
    expected = [];
  };

  testHostWideAndPerUserGroups = {
    expr =
      (host {
        imports = [(alice {extraGroups = ["wheel"];})];
        omninix.defaultUserGroups = ["networkmanager"];
      })
      .users
      .users
      .alice
      .extraGroups;
    expected = ["networkmanager" "wheel"];
  };

  # --- mutableUsers ----------------------------------------------------------

  # Declared passwords only reach the machine when users aren't mutable.
  testMutableUsersOffWithActiveUsers = {
    expr = (host (alice {})).users.mutableUsers;
    expected = false;
  };

  testMutableUsersCanBeTurnedBackOn = {
    expr =
      (host {
        imports = [(alice {})];
        users.mutableUsers = true;
      }).users.mutableUsers;
    expected = true;
  };

  # A host that doesn't use hostUsers keeps NixOS' default.
  testMutableUsersUntouchedWithoutUsers = {
    expr = (host {}).users.mutableUsers;
    expected = true;
  };

  # --- passwords -------------------------------------------------------------

  testNoPasswordFails = {
    expr = map (lib.hasInfix "alice") (failures (host (alice {})));
    expected = [true];
  };

  testPasswordPasses = {
    expr = failures (host {imports = [(alice {}) withPassword];});
    expected = [];
  };

  # Each of the five NixOS password options counts.
  testEveryPasswordOptionCounts = {
    expr = map (opt: failures (host {imports = [(alice {}) {users.users.alice.${opt} = "x";}];})) [
      "hashedPassword"
      "hashedPasswordFile"
      "initialHashedPassword"
      "initialPassword"
      "password"
    ];
    expected = [[] [] [] [] []];
  };

  # An empty password logs in without one, so it doesn't count.
  testEmptyPasswordFails = {
    expr = lib.length (failures (host {imports = [(alice {}) {users.users.alice.hashedPassword = "";}];}));
    expected = 1;
  };

  # A disabled user needs no password.
  testDisabledUserNeedsNoPassword = {
    expr = failures (host {omninix.hostUsers.alice.enable = false;});
    expected = [];
  };

  # --- insecure bootstrap ----------------------------------------------------

  testBootstrapBuildsButWarns = let
    c = host {
      imports = [(alice {})];
      omninix.allowInsecureBootstrap = true;
    };
  in {
    expr = {
      failures = failures c;
      noPasswordLogin = c.users.allowNoPasswordLogin;
      warned = lib.any (lib.hasInfix "allowInsecureBootstrap") c.warnings;
    };
    expected = {
      failures = [];
      noPasswordLogin = true;
      warned = true;
    };
  };

  # Bootstrap only opens passwordless login while someone actually lacks a
  # password.
  testBootstrapClosesOnceEveryoneHasAPassword = {
    expr =
      (host {
        imports = [(alice {}) withPassword];
        omninix.allowInsecureBootstrap = true;
      })
      .users
      .allowNoPasswordLogin;
    expected = false;
  };
}
