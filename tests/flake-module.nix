# The checks, as a flake-parts module. flake.nix evaluates it in the `dev`
# partition, where `inputs` also has the development inputs (dev/flake.nix).
{inputs, ...}: let
  lib = import ../lib {inherit inputs;};
in {
  perSystem = {pkgs, ...}: {
    # One check per suite in tests/suites, and per build in tests/builds.
    checks = import ./. {inherit pkgs lib inputs;};
  };
}
