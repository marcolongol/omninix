# Passwords and secrets

OmniNix won't build a NixOS host where an active user has no password: you
can't deploy a machine nobody can log in to, or one anyone can. Any NixOS
password setting counts (`hashedPasswordFile`, `hashedPassword`,
`initialHashedPassword`, `initialPassword`, `password`), as long as it isn't
empty.

Accounts come from the config alone (`users.mutableUsers` defaults to
`false`), so the password in your config is the one that works: `passwd`
changes don't survive a switch.

## sops-nix, by convention

Add the input and point OmniNix at a directory:

```nix
inputs.sops-nix = {
  url = "github:Mic92/sops-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};

omninix.secretsPath = ./secrets;
```

OmniNix wires these files, each only if it exists:

| File | Becomes |
|---|---|
| `users/<user>.yaml`, key `hashed-password` | that user's password, decrypted before accounts are created |
| `users/<user>.yaml` | also the user's default sops file in Home Manager |
| `<host>.yaml` | the host's default sops file |
| `shared.yaml` | secrets every host gets: each top-level key is `sops.secrets.<key>` |

Any other file works as usual, with `sops.secrets.<name>.sopsFile`.

### A user's password

```bash
mkpasswd -m yescrypt               # prints a hash
sops secrets/users/alice.yaml      # add:  hashed-password: <the hash>
```

### A host's own secrets

```nix
sops.secrets.cloudflared-credentials = {};   # read from secrets/<host>.yaml
```

### Secrets every host uses

Every key at the top of `shared.yaml` becomes a secret on every host, with
nothing to declare. Add settings per host as usual:

```nix
sops.secrets.wifi-psk.owner = "wpa_supplicant";
```

Because every host declares them, **every host must be able to decrypt
`shared.yaml`**: list all hosts' keys in its `.sops.yaml` rule. A host that
can't fails to activate. Only top-level keys count, so keep each shared secret
a plain value. `config.omninix.secrets.shared` is the file's path, if you need
it.

### Keys

Hosts decrypt with their SSH host key, as sops-nix does by default: the
ed25519 key in `services.openssh.hostKeys`. That needs sshd enabled (or
`services.openssh.generateHostKeys = true;`). To get a host's age recipient
for `.sops.yaml`:

```bash
nix shell nixpkgs#ssh-to-age -c sh -c 'ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub'
```

The template's `secrets/.sops.yaml` and `secrets/README.md` walk through it.

Homes decrypt with the user's own key, which you set yourself (for example
`sops.age.keyFile`). sops-nix's Home Manager module is in every home whenever
the input exists.

## Your own way

Without `secretsPath`, set passwords however you like, in a host or role:

```nix
users.users.alice.hashedPasswordFile = "/run/agenix/alice"; # agenix, systemd-creds, ...
users.users.alice.hashedPassword = "$y$...";                # or a plain hash
```

To use agenix or another tool, import its module like any
[third-party module](third-party-modules.md).

## A first install

Before a password exists, a host can build anyway:

```nix
omninix.allowInsecureBootstrap = true;
```

This allows **passwordless login** while a user has no password, and every
build warns about it. Set the password and delete the line before the machine
is reachable by anyone else.
