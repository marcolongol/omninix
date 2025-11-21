# OmniNix Layer 4 — NixOS VM boot test (runNixOSTest).
#
# Builds and boots a real host that uses the OmniNix NixOS module, then asserts
# the security/user model produces what it should on a live system:
#   - the active user is created
#   - opt-in groups are granted (wheel) and non-granted ones are NOT (docker)
#   - a password is actually set (account not locked)
#   - Home Manager activated (home dir exists)
#
# `lib` here is the OmniNix-extended lib; capture mkHomeModules before entering the
# node module (whose own `lib` arg would shadow it).
{
  pkgs,
  inputs,
  lib,
}: let
  mkHomeModules = lib.omninix.mkHomeModules;
in
  pkgs.testers.runNixOSTest {
    name = "omninix-user-groups";

    # specialArgs that modules/nixos expects, supplied the same way
    # mkNixosConfigurations does. Must be specialArgs (not _module.args): the
    # latter routes through `config` and would cause infinite recursion when the
    # module computes home-manager.users.*.imports.
    node.specialArgs = {
      inherit inputs mkHomeModules;
      hostName = "machine";
      users = {};
      profiles = {};
      homeManagerModules = {};
      secretsPath = null;
    };

    nodes.machine = {...}: {
      imports = [
        inputs.home-manager.nixosModules.home-manager
        (import ../modules/nixos)
      ];

      system.stateVersion = "26.05";

      # The unit-under-test: opt-in groups + a real password (so no bootstrap).
      omninix.hostUsers.alice = {
        enable = true;
        extraGroups = ["wheel"];
      };
      users.users.alice.password = "test";
    };

    testScript = ''
      machine.wait_for_unit("multi-user.target")

      # User exists.
      machine.succeed("id alice")

      # Opt-in group granted; non-granted group absent (no wheel/docker by default).
      machine.succeed("id -nG alice | grep -qw wheel")
      machine.fail("id -nG alice | grep -qw docker")

      # Home Manager activated for the user.
      machine.succeed("test -d /home/alice")

      # A password hash is set (account is not locked).
      machine.succeed(r"getent shadow alice | cut -d: -f2 | grep -q '^\$'")
    '';
  }
