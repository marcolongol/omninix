# A new Mac: its directory name is its name and hostname. In flake.nix, mark
# it as a Mac and add nix-darwin:
#   omninix.hostSystems.<name> = "aarch64-darwin";
#   inputs.nix-darwin = {
#     url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
#     inputs.nixpkgs.follows = "nixpkgs";
#   };
# The first time, on the Mac:
#   sudo nix run nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake .#<name>
{
  # nix-darwin's own numbering, not NixOS's.
  system.stateVersion = 7;

  # Existing macOS accounts. macOS manages their passwords and groups.
  # omninix.hostUsers.<user>.enable = true;
}
