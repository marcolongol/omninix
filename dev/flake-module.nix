# What the dev partition adds (flake.nix): the checks and the docs site. Both
# need the development inputs from dev/flake.nix, which `inputs` has here.
{inputs, ...}: let
  lib = import ../lib {inherit inputs;};
in {
  perSystem = {pkgs, ...}: let
    docs = import ../docs/site {inherit pkgs lib inputs;};
  in {
    # One check per suite in tests/suites and per build in tests/builds, plus
    # the docs: building them renders every option page, so broken option
    # docs fail the checks.
    checks =
      import ../tests {inherit pkgs lib inputs;}
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {inherit docs;};

    packages.docs = docs;
  };
}
