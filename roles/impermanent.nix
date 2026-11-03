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
  mnt = "/run/rollback-root";
  failed = "/run/rollback-root.failed";
  dev = lib.escapeShellArg cfg.wipe.device;
  deviceUnit = d: "${utils.escapeSystemdPath d}.device";
  rootDevice = root.device or null;
  # A wipe.device override must resolve to the same block device as /.
  checkRootDevice = rootDevice != null && rootDevice != cfg.wipe.device;
  waitFor = [(deviceUnit cfg.wipe.device)] ++ lib.optional checkRootDevice (deviceUnit rootDevice);
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
      omninix.requirements = [
        {
          by = "roles.impermanent";
          option = "environment.persistence";
          module = "impermanence's NixOS module, once (e.g. omninix.extraNixosModules.impermanence = inputs.impermanence.nixosModules.impermanence)";
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
          assertion = cfg.wipe.device != null && lib.hasPrefix "/dev/" cfg.wipe.device;
          message = "roles.impermanent.wipe: wipe.device must be a /dev path (fileSystems.\"/\".device is unset).";
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

      # Invariant: a root subvolume exists whenever this unit exits. Any failure
      # boots the previous root and is reported by rollback-root-check.
      boot.initrd.systemd.services.rollback-root = {
        description = "Rollback btrfs root subvolume";
        wantedBy = ["initrd.target"];
        requires = waitFor;
        after = waitFor ++ ["systemd-hibernate-resume.service"];
        before = ["sysroot.mount"];
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        script = ''
          trap 'touch ${failed}' ERR
          ${lib.optionalString checkRootDevice ''
            if [[ "$(readlink -f ${dev})" != "$(readlink -f ${lib.escapeShellArg rootDevice})" ]]; then
                echo "rollback-root: ${cfg.wipe.device} is not the root device; not wiping" >&2
                touch ${failed}; exit 1
            fi
          ''}
          mkdir -p ${mnt}
          mount -t btrfs -o subvolid=5 ${dev} ${mnt}

          if [[ -e ${mnt}/${sv} ]]; then
              mkdir -p ${mnt}/old_roots
              timestamp=$(date --date="@$(stat -c %Y ${mnt}/${sv})" "+%Y-%m-%d_%H:%M:%S")
              dst="${mnt}/old_roots/$timestamp"; n=0
              while [[ -e "$dst" ]]; do n=$((n + 1)); dst="${mnt}/old_roots/$timestamp.$n"; done
              mv -T ${mnt}/${sv} "$dst"
              btrfs subvolume create ${mnt}/${sv} || { mv -T "$dst" ${mnt}/${sv}; touch ${failed}; umount ${mnt}; exit 1; }
          else
              btrfs subvolume create ${mnt}/${sv}
          fi

          delete_subvolume_recursively() {
              local IFS=$'\n' i
              for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
                  delete_subvolume_recursively "${mnt}/$i"
              done
              btrfs subvolume delete "$1"
          }

          # Prune last and never fatally; only real subvolumes inside old_roots.
          while IFS= read -r -d "" i; do
              if btrfs subvolume show "$i" >/dev/null 2>&1; then
                  delete_subvolume_recursively "$i" || echo "rollback-root: could not prune $i" >&2
              fi
          done < <(find ${mnt}/old_roots -mindepth 1 -maxdepth 1 -mtime +${toString cfg.wipe.keepDays} -print0 2>/dev/null)

          umount ${mnt}
        '';
      };

      # Stage 2: surface a skipped or failed wipe in systemctl --failed.
      systemd.services.rollback-root-check = {
        description = "Report a failed btrfs root rollback";
        wantedBy = ["multi-user.target"];
        unitConfig.ConditionPathExists = failed;
        serviceConfig.Type = "oneshot";
        script = ''
          echo "rollback-root did not complete in the initrd; this boot uses the previous root. Check: journalctl -b -u rollback-root" >&2
          exit 1
        '';
      };
    })
  ]);
}
