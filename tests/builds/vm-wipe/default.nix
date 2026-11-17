# roles.impermanent's root wipe, run for real: the rollback-root script the
# role generates, against throwaway loopback btrfs images inside a VM (never
# a real disk), once per failure mode (scenarios.sh). The unit's place in the
# initrd is covered by the impermanence suite. Linux only.
{
  pkgs,
  lib,
  inputs,
}: let
  # rollback-root's script, as the role generates it for a host on btrfs.
  scriptFor = extra:
    (lib.omninix.mkNixosConfigurations {
      inherit inputs;
      defaultSystem = pkgs.stdenv.hostPlatform.system;
      roles.impermanent = inputs.self.roles.impermanent;
      hosts.wipe = {
        imports = [extra];
        system.stateVersion = "26.05";
        boot.initrd.systemd.enable = true;
        fileSystems."/" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "btrfs";
          options = ["subvol=/root"];
        };
        fileSystems."/persist" = {
          device = "/dev/disk/by-label/persist";
          fsType = "ext4";
        };
        roles.impermanent = {
          enable = true;
          wipe = {
            enable = true;
            acknowledgeDataLoss = true;
          };
        };
      };
    }).wipe.config.boot.initrd.systemd.services.rollback-root.script;

  plain = pkgs.writeText "rollback-root.sh" (scriptFor {});
  # wipe.device pointing elsewhere than fileSystems."/".device.
  override = pkgs.writeText "rollback-root-override.sh" (scriptFor {
    roles.impermanent.wipe.device = "/dev/disk/by-label/other";
  });
in
  lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    vm-wipe = pkgs.testers.runNixOSTest {
      name = "omninix-vm-wipe";
      nodes.machine = {pkgs, ...}: {
        boot.supportedFilesystems = ["btrfs"];
        virtualisation.memorySize = 2048;
        environment = {
          systemPackages = [pkgs.btrfs-progs pkgs.util-linux];
          etc = {
            "wipe/plain.sh".source = plain;
            "wipe/override.sh".source = override;
            "wipe/scenarios.sh".source = ./scenarios.sh;
          };
        };
      };
      testScript = ''
        machine.wait_for_unit("multi-user.target")
        print(machine.succeed("bash /etc/wipe/scenarios.sh /etc/wipe/plain.sh /etc/wipe/override.sh"))
      '';
    };
  }
