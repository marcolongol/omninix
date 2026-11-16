# A host booted in a VM, built from exactly what mkNixosConfigurations would
# build (nixosHostEvalArgs), then checked on the running system:
#   - alice exists, with wheel (granted) and without docker (never granted)
#   - her password came from sops: decrypted before users were created
#   - her home was activated by Home Manager
# Linux only: it boots a QEMU guest.
{
  pkgs,
  lib,
  inputs,
}: let
  host =
    lib.omninix.nixosHostEvalArgs {
      inherit inputs;
      secretsPath = ./secrets;
      users.alice = {home.file.greeting.text = "hi";};
    } "machine" {
      system.stateVersion = "26.05";
      omninix.hostUsers.alice = {
        enable = true;
        extraGroups = ["wheel"];
      };
      # The throwaway key that encrypted secrets/users/alice.yaml. A real host
      # uses its SSH host key; this one has no sshd. sops-nix refuses keys in
      # the (world-readable) store, so it's copied out first, below.
      sops.age.keyFile = "/run/test-age-key";
    };

  # Copy the key out of the store before sops decrypts the user passwords.
  testKey = {
    system.activationScripts.testAgeKey = {
      deps = ["specialfs"];
      text = "install -m 0400 ${./age-key.txt} /run/test-age-key";
    };
    system.activationScripts.setupSecretsForUsers.deps = ["testAgeKey"];
  };
in
  lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    vm-host = pkgs.testers.runNixOSTest {
      name = "omninix-vm-host";
      node = {
        inherit (host) specialArgs;
        # The host sets nixpkgs options (overlays, platform) like any OmniNix
        # host, so the test can't hand it a read-only pkgs.
        pkgsReadOnly = false;
      };
      nodes.machine.imports = host.modules ++ [testKey];

      testScript = ''
        machine.wait_for_unit("multi-user.target")

        with subtest("alice exists, with only the groups she was given"):
            machine.succeed("id alice")
            machine.succeed("id -nG alice | grep -qw wheel")
            machine.fail("id -nG alice | grep -qw docker")

        with subtest("her password is the hash sops decrypted"):
            expected = "${lib.trim (builtins.readFile ./expected-hash)}"
            actual = machine.succeed("getent shadow alice | cut -d: -f2").strip()
            assert actual == expected, f"shadow has {actual!r}"

        with subtest("Home Manager activated her home"):
            machine.wait_for_unit("home-manager-alice.service")
            machine.succeed("test \"$(cat /home/alice/greeting)\" = hi")
      '';
    };
  }
