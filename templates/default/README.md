# OmniNix Configuration

This is an OmniNix-based NixOS configuration.

OmniNix discovers `hosts/`, `roles/`, `users/`, and `profiles/` automatically and
builds `nixosConfigurations.<host>` plus standalone `homeConfigurations.<user>`.
Roles and profiles are **enable-based**: each one declares its own
`roles.<name>.enable` / `profiles.<name>.enable` option, and you turn it on per
host / per user.

## Getting Started

1. **Update hardware configuration:**
   ```bash
   sudo nixos-generate-config --show-hardware-config > hosts/example-host/hardware-config.nix
   ```

2. **Rename the example host:**
   ```bash
   mv hosts/example-host hosts/your-hostname
   ```
   Then set `networking.hostName = "your-hostname";` in
   `hosts/your-hostname/default.nix`.

3. **Rename the example user:**
   ```bash
   mv users/example-user users/your-username
   ```
   Update `users/your-username/default.nix` — including your **git name/email**
   under `programs.git.settings.user`.

4. **Enable the user on the host.** In `hosts/your-hostname/default.nix`:
   ```nix
   omninix.hostUsers = {
     your-username = {
       enable = true;
       extraGroups = [ "wheel" ]; # sudo; add "docker" etc. as needed
     };
   };
   ```
   Privileged groups are opt-in. `wheel` (sudo) and `docker` (root-equivalent)
   are **not** granted automatically. Use per-user `extraGroups`, or set groups
   for every user with `omninix.defaultUserGroups = [ ... ];`.

5. **Configure passwords (required).** OmniNix **fails the build** if an active
   user has no password — so you can't accidentally ship a passwordless system.

   **Option A — sops-nix (recommended):**
   ```bash
   mkdir -p secrets/users
   # Put a hashed password (key: hashed-password) in
   # secrets/users/your-username.yaml, encrypted with sops, then uncomment
   # secretsPath in flake.nix.
   ```

   **Option B — set a password directly** in `hosts/your-hostname/default.nix`:
   ```nix
   users.users.your-username.hashedPassword = "..."; # mkpasswd -m sha-512
   ```

   **Bootstrap escape hatch:** to build *before* you've set a password (initial
   install only), the example host sets `omninix.allowInsecureBootstrap = true;`,
   which permits **passwordless login**. Remove it once a password is set —
   leaving it on is insecure.

6. **Build and deploy:**
   ```bash
   sudo nixos-rebuild switch --flake .#your-hostname
   ```

## Directory Structure

- `hosts/` — host-specific configurations (one machine each)
- `roles/` — system-level capabilities (enable-based)
- `users/` — user configurations (also usable as standalone home configs)
- `profiles/` — user environment patterns (enable-based)
- `packages/` — auto-discovered packages → `packages.<system>.<name>`
- `secrets/` — encrypted sops secrets (git-ignored; never commit plaintext)

## Adding Components

### Add a new role

Create `roles/my-role.nix` — declare an enable option and gate config on it:
```nix
{ config, lib, pkgs, ... }:
{
  options.roles.my-role.enable = lib.mkEnableOption "my role";

  config = lib.mkIf config.roles.my-role.enable {
    # ... system configuration ...
  };
}
```
Enable it on a host: `roles.my-role.enable = true;`

### Add a role with a home side

When a role has a user-facing half (a desktop needs both the compositor *and*
each user's terminal/browser/bar config), ship both from the role instead of
pairing it with a profile. See `roles/desktop/`:
```nix
# roles/desktop/default.nix
config = lib.mkIf config.roles.desktop.enable {
  programs.sway.enable = true;
  home-manager.sharedModules = [ ./home.nix ];  # applied to every user on the host
};
```
`home.nix` is a plain Home Manager module with no enable option. One flag on the
host drives both sides, so they can't drift apart.

### Add a new profile

Create `profiles/my-profile.nix`:
```nix
{ config, lib, pkgs, ... }:
{
  options.profiles.my-profile.enable = lib.mkEnableOption "my profile";

  config = lib.mkIf config.profiles.my-profile.enable {
    # ... home-manager configuration ...
  };
}
```
Enable it for a user: `profiles.my-profile.enable = true;`

## Third-party modules

Ecosystem modules (impermanence, disko, stylix) are plain modules: declare the
input in `flake.nix` and import it in a host, role, or `modules/nixos/*.nix`.
`roles/impermanent.nix` imports impermanence itself and fails the build if the
role is enabled without the input.

## Unfree Packages

Unfree packages are **off by default**. Set `omninix.allowUnfree = true;` in
`flake.nix` to opt the whole flake in (needed for e.g. the `developer`
profile's `dbeaver`/`ngrok`, nvidia drivers, etc.).

## Learn More

See the [OmniNix documentation](https://github.com/marcolongol/omninix) for details.
