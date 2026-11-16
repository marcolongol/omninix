# roles.impermanent and omninix.persistence: what survives a reboot, on the
# host and in homes, and the guards around wiping the root.
{
  lib,
  inputs,
  evalHosts,
  ...
}: let
  role = inputs.self.roles.impermanent;

  # A host on btrfs with the role on and a user, alice.
  host = {
    withImpermanence ? true,
    extra ? {},
  }:
    (evalHosts {
      hosts.h = {
        imports = [extra];
        roles.impermanent.enable = true;
        fileSystems."/" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "btrfs";
          options = ["subvol=root"];
        };
        fileSystems."/persist" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "btrfs";
          options = ["subvol=persist"];
        };
        omninix.hostUsers.alice.enable = true;
        users.users.alice.hashedPassword = "$y$fake";
      };
      sharedModules = [role] ++ lib.optional withImpermanence inputs.impermanence.nixosModules.impermanence;
      users.alice = {omninix.persistence.directories = [".ssh"];};
    })
    .h;

  persisted = config: let
    p = config.environment.persistence."/persist";
  in {
    directories = map (d: d.directory) p.directories;
    files = map (f: f.file) p.files;
  };

  failures = config:
    map (a: a.message) (lib.filter (a: !a.assertion && lib.hasPrefix "OmniNix:" a.message) config.assertions);

  wipe = extra:
    host {
      extra = {
        imports = [extra];
        roles.impermanent.wipe.enable = true;
      };
    };
in {
  testShipped = {
    expr = lib.attrNames inputs.self.roles;
    expected = ["impermanent"];
  };

  # --- what persists ----------------------------------------------------------

  testSystemPaths = {
    expr = persisted (host {
      extra = {
        omninix.persistence = {
          directories = ["/var/lib/docker"];
          files = ["/etc/adjtime"];
        };
      };
    });
    expected = {
      directories = ["/var/log" "/var/lib/nixos" "/var/lib/docker"];
      files = ["/etc/machine-id" "/etc/adjtime"];
    };
  };

  # Paths for what the host actually runs.
  testServicePaths = {
    expr =
      (persisted (host {
        extra = {
          networking.networkmanager.enable = true;
          hardware.bluetooth.enable = true;
          roles.impermanent.persistCoredumps = true;
        };
      }))
      .directories;
    expected = ["/var/log" "/var/lib/nixos" "/var/lib/bluetooth" "/var/lib/systemd/coredump" "/etc/NetworkManager/system-connections"];
  };

  testPersistNeededForBoot = {
    expr = (host {}).fileSystems."/persist".neededForBoot;
    expected = true;
  };

  # A user's omninix.persistence reaches impermanence in their home.
  testHomePaths = {
    expr = map (d: d.directory) (host {}).home-manager.users.alice.home.persistence."/persist".directories;
    expected = [".ssh"];
  };

  # Standalone homes have the option too (profiles set it unconditionally),
  # it just has nowhere to go.
  testStandaloneHomeHasOption = {
    expr =
      (lib.omninix.mkHomeConfigurations {
        inherit inputs;
        users.alice = {omninix.persistence.directories = [".ssh"];};
      })
      .alice
      .config
      .omninix
      .persistence
      .directories;
    expected = [".ssh"];
  };

  # --- ssh host keys ------------------------------------------------------------

  # Keys live in /persist itself; sops-nix's default key path follows them.
  testHostKeysInPersist = {
    expr = let
      c = host {extra = {services.openssh.enable = true;};};
    in {
      keys = map (k: k.path) c.services.openssh.hostKeys;
      sops = c.sops.age.sshKeyPaths;
    };
    expected = {
      keys = ["/persist/etc/ssh/ssh_host_ed25519_key" "/persist/etc/ssh/ssh_host_rsa_key"];
      sops = ["/persist/etc/ssh/ssh_host_ed25519_key"];
    };
  };

  # --- the requirement --------------------------------------------------------

  testNeedsImpermanence = {
    expr = map (lib.hasPrefix "OmniNix: roles.impermanent needs impermanence's NixOS module") (failures (host {withImpermanence = false;}));
    expected = [true];
  };

  # --- wiping the root --------------------------------------------------------

  testWipeNeedsAcknowledgement = {
    expr = map (lib.hasInfix "acknowledgeDataLoss") (failures (wipe {boot.initrd.systemd.enable = true;}));
    expected = [true];
  };

  testWipeReady = {
    expr = let
      c = wipe {
        boot.initrd.systemd.enable = true;
        roles.impermanent.wipe.acknowledgeDataLoss = true;
      };
    in {
      failures = failures c;
      unit = c.boot.initrd.systemd.services ? rollback-root;
      check = c.systemd.services ? rollback-root-check;
    };
    expected = {
      failures = [];
      unit = true;
      check = true;
    };
  };

  # The wipe needs a btrfs root, systemd initrd, and one named subvolume.
  testWipeGuards = {
    expr = let
      ready = {
        boot.initrd.systemd.enable = true;
        roles.impermanent.wipe.acknowledgeDataLoss = true;
      };
      messagesFor = extra: map (m: lib.last (lib.splitString "wipe: " m)) (failures (wipe {imports = [ready extra];}));
    in {
      ext4 = messagesFor {fileSystems."/".fsType = lib.mkForce "ext4";};
      nested = messagesFor {fileSystems."/".options = lib.mkForce ["subvol=root/nested"];};
      overlap = messagesFor {
        fileSystems."/home" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "btrfs";
          options = ["subvol=root/home"];
        };
      };
    };
    expected = {
      ext4 = ["fileSystems.\"/\" must be btrfs."];
      nested = ["fileSystems.\"/\" must mount exactly one top-level subvolume via subvol=<name> (subvolid= only, the top level, or nested names are refused)."];
      overlap = ["the root subvolume (or one nested under it) is also mounted at /home; wiping would destroy it."];
    };
  };
}
