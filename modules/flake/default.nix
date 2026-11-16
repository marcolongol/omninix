{inputs, ...}: let
  lib = import ../../lib {inherit inputs;};

  # What consumers import. importApply hands it our namespace by closure;
  # inside their flake, `lib` and `inputs` are theirs.
  flakeModule = lib.modules.importApply ../flake-parts {omninixLib = lib.omninix;};
in {
  # OmniNix uses its own flake module, like any consumer (see flake.nix).
  # Imported by path, not via self.flakeModules: that would be infinite
  # recursion, since imports are needed before `self` exists.
  imports = [flakeModule];

  flake = {
    # Only our namespace, not the whole extended lib: that would hand
    # consumers a copy of nixpkgs' lib on our pin instead of theirs (nixpkgs
    # warns against extending lib for exactly this reason).
    lib = lib.omninix;

    flakeModules.default = flakeModule;
  };

  perSystem = {pkgs, ...}: {
    formatter = pkgs.alejandra;
    # One check per suite in tests/suites.
    checks = import ../../tests {inherit pkgs lib inputs;};
  };
}
