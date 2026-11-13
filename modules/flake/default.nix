{inputs, ...}: let
  lib = import ../../lib {inherit inputs;};
in {
  flake = {
    inherit lib;
  };
  perSystem = {pkgs, ...}: let
    testLib = import ../../tests/lib.nix {inherit pkgs lib;};
  in {
    formatter = pkgs.alejandra;
    checks.harness = testLib.mkSuite "harness" (import ../../tests/harness.nix);
  };
}
