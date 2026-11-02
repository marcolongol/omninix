# Ephemeral root with a persistent /persist, plus an optional btrfs root wipe.
#
# Needs impermanence's NixOS module imported by the consumer (the role never
# imports it: the module is a lambda, so a second import is fatal).
{
  config,
  lib,
  options,
  utils,
  ...
}: let
  cfg = config.roles.impermanent;
  hasPersistence = options ? environment && options.environment ? persistence;
  root = config.fileSystems."/" or {};

  subvolOf = fs: map (lib.removePrefix "subvol=") (lib.filter (lib.hasPrefix "subvol=") (fs.options or []));
  trimSlashes = s: lib.removeSuffix "/" (lib.removePrefix "/" s);

  # The wipe target is derived from fileSystems."/" only, never configurable.
  rootSubvols = subvolOf root;
  target = trimSlashes (lib.findFirst (_: true) "" rootSubvols);
  targetValid =
    builtins.length rootSubvols
    == 1
    && builtins.match "[^/]+" target != null
    && !(lib.elem target ["." ".."]);

  # Other mounts using the target subvolume or one nested under it.
  overlapping = lib.attrNames (lib.filterAttrs (mp: fs:
    mp
    != "/"
    && lib.any (s: let
      t = trimSlashes s;
    in
      t == target || lib.hasPrefix "${target}/" t) (subvolOf fs))
  config.fileSystems);

  sv = lib.escapeShellArg target;
  dev = lib.escapeShellArg cfg.wipe.device;
  deviceUnit = "${utils.escapeSystemdPath cfg.wipe.device}.device";
in {
  options.roles.impermanent = {
    enable = lib.mkEnableOption "ephemeral root with a persistent /persist";
    persistCoredumps = lib.mkEnableOption "persisting /var/lib/systemd/coredump";
    wipe = {
      enable = lib.mkEnableOption "rolling the btrfs root subvolume back on every boot";
      acknowledgeDataLoss = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Confirm that everything outside /persist is deleted on every boot. Required by wipe.enable.";
      };
      device = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = root.device or null;
        defaultText = lib.literalExpression ''config.fileSystems."/".device'';
        description = "Block device holding the btrfs filesystem of /.";
      };
      keepDays = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 30;
        description = "Prune rolled-back roots older than this many days.";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = hasPersistence;
          message = "roles.impermanent needs impermanence's NixOS module: import inputs.impermanence.nixosModules.impermanence once (e.g. in nixosModulesDir).";
        }
      ];
      fileSystems."/persist".neededForBoot = true;
    }

    (lib.optionalAttrs hasPersistence {
      environment.persistence."/persist" = {
        enable = true;
        hideMounts = true;
        directories =
          ["/var/log"]
          ++ lib.optional config.hardware.bluetooth.enable "/var/lib/bluetooth"
          ++ ["/var/lib/nixos"]
          ++ lib.optional cfg.persistCoredumps "/var/lib/systemd/coredump"
          ++ lib.optional config.networking.networkmanager.enable "/etc/NetworkManager/system-connections"
          ++ ["/etc/ssh"]
          ++ config.omninix.persistence.directories;
        files = ["/etc/machine-id"] ++ config.omninix.persistence.files;
      };
    })

    (lib.mkIf cfg.wipe.enable {
      assertions = [
        {
          assertion = cfg.wipe.acknowledgeDataLoss;
          message = "roles.impermanent.wipe deletes everything outside /persist on every boot. Seed /persist (at least /persist/etc/ssh) first, then set roles.impermanent.wipe.acknowledgeDataLoss = true.";
        }
        {
          assertion = (root.fsType or null) == "btrfs";
          message = "roles.impermanent.wipe: fileSystems.\"/\" must be btrfs.";
        }
        {
          assertion = config.boot.initrd.systemd.enable;
          message = "roles.impermanent.wipe: requires boot.initrd.systemd.enable.";
        }
        {
          assertion = cfg.wipe.device != null;
          message = "roles.impermanent.wipe: set wipe.device (fileSystems.\"/\".device is unset).";
        }
        {
          assertion = targetValid;
          message = "roles.impermanent.wipe: fileSystems.\"/\" must mount exactly one top-level subvolume via subvol=<name> (subvolid= only, the top level, or nested names are refused).";
        }
        {
          assertion = targetValid -> overlapping == [];
          message = "roles.impermanent.wipe: the root subvolume (or one nested under it) is also mounted at ${toString overlapping}; wiping would destroy it.";
        }
      ];

      boot.initrd.systemd.services.rollback-root = {
        description = "Rollback btrfs root subvolume";
        wantedBy = ["initrd.target"];
        requires = [deviceUnit];
        after = [deviceUnit];
        before = ["sysroot.mount"];
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        script = ''
          mkdir -p /tmp
          mount -t btrfs ${dev} /tmp

          if [[ -e /tmp/${sv} ]]; then
              mkdir -p /tmp/old_roots
              timestamp=$(date --date="@$(stat -c %Y /tmp/${sv})" "+%Y-%m-%-d_%H:%M:%S")
              mv /tmp/${sv} "/tmp/old_roots/$timestamp"
          fi

          delete_subvolume_recursively() {
              IFS=$'\n'
              for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
                  delete_subvolume_recursively "/tmp/$i"
              done
              btrfs subvolume delete "$1"
          }

          for i in $(find /tmp/old_roots/ -maxdepth 1 -mtime +${toString cfg.wipe.keepDays}); do
              delete_subvolume_recursively "$i"
          done

          btrfs subvolume create /tmp/${sv}
          umount /tmp
        '';
      };
    })
  ]);
}
