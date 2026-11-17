# Impermanence and root wipe

With impermanence, only what you list survives a reboot. Machines stay
reproducible and state stops piling up. OmniNix gives you two pieces:

1. **`omninix.persistence`**: any host, role, user or profile lists what it
   needs to keep.
2. **`roles.impermanent`**, shipped with OmniNix: keeps those lists in
   `/persist`, and can wipe the btrfs root on every boot.

## Listing what to keep

```nix
# in a host or role: system paths
omninix.persistence.directories = ["/var/lib/docker"];
omninix.persistence.files = ["/etc/adjtime"];

# in a user or profile: paths in the home
omninix.persistence.directories = [".ssh" "Documents"];
omninix.persistence.files = [".zsh_history"];
```

On a host with the role on, system paths are kept in `/persist`, and each
user's in `/persist/home/<user>`. Everywhere else the lists do nothing, so
shared profiles can always declare them.

## Turning on the role

You need the [impermanence](https://github.com/nix-community/impermanence)
module on your hosts, the role, and a `/persist` filesystem:

```nix
# flake.nix
inputs.impermanence.url = "github:nix-community/impermanence";

omninix = {
  extraRoles = {inherit (omninix.roles) impermanent;};
  extraNixosModules.impermanence = inputs.impermanence.nixosModules.impermanence;
};
```

```nix
# hosts/laptop/default.nix
roles.impermanent.enable = true;
```

impermanence's module does nothing until a host uses it, so importing it
everywhere is fine. It must be imported only **once**; if a host enables the
role without it, the build says what to import.

The role keeps:

- `/var/log`, `/var/lib/nixos` (stable user and group IDs), `/etc/machine-id`;
- `/var/lib/bluetooth` with Bluetooth on, NetworkManager's connections with
  NetworkManager on, `/var/lib/systemd/coredump` with
  `roles.impermanent.persistCoredumps = true`;
- everything in `omninix.persistence`.

It marks `/persist` as needed at boot, and keeps the **SSH host keys in
`/persist/etc/ssh`** itself: sshd reads them there, and so does sops-nix, so
secrets decrypt early in boot.

## Wiping the root on every boot

```nix
roles.impermanent.wipe = {
  enable = true;
  acknowledgeDataLoss = true; # required
  # keepDays = 30;            # how long old roots are kept
  # device = "/dev/…";        # default: fileSystems."/".device
};
```

On every boot, before the root is mounted, the old root subvolume moves to
`old_roots/<timestamp>` and a fresh, empty one takes its place. Old roots
older than `keepDays` are deleted.

It needs `/` on **btrfs**, mounted with `subvol=<name>`, and a systemd initrd
(`boot.initrd.systemd.enable = true` on NixOS 26.05; from 26.11 it's the only
kind). The build checks all of it, and refuses:

- a root mounted by `subvolid=` only, the btrfs top level, or a nested name;
- any other mount (like `/home`) that uses the root subvolume or one under it;
- a `device` that isn't a `/dev` path.

On the machine:

- **There's always a root.** The new root is created before anything is
  deleted; if that fails, the old one is put back and the machine boots as
  before.
- **Only old roots are deleted,** and only btrfs subvolumes in `old_roots`.
- **Failures show.** If the wipe didn't run, the machine still boots, and
  `rollback-root-check` appears in `systemctl --failed`.

## Rolling it out on a running machine ⚠️

The role moves the SSH host keys to `/persist/etc/ssh`, and sops decrypts your
password with them: if they aren't there, you can't log in with a password.
The wipe then deletes everything not in `/persist` on the next boot.

1. Copy the live state into `/persist` **before** enabling the role:

   ```bash
   sudo mkdir -p /persist/etc/ssh
   sudo cp -a /etc/ssh/ssh_host_* /persist/etc/ssh/
   sudo cp /etc/machine-id /persist/etc/
   ```

   Plus anything else you want to keep.
2. Enable the role **without** `wipe`, then `nixos-rebuild boot` and reboot.
3. Check that you can log in, and that secrets decrypted:
   `sudo ls /run/secrets-for-users`.
4. Only now enable `wipe`, and reboot with a live USB stick at hand.

## Recovering from a live USB

If a machine won't boot after a wipe:

```bash
sudo mount -o subvolid=5 /dev/<root-partition> /mnt
ls /mnt/old_roots                     # newest last
sudo mv /mnt/root /mnt/root.broken    # the empty root, if there is one
sudo mv /mnt/old_roots/<newest> /mnt/root
sudo umount /mnt && reboot
```

Old roots are kept for `keepDays`, so you have that long to recover anything
from them.
