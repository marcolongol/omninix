# Passwords and secrets

OmniNix won't build a host where an active user has no password. The goal is
simple: you can't deploy a machine nobody can log in to, or one where anyone can.

Any NixOS password mechanism counts. Pick one:

## Option 1: sops-nix (built in)

Add the `sops-nix` input and point OmniNix at your secrets directory:

```nix
# flake.nix
inputs.sops-nix = {
  url = "github:Mic92/sops-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};

omninix.secretsPath = ./secrets;
```

OmniNix then wires sops for you:

| File | Used for |
|---|---|
| `secrets/users/<user>.yaml`, key `hashed-password` | that user's login password, decrypted before users are created |
| `secrets/<host>.yaml` | the host's default sops file (only if it exists) |
| anything else, e.g. `secrets/shared.yaml` | whatever you point `sopsFile` at |

The host decrypts with its SSH host key (`/etc/ssh/ssh_host_ed25519_key`, or
`/persist/etc/ssh/...` when [impermanence](impermanence.md) is on).

Create a user password:

```bash
mkpasswd -m sha-512   # copy the hash
sops secrets/users/alice.yaml   # add:  hashed-password: <hash>
```

Declare other secrets as usual:

```nix
sops.secrets.api-key = {};                                        # from secrets/<host>.yaml
sops.secrets.db-password.sopsFile = ./secrets/shared.yaml;
```

Without `secretsPath` (or without the `sops-nix` input), OmniNix doesn't touch
anything secrets-related.

## Option 2: bring your own

The password check only asks that each active user has *some* password. Set it
in a host or role however you like:

```nix
users.users.alice.hashedPasswordFile = "/run/agenix/alice"; # agenix, systemd-creds, ...
# or
users.users.alice.hashedPassword = "$6$..."; # from `mkpasswd -m sha-512`
```

Empty passwords don't count: an empty or empty-hashed password lets anyone log
in, so the build still fails.

To use agenix or another tool, import its module like any
[third-party module](third-party-modules.md).

## First install: building without a password

Before your secrets exist, you can opt out once:

```nix
# hosts/laptop/default.nix
omninix.allowInsecureBootstrap = true;
```

⚠️ This allows **passwordless login**. Every build warns about it. Set a password
and remove the line before the machine is reachable by anyone else.

## Users and groups

- Users enabled with `omninix.hostUsers.<name>.enable` get **no** privileged
  groups by default.
- Grant them per user: `omninix.hostUsers.alice.extraGroups = ["wheel"];`
- Or for every user on a host: `omninix.defaultUserGroups = ["networkmanager"];`
- `users.mutableUsers` defaults to `true`, so `passwd` works while you bootstrap.
  Set it to `false` on a host for fully declarative users.
