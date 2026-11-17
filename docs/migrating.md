# Migrating an existing flake

Move a flake with `nixosConfigurations` (and maybe Home Manager) to OmniNix
one host at a time, proving at each step that the machine is the one you had.

## 1. Record what you have

Before changing anything, note each host's derivation. Nothing is built:

```bash
nix eval --raw .#nixosConfigurations.laptop.config.system.build.toplevel.drvPath > before-laptop
```

Keep a copy of the flake as it is (a git worktree works well) to compare
against later.

## 2. Add OmniNix next to your hosts

If your flake isn't on flake-parts yet, wrap your outputs in its `flake`
attribute first. Hosts you haven't moved stay where they are; both sets of
`nixosConfigurations` merge.

```nix
inputs.omninix = {
  url = "github:marcolongol/omninix";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.flake-parts.follows = "flake-parts";
};

outputs = {flake-parts, omninix, nixpkgs, ...} @ inputs:
  flake-parts.lib.mkFlake {inherit inputs;} {
    imports = [omninix.flakeModules.default];
    systems = ["x86_64-linux"];

    omninix = {
      hostsDir = ./hosts;
      usersDir = ./users;
    };

    # Not moved yet.
    flake.nixosConfigurations.server = nixpkgs.lib.nixosSystem { /* as before */ };
  };
```

Hosts are built with *your* `nixpkgs`, `home-manager` and `sops-nix`, so no
versions change.

## 3. Move one host

```
hosts/laptop/
├── default.nix                  was configuration.nix
└── hardware-configuration.nix
```

In `default.nix`:

- **Drop `networking.hostName`** if it matches the directory name: OmniNix
  sets it from the name (yours wins if it differs).
- **Drop the Home Manager and sops-nix module imports.** OmniNix imports them
  when the inputs exist.
- **Replace your user declaration** with `omninix.hostUsers`, keeping the
  password:

  ```nix
  # before
  users.users.alice = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    hashedPasswordFile = config.sops.secrets.alice-password.path;
  };

  # after
  omninix.hostUsers.alice = {
    enable = true;
    extraGroups = ["wheel"];
  };
  users.users.alice.hashedPasswordFile = config.sops.secrets.alice-password.path;
  ```

  The last line keeps your existing secret. Move the hash to
  `secrets/users/alice.yaml` (key `hashed-password`) and OmniNix wires it
  itself ([Passwords and secrets](secrets.md)).

Remove the host from your own `flake.nixosConfigurations`.

## 4. Move Home Manager users

Move what you had under `home-manager.users.alice` into `users/alice.nix`, a
plain Home Manager module, and delete it from the host. `omninix.hostUsers.alice`
now brings it in, and it also builds on its own as `homeConfigurations.alice`.

OmniNix sets `home-manager.useGlobalPkgs` and `useUserPackages` to `true`;
remove yours if they differ. It doesn't set `backupFileExtension`: if you
relied on Home Manager renaming clashing files to `.bak`, set
`home-manager.backupFileExtension = "bak";` in a module.

## 5. Compare

The same derivation path means the same system:

```bash
nix eval --raw .#nixosConfigurations.laptop.config.system.build.toplevel.drvPath > after-laptop
diff before-laptop after-laptop && echo identical
```

If they differ, `nix-diff` shows what, without building anything:

```bash
nix run nixpkgs#nix-diff -- "$(cat before-laptop)" "$(cat after-laptop)"
```

Expected differences:

- `users.mutableUsers` becomes `false`: accounts and passwords come from the
  config alone. Set it to `true` on the host to keep managing them by hand.
- Users get only the groups you list in `extraGroups`.
- Unfree packages need `omninix.allowUnfree = true;`, or
  `nixpkgs.config.allowUnfree = true;` on the host.
- Lists may come out in a different order (packages, kernel parameters),
  because modules are imported in a different order. Harmless unless two
  entries compete, like two `loglevel=` kernel parameters.

Anything else is a real change: find it before you switch. If your config
derives something from the flake itself, like a wallpaper picked from
`inputs.self.lastModified`, compare two copies with the same file times, or
that will differ too.

## 6. Split out roles and profiles

Once a host is moved and the comparison is clean, pull features out of it as
you go. A block like

```nix
virtualisation.docker.enable = true;
users.users.alice.extraGroups = ["docker"];
```

becomes `roles/docker.nix` with an `enable` option
([Roles](pieces.md#roles)), and the host turns it on with
`roles.docker.enable = true;` and `extraGroups = ["docker"];`. Home Manager
features become profiles the same way. Compare after each step: moving code
into a role shouldn't change the system.
