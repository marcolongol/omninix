# packagesDir and overlaysDir: the flake's own packages and overlays, applied
# to every host, home and perSystem pkgs, and exported for other flakes.
{lib}: let
  # Call a package file, passing `inputs` only if it asks for it
  # (callPackage rejects arguments a package doesn't take).
  callWithInputs = pkgs: inputs: file:
    pkgs.callPackage file (builtins.intersectAttrs (lib.functionArgs (import file)) {inherit inputs;});

  # The overlay of the flake's own packages: pkgs.<name> for every file in
  # `packages` ({ name = file; }, from packagesDir).
  #
  # Type: AttrSet -> AttrSet -> Overlay
  packagesOverlay = inputs: packages: final: _:
    lib.mapAttrs (_: callWithInputs final inputs) packages;

  # The same packages as an overlay other flakes can use: it only adds (never
  # replaces a package they have), and refuses a package that needs our
  # inputs. Checked per package, so one unshareable package doesn't break the
  # others.
  #
  # Type: AttrSet -> Overlay
  exportOverlay = packages: final: prev:
    lib.mapAttrs (name: file:
      if prev ? ${name}
      then throw "OmniNix: overlays.packages: `${name}` would replace an existing package"
      else if lib.functionArgs (import file) ? inputs
      then throw "OmniNix: overlays.packages: `${name}` takes `inputs`, which only this flake has"
      else final.callPackage file {})
    packages;

  # The overlays to apply everywhere: the packages first, then the overlays
  # from overlaysDir in name order, so those can override packages.
  #
  # Type: { inputs, packages, overlays } -> [Overlay]
  allOverlays = {
    inputs,
    packages,
    overlays,
  }:
    lib.optional (packages != {}) (packagesOverlay inputs packages)
    ++ map import (lib.attrValues overlays);

  # The nixpkgs settings every host and standalone home gets.
  #
  # Type: { overlays, allowUnfree } -> Module
  nixpkgsModule = {
    overlays,
    allowUnfree,
  }: {
    nixpkgs.overlays = overlays;
    # Only set when on: nixpkgs.config merges without priorities, so `false`
    # here would override a host's own `allowUnfree = true`.
    nixpkgs.config = lib.optionalAttrs allowUnfree {allowUnfree = true;};
  };

  # packages.<system>: the flake's packages from `pkgs`, minus those whose
  # meta.platforms rule out this system (they stay available as pkgs.<name>).
  #
  # Type: AttrSet -> Pkgs -> AttrSet
  packagesFor = packages: pkgs:
    lib.filterAttrs (_: lib.meta.availableOn pkgs.stdenv.hostPlatform)
    (lib.mapAttrs (name: _: pkgs.${name}) packages);
in {
  inherit packagesOverlay exportOverlay allOverlays nixpkgsModule packagesFor;
}
