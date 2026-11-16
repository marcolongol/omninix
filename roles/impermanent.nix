# roles.impermanent: an ephemeral root with a persistent /persist, and
# optionally a btrfs root wiped on every boot.
#
# What survives a reboot is only what's listed: a few system paths this role
# knows about, plus every host's and user's omninix.persistence.
#
# Needs impermanence's NixOS module, imported once by the flake (e.g.
# omninix.extraNixosModules.impermanence). The role never imports it itself:
# the module is a function, so a second import would be fatal.
{
  config,
  lib,
  options,
  utils,
  ...
}: let
  cfg = config.roles.impermanent;
  hasPersistence = options ? environment.persistence;
  root = config.fileSystems."/" or {};

  # --- the wipe target, from fileSystems."/" only ----------------------------

  # nixpkgs 26.11+ dropped the scripted initrd: its enable option is then a
  # hidden stub, and systemd initrd is the only kind left.
  systemdInitrd = !(options.boot.initrd.systemd.enable.visible or true) || config.boot.initrd.systemd.enable;

  subvolsOf = fs: map (lib.removePrefix "subvol=") (lib.filter (lib.hasPrefix "subvol=") (fs.options or []));
  trimSlashes = s: lib.removeSuffix "/" (lib.removePrefix "/" s);

  # The root must mount exactly one top-level subvolume by name. That's what
  # gets rolled back; it's never configurable, so it can't point elsewhere.
  rootSubvols = subvolsOf root;
  target = trimSlashes (lib.findFirst (_: true) "" rootSubvols);
  targetValid =
    lib.length rootSubvols
    == 1
    && builtins.match "[^/]+" target != null
    && !(lib.elem target ["." ".."]);

  # Other mounts of the target subvolume, or of one nested under it: wiping
  # would destroy them.
  overlapping = lib.attrNames (lib.filterAttrs (mountPoint: fs:
    mountPoint
    != "/"
    && lib.any (s: let
      t = trimSlashes s;
    in
      t == target || lib.hasPrefix "${target}/" t) (subvolsOf fs))
  config.fileSystems);

  # --- shell values for the wipe script ---------------------------------------

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
    enable = lib.mkEnableOption "an ephemeral root with a persistent /persist";
    persistCoredumps = lib.mkEnableOption "keeping /var/lib/systemd/coredump";
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

      # Host keys live in /persist itself rather than a bind mount over
      # /etc/ssh: sshd reads them there, and sops-nix's default key paths
      # follow hostKeys, so secrets decrypt before any bind mount exists.
      services.openssh.hostKeys = lib.mkDefault [
        {
          path = "/persist/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
        {
          path = "/persist/etc/ssh/ssh_host_rsa_key";
          type = "rsa";
          bits = 4096;
        }
      ];
    }

    # Only where impermanence's module is imported: setting an undeclared
    # option is an error, even under mkIf. The requirement above explains it.
    (lib.optionalAttrs hasPersistence {
      environment.persistence."/persist" = {
        enable = true;
        hideMounts = true;
        directories =
          [
            "/var/log"
            # User and group IDs, so they stay stable across boots.
            "/var/lib/nixos"
          ]
          ++ lib.optional config.hardware.bluetooth.enable "/var/lib/bluetooth"
          ++ lib.optional cfg.persistCoredumps "/var/lib/systemd/coredump"
          ++ lib.optional config.networking.networkmanager.enable "/etc/NetworkManager/system-connections"
          ++ config.omninix.persistence.directories;
        files = ["/etc/machine-id"] ++ config.omninix.persistence.files;
      };
    })

    (lib.mkIf cfg.wipe.enable {
      assertions = [
        {
          assertion = cfg.wipe.acknowledgeDataLoss;
          message = "OmniNix: roles.impermanent.wipe deletes everything outside /persist on every boot. Seed /persist (at least /persist/etc/ssh) first, then set roles.impermanent.wipe.acknowledgeDataLoss = true.";
        }
        {
          assertion = (root.fsType or null) == "btrfs";
          message = "OmniNix: roles.impermanent.wipe: fileSystems.\"/\" must be btrfs.";
        }
        {
          assertion = systemdInitrd;
          message = "OmniNix: roles.impermanent.wipe: requires boot.initrd.systemd.enable.";
        }
        {
          assertion = cfg.wipe.device != null && lib.hasPrefix "/dev/" cfg.wipe.device;
          message = "OmniNix: roles.impermanent.wipe: wipe.device must be a /dev path (fileSystems.\"/\".device is unset).";
        }
        {
          assertion = targetValid;
          message = "OmniNix: roles.impermanent.wipe: fileSystems.\"/\" must mount exactly one top-level subvolume via subvol=<name> (subvolid= only, the top level, or nested names are refused).";
        }
        {
          assertion = targetValid -> overlapping == [];
          message = "OmniNix: roles.impermanent.wipe: the root subvolume (or one nested under it) is also mounted at ${toString overlapping}; wiping would destroy it.";
        }
      ];

      # Invariant: a root subvolume exists whenever this unit exits. Any
      # failure boots the previous root, and rollback-root-check reports it.
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

          # Move the old root aside (named by its last change), then create a
          # fresh one. If creating fails, put the old one back.
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

      # Stage 2: surface a skipped or failed wipe in `systemctl --failed`.
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
