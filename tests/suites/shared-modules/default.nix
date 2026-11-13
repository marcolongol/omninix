# sharedModules / sharedHomeModules: modules every host / every home
# imports. Roles and profiles are such modules that stay off until enabled.
{
  lib,
  inputs,
  evalHosts,
  ...
}: let
  # A role in the usual shape: its own enable switch and settings, applied
  # only when a host turns it on. It adds every active user to docker.
  dockerRole = {
    config,
    lib,
    ...
  }: {
    options.roles.docker.enable = lib.mkEnableOption "docker, adding every active user to its group";
    config = lib.mkIf config.roles.docker.enable {
      virtualisation.docker.enable = true;
      users.users = lib.genAttrs config.omninix.activeUsers (_: {extraGroups = ["docker"];});
    };
  };

  # A profile: the same shape, for Home Manager.
  gitProfile = {
    config,
    lib,
    ...
  }: {
    options.profiles.git.enable = lib.mkEnableOption "git";
    config = lib.mkIf config.profiles.git.enable {programs.git.enable = true;};
  };

  alice = {
    omninix.hostUsers.alice.enable = true;
    users.users.alice.hashedPassword = "$y$fake";
  };

  hosts = evalHosts {
    hosts = {
      with-docker = {
        imports = [alice];
        roles.docker.enable = true;
      };
      without = alice;
    };
    sharedModules = [dockerRole];
    sharedHomeModules = [gitProfile];
    users.alice = {profiles.git.enable = true;};
  };
in {
  # Every host gets the role; only the one enabling it is affected.
  testRoleOnlyWhereEnabled = {
    expr = lib.mapAttrs (_: c: c.virtualisation.docker.enable) hosts;
    expected = {
      with-docker = true;
      without = false;
    };
  };

  # A role can read the rest of the config, here the active users.
  testRoleReadsActiveUsers = {
    expr = lib.elem "docker" hosts.with-docker.users.users.alice.extraGroups;
    expected = true;
  };

  # A profile reaches host homes...
  testProfileOnHostHome = {
    expr = hosts.without.home-manager.users.alice.programs.git.enable;
    expected = true;
  };

  # ...and standalone homes.
  testProfileOnStandaloneHome = {
    expr =
      (lib.omninix.mkHomeConfigurations {
        inherit inputs;
        users.alice = {profiles.git.enable = true;};
        sharedHomeModules = [gitProfile];
      })
      .alice
      .config
      .programs
      .git
      .enable;
    expected = true;
  };

  # A user with no file still gets shared home modules (off by default).
  testProfileDeclaredForUserWithoutFile = {
    expr = let
      c = evalHosts {
        hosts.h = {
          omninix.hostUsers.bob.enable = true;
          users.users.bob.hashedPassword = "$y$fake";
        };
        sharedHomeModules = [gitProfile];
      };
    in
      c.h.home-manager.users.bob.profiles.git.enable;
    expected = false;
  };

  # Shared home modules alone also need Home Manager, or they'd be dropped.
  testSharedHomeModulesWithoutHomeManagerThrows = {
    expr =
      (builtins.tryEval (evalHosts {
        hosts.h = {};
        sharedHomeModules = [gitProfile];
        inputs = removeAttrs inputs ["home-manager"];
      }))
      .success;
    expected = false;
  };
}
