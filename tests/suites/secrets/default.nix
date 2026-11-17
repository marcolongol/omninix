# secretsPath: sops-nix wired by convention.
#   secrets/users/<user>.yaml  key `hashed-password`: that user's password,
#                              and their default sops file in Home Manager
#   secrets/<host>.yaml        the host's default sops file
# Nothing is decrypted here: these are evaluation tests, checking paths.
{
  lib,
  inputs,
  evalHosts,
  failures,
  ...
}: let
  secrets = ./secrets;

  # alice has a secret file, bob doesn't.
  enable = names: {omninix.hostUsers = lib.genAttrs names (_: {enable = true;});};

  # laptop has a host secret file, desktop doesn't.
  hosts = evalHosts {
    hosts = {
      laptop = enable ["alice"];
      desktop = enable ["alice" "bob"];
    };
    secretsPath = secrets;
  };
  inherit (hosts) laptop desktop;

  # Whether `path` in a nixosSystem's options was given a value.
  isDefined = host: path:
    (lib.attrByPath path {}
      (lib.omninix.mkNixosConfigurations {
        inherit inputs;
        hosts.${host} = {system.stateVersion = "26.05";};
        secretsPath = secrets;
      }).${
        host
      }.options).isDefined;
in {
  # The password secret, decrypted before users are created...
  testUserPasswordSecret = {
    expr = {inherit (laptop.sops.secrets.user-password-alice) sopsFile key neededForUsers;};
    expected = {
      sopsFile = secrets + "/users/alice.yaml";
      key = "hashed-password";
      neededForUsers = true;
    };
  };

  # ...becomes the user's password file, so the password rule is satisfied.
  testUserPasswordWired = {
    expr = {
      file = laptop.users.users.alice.hashedPasswordFile;
      failures = failures laptop;
    };
    expected = {
      file = laptop.sops.secrets.user-password-alice.path;
      failures = [];
    };
  };

  # A user without a secret file gets nothing, and still needs a password.
  testUserWithoutSecret = {
    expr = {
      secret = desktop.sops.secrets ? user-password-bob;
      failures = map (lib.hasInfix "bob") (failures desktop);
    };
    expected = {
      secret = false;
      failures = [true];
    };
  };

  # The host's own secret file is its default, when it exists.
  testHostDefaultSopsFile = {
    expr = {
      laptop = laptop.sops.defaultSopsFile;
      desktop = isDefined "desktop" ["sops" "defaultSopsFile"];
    };
    expected = {
      laptop = secrets + "/laptop.yaml";
      desktop = false;
    };
  };

  # A host can still replace it.
  testHostCanOverrideDefaultSopsFile = {
    expr =
      (evalHosts {
        hosts.laptop = {sops.defaultSopsFile = ./secrets/users/alice.yaml;};
        secretsPath = secrets;
      }).laptop.sops.defaultSopsFile;
    expected = ./secrets/users/alice.yaml;
  };

  # In Home Manager, a user's secret file is their default sops file.
  testHomeDefaultSopsFile = {
    expr = {
      host = laptop.home-manager.users.alice.sops.defaultSopsFile;
      standalone =
        (lib.omninix.mkHomeConfigurations {
          inherit inputs;
          users.alice = {};
          secretsPath = secrets;
        }).alice.config.sops.defaultSopsFile;
    };
    expected = {
      host = secrets + "/users/alice.yaml";
      standalone = secrets + "/users/alice.yaml";
    };
  };

  # sops-nix is there whenever the input is, even without secretsPath, so
  # hosts and homes can use it by hand.
  testSopsWithoutSecretsPath = {
    expr = let
      c = (evalHosts {hosts.h = enable ["alice"] // {users.users.alice.hashedPassword = "$y$fake";};}).h;
    in {
      host = c ? sops;
      home = c.home-manager.users.alice ? sops;
    };
    expected = {
      host = true;
      home = true;
    };
  };

  # secretsPath without sops-nix can't be wired: say so.
  testSecretsPathWithoutSopsThrows = {
    expr =
      (builtins.tryEval (evalHosts {
        hosts.laptop = {};
        secretsPath = secrets;
        inputs = removeAttrs inputs ["sops-nix"];
      })).success;
    expected = false;
  };
}
