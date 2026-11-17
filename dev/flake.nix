# OmniNix's development inputs: only what the checks need. The main flake
# loads them through a flake-parts partition (flake.nix), so they never end
# up in the lock file of a flake that uses OmniNix.
#
# A `follows` here can't reach the main flake's inputs, so these keep their
# own nixpkgs pins. The checks themselves evaluate with the main nixpkgs.
{
  inputs = {
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    sops-nix.url = "github:Mic92/sops-nix";
    impermanence.url = "github:nix-community/impermanence";
  };

  outputs = _: {};
}
