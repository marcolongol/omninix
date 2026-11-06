# OmniNix Layer 4 — roles.impermanent wipe script on real btrfs (runNixOSTest).
#
# Runs the role's generated rollback-root script against throwaway loopback
# btrfs images inside the VM (never real disks) and asserts the outcome of each
# failure mode. Unit ordering in the initrd is covered by config-tests.
{
  pkgs,
  inputs,
  lib,
}: let
  # rollback-root's script as the role generates it for a fixture host.
  scriptFor = extra:
    (lib.omninix.mkNixosConfigurations {
      inherit inputs;
      defaultSystem = pkgs.stdenv.hostPlatform.system;
      roles.impermanent = ../roles/impermanent.nix;
      hosts.wipe = {
        lib,
        options,
        ...
      }: {
        imports = [./stubs/impermanence.nix extra];
        system.stateVersion = "26.05";
        # Only on nixpkgs that still has scripted initrd (see roles/impermanent.nix).
        boot.initrd.systemd.enable = lib.mkIf (options.boot.initrd.systemd.enable.visible or true) true;
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
    })
    .wipe
    .config
    .boot
    .initrd
    .systemd
    .services
    .rollback-root
    .script;

  plain = pkgs.writeText "rollback-root.sh" (scriptFor {});
  # wipe.device overridden to a different path than fileSystems."/".device.
  override = pkgs.writeText "rollback-root-override.sh" (scriptFor {
    roles.impermanent.wipe.device = "/dev/disk/by-label/other";
  });
in
  pkgs.testers.runNixOSTest {
    name = "omninix-impermanent-wipe";
    nodes.machine = {pkgs, ...}: {
      boot.supportedFilesystems = ["btrfs"];
      virtualisation.memorySize = 2048;
      environment.systemPackages = [pkgs.btrfs-progs pkgs.util-linux];
      environment.etc."wipe/plain.sh".source = plain;
      environment.etc."wipe/override.sh".source = override;
      environment.etc."wipe/scenarios.sh".source = ./vm-impermanent-scenarios.sh;
    };
    testScript = ''
      machine.start()
      machine.wait_for_unit("multi-user.target")
      print(machine.succeed("bash /etc/wipe/scenarios.sh /etc/wipe/plain.sh /etc/wipe/override.sh"))
    '';
  }
