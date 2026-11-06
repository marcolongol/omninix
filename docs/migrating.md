# Migrating a hand-rolled config

This moves an existing flake with `nixosConfigurations` (and maybe Home
Manager) to OmniNix one host at a time, checking at each step that the
machine you build is the one you had.

## 1. Record what you have

Before changing anything, build each host as it is now:

```bash
nix build .#nixosConfigurations.laptop.config.system.build.toplevel -o before-laptop
```

You'll compare against this at the end.

## 2. Add OmniNix next to your hosts

Add the input and the flake-parts module. If your flake isn't on flake-parts
yet, wrap your existing outputs in `flake` first. Hosts you haven't moved stay
where they are; the two sets of `nixosConfigurations` merge.

```nix
inputs.omninix = {
  url = "github:marcolongol/omninix";
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

OmniNix builds hosts with *your* `nixpkgs`, `home-manager` and `sops-nix`
inputs, so the versions don't change.

## 3. Move one host

Move `configuration.nix` and its hardware config to `hosts/laptop/`:

```
hosts/laptop/
├── default.nix               # was configuration.nix
└── hardware-configuration.nix
```

Then, in `default.nix`:

- **Keep `networking.hostName`.** OmniNix doesn't set it from the directory
  name.
- **Drop the Home Manager and sops-nix module imports.** OmniNix imports
  `home-manager.nixosModules.home-manager` and `sops-nix.nixosModules.sops`
  itself when those inputs exist.
- **Replace your user declaration** with `omninix.hostUsers`, keeping any
  password settings:

  ```nix
  # before
  users.users.alice = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager"];
    hashedPasswordFile = config.sops.secrets.alice-password.path;
  };

  # after
  omninix.hostUsers.alice = {
    enable = true;
    extraGroups = ["wheel" "networkmanager"];
  };
  users.users.alice.hashedPasswordFile = config.sops.secrets.alice-password.path;
  ```

  If an active user ends up with no password, the build fails and says so.
  That's the point: fix it rather than reaching for `allowInsecureBootstrap`.

Remove the host from your own `flake.nixosConfigurations`; it now comes from
`hostsDir`.

## 4. Move Home Manager users

Move what you had under `home-manager.users.alice` into `users/alice/default.nix`
(a plain Home Manager module), and delete the `home-manager.users.alice` line
from the host. The user is wired in by `omninix.hostUsers.alice.enable`, and
the same file now also builds standalone as `homeConfigurations.alice`.

OmniNix sets `home-manager.useGlobalPkgs = true` and `useUserPackages = true`,
and defaults `backupFileExtension` to `"bak"`. If you had different values for
the first two, the build stops with a conflict: remove yours. Your packages
and overlays apply to users through `useGlobalPkgs`.

## 5. Compare

```bash
nix build .#nixosConfigurations.laptop.config.system.build.toplevel -o after-laptop
nix store diff-closures ./before-laptop ./after-laptop
```

An empty diff means you moved the host without changing it. Expected
differences:

- `users.mutableUsers` defaults to `true` (unless you set it).
- Users get only the groups you list in `extraGroups`, nothing more.
- Unfree packages need `omninix.allowUnfree = true;` (fleet-wide) or
  `nixpkgs.config.allowUnfree = true;` on the host.

Anything else is a real change: find it before you switch.

## 6. Split out roles and profiles

Once the host is moved and the diff is clean, pull features out of the host
file as you go. A block like

```nix
virtualisation.docker.enable = true;
users.users.alice.extraGroups = ["docker"];
```

becomes `roles/docker.nix` with an `enable` option (see the
[README](../README.md#roles)), and the host turns it on with
`roles.docker.enable = true;` and `extraGroups = ["docker"];`. Settings every
host should get unconditionally go in `nixosModulesDir` instead. Home Manager
features become profiles the same way.

Re-run the diff after each step. Moving code into a role shouldn't change the
closure.

## Next

- [Passwords and secrets](secrets.md): sops-nix with the `secretsPath`
  convention, so passwords stop living in host files.
- [Deploying](deployment.md): pushing hosts over SSH.
