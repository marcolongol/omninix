{inputs, ...}: let
  lib = import ../../lib {inherit inputs;};
in {
  flake = {
    # Only our namespace, not the whole extended lib: that would hand
    # consumers a copy of nixpkgs' lib on our pin instead of theirs (nixpkgs
    # warns against extending lib for exactly this reason).
    lib = lib.omninix;

    # What consumers import. importApply hands it our namespace by closure;
    # inside their flake, `lib` and `inputs` are theirs.
    flakeModules.default = lib.modules.importApply ../flake-parts {omninixLib = lib.omninix;};
  };
  perSystem = {pkgs, ...}: {
    formatter = pkgs.alejandra;
    # One check per suite in tests/suites.
    checks = import ../../tests {inherit pkgs lib inputs;};
  };
}
