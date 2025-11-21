{
  self,
  inputs,
  ...
}: let
  # Single instantiation of the OmniNix-extended lib for this flake. It is built
  # once here and reused for the `dirs` scan, the exposed `flake.lib` (consumers'
  # `omninix.lib.omninix.*` resolves to this very value), and the per-system checks.
  # We cannot use `self.lib` instead — that is the output we are defining here,
  # so referencing it would be circular.
  lib = import ../../lib {inherit inputs;};
  dirs = lib.omninix.mkDirMap {
    profiles = ../../profiles;
    roles = ../../roles;
  };
in {
  flake = {
    # Expose the library
    inherit lib;
    # Expose global roles and profiles
    inherit (dirs) profiles roles;

    # Templates. `default` scaffolds a whole config; the rest scaffold a single
    # component into a new directory, e.g.
    #   nix flake new -t github:marcolongol/omninix#host hosts/laptop
    #   nix flake new -t github:marcolongol/omninix#role roles/webserver
    # Discovery treats a directory with default.nix as one unit, so these land
    # as hosts/<name>, roles/<name>, etc. automatically.
    templates = {
      default = {
        path = ../../templates/default;
        description = "A basic OmniNix configuration with example host, roles, users, and profiles";
      };
      host = {
        path = ../../templates/host;
        description = "Scaffold a new OmniNix host (nix flake new -t …#host hosts/<name>)";
      };
      user = {
        path = ../../templates/user;
        description = "Scaffold a new OmniNix user (nix flake new -t …#user users/<name>)";
      };
      role = {
        path = ../../templates/role;
        description = "Scaffold a new OmniNix role (nix flake new -t …#role roles/<name>)";
      };
      profile = {
        path = ../../templates/profile;
        description = "Scaffold a new OmniNix profile (nix flake new -t …#profile profiles/<name>)";
      };
    };
  };

  # Per-system flake checks: the eval test suites (Layer 1 lib + Layer 2
  # config-behaviour) and, on Linux, the VM boot test. Run with `nix flake check`.
  perSystem = {
    pkgs,
    system,
    ...
  }: {
    checks = import ../../tests/checks.nix {
      inherit pkgs system inputs lib;
    };

    devShells.default = pkgs.mkShellNoCC {
      packages = with pkgs; [
        nil # Nix LSP
        alejandra # formatter
        statix # linter
        deadnix # dead-code finder
      ];
    };
  };
}
