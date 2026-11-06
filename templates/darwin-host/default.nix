# A Mac host. Mark it as darwin in flake.nix, and add the nix-darwin input:
#
#   omninix.hostSystems.<this directory's name> = "aarch64-darwin";
#
#   inputs.nix-darwin = {
#     url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
#     inputs.nixpkgs.follows = "nixpkgs";
#   };
#
# Then, on the Mac, the first time (darwin-rebuild isn't installed yet):
#   sudo nix run nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake .#<name>
# and afterwards:
#   sudo darwin-rebuild switch --flake .#<name>
{pkgs, ...}: {
  # nix-darwin's own numbering, not NixOS's. Keep it once set.
  system.stateVersion = 7;

  # Set this to match this host directory's name.
  networking.hostName = "CHANGEME";

  # Roles with a darwin half (roles/<name>/darwin.nix). Until the flake has
  # one, `roles` doesn't exist on Mac hosts, so leave this commented out.
  # roles.<name>.enable = true;

  # Existing macOS accounts. Each gets its Home Manager config from
  # users/<name>. macOS manages passwords and groups itself, so there's no
  # extraGroups here. With one user, it's also system.primaryUser.
  omninix.hostUsers = {
    # your-username.enable = true;
  };

  environment.systemPackages = [pkgs.git];
}
