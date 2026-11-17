# Getting started

From nothing to a machine running your fleet.

## 1. Create the fleet

```bash
mkdir my-fleet && cd my-fleet
nix flake init -t github:marcolongol/omninix
git init && git add -A   # flakes only see files git knows about
```

You get:

```
flake.nix                                  inputs and the omninix block
hosts/example-host/default.nix             a machine
hosts/example-host/hardware-configuration.nix
users/example-user.nix                     a person's Home Manager config
roles/common.nix                           a role every host turns on
profiles/common.nix                        a profile every user turns on
secrets/                                   sops setup, with a README
```

## 2. Make it your machine

On the machine, rename the host and replace the placeholder hardware config:

```bash
git mv hosts/example-host hosts/laptop
nixos-generate-config --show-hardware-config > hosts/laptop/hardware-configuration.nix
```

The directory name is the host's name: it becomes
`nixosConfigurations.laptop`, and the hostname `laptop`.

## 3. Make it yours

Rename the user to your username, and set your git name and email in it:

```bash
git mv users/example-user.nix users/alice.nix
```

Then enable yourself on the host, in `hosts/laptop/default.nix`:

```nix
omninix.hostUsers.alice = {
  enable = true;
  extraGroups = ["wheel"]; # sudo
};
```

## 4. Build and switch

```bash
sudo nixos-rebuild switch --flake .#laptop
```

The template builds with `omninix.allowInsecureBootstrap = true;`, which lets a
user without a password log in **without one**. Every build warns about it.

## 5. Set a password

Follow `secrets/README.md` (or [Passwords and secrets](secrets.md)): make an
age key, encrypt a password hash into `secrets/users/alice.yaml`, then delete
`allowInsecureBootstrap` from the host and switch again. From now on, a host
where an active user has no password doesn't build.

## Next

- Turn on more roles, write your own: [Hosts, users, roles and profiles](pieces.md).
- Use the same user on a machine without NixOS:
  `home-manager switch --flake .#alice`.
- Add more pieces, each in one command (the directory is the piece's name):

  ```bash
  nix flake new -t github:marcolongol/omninix#host        hosts/server
  nix flake new -t github:marcolongol/omninix#darwin-host hosts/macbook
  nix flake new -t github:marcolongol/omninix#user        users/bob
  nix flake new -t github:marcolongol/omninix#role        roles/webserver
  nix flake new -t github:marcolongol/omninix#profile     profiles/gaming
  ```
