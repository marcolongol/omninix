# Secrets

OmniNix reads two kinds of file here, both encrypted with sops:

- `users/<user>.yaml`, key `hashed-password`: that user's login password.
- `<host>.yaml`: the host's default sops file, for `sops.secrets.<name> = {};`.
- `shared.yaml`: secrets every host uses. Point a secret at it with
  `sops.secrets.<name>.sopsFile = config.omninix.secrets.shared;`.

To give example-user a password:

1. Make yourself a key, and put its public half in `.sops.yaml` as `admin`:
   `age-keygen -o ~/.config/sops/age/keys.txt`
2. On the host, get its key from its SSH host key, and put it in `.sops.yaml`
   as `example-host`:
   `nix shell nixpkgs#ssh-to-age -c sh -c 'ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub'`
3. Hash a password and encrypt it:
   `echo "hashed-password: $(mkpasswd -m yescrypt)" > users/example-user.yaml`
   `sops encrypt -i users/example-user.yaml`
4. Delete `omninix.allowInsecureBootstrap` from the host.
