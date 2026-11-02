# Impermanence and root wipe

"Impermanence" means only what you list survives a reboot; everything else is
thrown away. It keeps machines reproducible and stops state from piling up.

OmniNix gives you two pieces:

1. **`omninix.persistence.*`**: any host, role, user or profile lists what it
   needs to keep.
2. **`roles.impermanent`** (shipped with OmniNix): turns those lists into a
   `/persist` store, and can optionally wipe the btrfs root on every boot.

## Declaring what to keep

```nix
# in a host or role (system paths)
omninix.persistence.directories = ["/var/lib/docker"];

# in a user or profile (paths relative to the home directory)
omninix.persistence.directories = [".ssh" ".config/1Password"];
omninix.persistence.files = [".kube/config"];
```

On a host with the impermanent role on, system paths land in `/persist` and each
user's paths in `/persist/home/<user>`. Everywhere else these lists do nothing,
so it's safe to declare them in shared profiles.

## Turning on `roles.impermanent`

You need:

- the [impermanence](https://github.com/nix-community/impermanence) input, with
  its NixOS module imported **once** (a second import is a hard error);
- a `/persist` filesystem;
- the role, via `omninix.extraRoles = omninix.roles;` (the template does this).

```nix
# hosts/laptop/default.nix
{inputs, ...}: {
  imports = [inputs.impermanence.nixosModules.impermanence];
  roles.impermanent.enable = true;
}
```

The role keeps:

- `/var/log`, `/var/lib/nixos`, `/etc/ssh`, `/etc/machine-id`;
- `/var/lib/bluetooth` when Bluetooth is on, NetworkManager connections when
  NetworkManager is on;
- `/var/lib/systemd/coredump` with `roles.impermanent.persistCoredumps = true`;
- everything in `omninix.persistence.*`.

It also marks `/persist` as needed at boot.

## Wiping the root on every boot

```nix
roles.impermanent.wipe = {
  enable = true;
  acknowledgeDataLoss = true; # required, see below
  # keepDays = 30;            # how long old roots are kept
  # device = "...";           # default: fileSystems."/".device
};
```

On every boot, before the root is mounted, the old root subvolume is moved to
`old_roots/<timestamp>` and a fresh empty one takes its place. Archived roots
older than `keepDays` are deleted.

Requirements: `/` on **btrfs**, mounted with `subvol=<name>`, and
`boot.initrd.systemd.enable = true`.

### Built-in safety

- **The wipe target isn't configurable.** It's read from `fileSystems."/"`, and
  the build refuses roots mounted by `subvolid=` only, the btrfs top level,
  nested names, and any other mount (like `/persist` or `/nix`) that uses the
  root subvolume.
- **The disk always keeps a root.** The new root is created before anything is
  deleted. If that fails, the old root is put back and the machine boots as
  before.
- **Only archived roots are ever deleted.** Anything in `old_roots` that isn't a
  btrfs subvolume is left alone.
- **Failures are visible.** If the wipe didn't run or failed, the machine still
  boots, and `rollback-root-check` shows up in `systemctl --failed`.

## ⚠️ Rolling it out on an existing machine

Turning on the wipe deletes everything not in `/persist` **on the next boot**.
That includes the SSH host keys. sops decrypts with those keys, so without them
your password secret can't be decrypted and you're locked out.

Do it in steps:

1. Enable `roles.impermanent` **without** `wipe`, and switch.
2. Copy the live state into `/persist`:
   ```bash
   sudo mkdir -p /persist/etc/ssh
   sudo cp -a /etc/ssh/ssh_host_* /persist/etc/ssh/
   sudo cp /etc/machine-id /persist/etc/
   ```
   Plus anything else you want to keep.
3. Reboot. Check that you can log in and that secrets still decrypt.
4. Only now enable `wipe` (with `acknowledgeDataLoss = true`), switch, and reboot
   with a live USB stick at hand.

## Recovering from a live USB

If a machine won't boot after a wipe:

```bash
sudo mount -o subvolid=5 /dev/<root-partition> /mnt
ls /mnt/old_roots                              # newest archive last
sudo mv /mnt/root /mnt/root.broken             # if an empty root exists
sudo mv /mnt/old_roots/<newest> /mnt/root
sudo umount /mnt && reboot
```

Archives are kept for `keepDays` (30 by default), so you have that long to
recover anything from a previous root.
