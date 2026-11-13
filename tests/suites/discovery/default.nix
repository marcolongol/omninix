# Directory discovery: which entries of a scanned directory become pieces,
# and what each one maps to.
{lib, ...}: let
  inherit (lib.omninix) discoverNixFiles scanNixFiles;
  markers = ["default.nix"];
in {
  # `plain.nix` becomes `plain`; `with-default/` counts because it holds a
  # marker. `no-marker/` and `README.md` are ignored.
  testFindsFilesAndMarkedDirectories = {
    expr = discoverNixFiles markers ./fixtures;
    expected = {
      plain = ./fixtures/plain.nix;
      with-default = ./fixtures/with-default;
    };
  };

  # Values stay paths: a string would copy each piece to the store on its
  # own and break imports that reach outside it.
  testValuesArePaths = {
    expr = lib.all builtins.isPath (lib.attrValues (discoverNixFiles markers ./fixtures));
    expected = true;
  };

  # A directory counts if it holds any of the markers.
  testOtherMarkers = {
    expr = lib.attrNames (discoverNixFiles ["other.nix"] ./fixtures);
    expected = ["no-marker" "plain"];
  };

  # A directory that doesn't exist is just empty, so optional directories
  # need no special-casing by the caller.
  testMissingDirectoryIsEmpty = {
    expr = discoverNixFiles markers ./does-not-exist;
    expected = {};
  };

  # `foo.nix` and `foo/` both claim the name `foo`.
  testScanReportsClashes = {
    expr = (scanNixFiles markers ./clash).clashes;
    expected = ["foo"];
  };

  testClashThrows = {
    expr = (builtins.tryEval (discoverNixFiles markers ./clash)).success;
    expected = false;
  };
}
