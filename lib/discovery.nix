# OmniNix directory discovery
#
# Helpers that scan directories for `.nix` files and assemble them into attr
# sets. Receives the extended-lib fixpoint `final` (mkDirMap calls
# `final.omninix.forAllNixFiles` through the fixpoint).
{final}: {
  # Discover and process all .nix files in a directory
  #
  # Type: Path -> (Path -> a) -> AttrSet
  #
  # Scans a directory for .nix files and subdirectories with default.nix,
  # applies a function to each, and returns an attribute set keyed by
  # filename (without .nix extension) or directory name.
  #
  # Parameters:
  #   dir - Path to directory to scan
  #   f   - Function to apply to each discovered path
  #
  # Returns:
  #   Attribute set mapping names to results of f
  #   Returns {} if directory doesn't exist
  #
  # Discovery rules:
  #   - Regular files ending in .nix: name without .nix extension
  #   - Directories with default.nix: directory name
  #   - Everything else: ignored
  #
  # Example:
  #   Given directory structure:
  #     hosts/
  #       laptop.nix
  #       server/
  #         default.nix
  #
  #   forAllNixFiles ./hosts (path: path)
  #   => { laptop = ./hosts/laptop.nix; server = ./hosts/server; }
  forAllNixFiles = final.omninix.forAllNixFilesWith ["default.nix"];

  # forAllNixFiles, where a directory counts if it holds any of `markers`
  #
  # Type: [String] -> Path -> (Path -> a) -> AttrSet
  #
  # Example (roles: a directory may hold only a darwin half):
  #   forAllNixFilesWith ["default.nix" "darwin.nix"] ./roles (p: p)
  forAllNixFilesWith = markers: dir: f:
    if builtins.pathExists dir
    then
      final.pipe dir [
        builtins.readDir
        (final.omninix.mapAttrsMaybe (
          fn: type:
          # Only `.nix` regular files are discovered. Without this guard a
          # stray README.md / .gitkeep / secrets.yaml in a scanned directory
          # would be keyed verbatim and later `import`ed, producing a
          # confusing eval error.
          #
          # `dir + "/…"` keeps a path a path. Interpolating it ("${dir}/…")
          # would copy each scanned directory to the store on its own, so a
          # discovered module could not import files outside its directory.
          #
          # Precedence note: a file `foo.nix` and a directory `foo/` (with
          # default.nix) in the same directory both map to the key `foo`;
          # builtins.readDir ordering then decides which wins via listToAttrs.
          # Avoid naming a file and a directory the same within one scan dir.
            if type == "regular" && final.hasSuffix ".nix" fn
            then final.nameValuePair (final.removeSuffix ".nix" fn) (f (dir + "/${fn}"))
            # A path here too: the interpolated string names a store copy of
            # `dir` that `nix flake check --no-build` never creates.
            else if type == "directory" && builtins.any (m: builtins.pathExists (dir + "/${fn}/${m}")) markers
            then final.nameValuePair fn (f (dir + "/${fn}"))
            else null
        ))
      ]
    else {};

  # Discover a shareable piece directory (roles, profiles, modules)
  #
  # Type: Path -> { all :: AttrSet; exportable :: AttrSet; }
  #
  # Like forAllNixFiles, plus `<dir>/internal/`: its entries join the same map
  # (same names, same import depth) so they are used locally, but they are
  # left out of `exportable`, which is what the flake exports. "internal" is
  # reserved: it is never an entry itself. A name defined both in `dir` and
  # in `internal/` throws instead of one silently winning.
  #
  # Example:
  #   roles/{desktop.nix, internal/site.nix}
  #   discoverPieces ./roles
  #   => { all = { desktop = …; site = …; }; exportable = { desktop = …; }; }
  discoverPieces = final.omninix.discoverPiecesWith ["default.nix"];

  # discoverPieces for roles: a role directory may hold a NixOS half
  # (default.nix), a darwin half (darwin.nix), or both.
  discoverRoles = final.omninix.discoverPiecesWith ["default.nix" "darwin.nix"];

  discoverPiecesWith = markers: dir: let
    top = builtins.removeAttrs (final.omninix.forAllNixFilesWith markers dir (fn: fn)) ["internal"];
    internal = final.omninix.forAllNixFilesWith markers (dir + "/internal") (fn: fn);
    clashes = builtins.attrNames (builtins.intersectAttrs top internal);
  in
    if clashes != []
    then throw "OmniNix: ${toString dir} and its internal/ both define: ${toString clashes}"
    else {
      all = top // internal;
      exportable = top;
    };

  # Split roles into the halves each kind of host imports
  #
  # Type: AttrSet -> { nixos :: AttrSet; darwin :: AttrSet; inline :: [String]; }
  #
  # A role directory gives its default.nix to NixOS (as the directory path,
  # unchanged) and its darwin.nix to darwin. A file, or a value that isn't a
  # path (a function or attrset module), is NixOS only: there's nothing to
  # look inside. `inline` names those non-path values, so a flake with darwin
  # hosts can warn that they can't carry a darwin half.
  #
  # Example:
  #   splitRoles { docker = ./roles/docker.nix; desktop = ./roles/desktop; }
  #   => { nixos = { docker = …; desktop = ./roles/desktop; };
  #        darwin = { desktop = ./roles/desktop/darwin.nix; }; inline = []; }
  splitRoles = roles: let
    isPathLike = v: builtins.isPath v || builtins.isString v;
    isDir = v: isPathLike v && builtins.readFileType v == "directory";
    has = file: v: isDir v && builtins.pathExists (v + "/${file}");
  in {
    nixos = final.filterAttrs (_: v: !(isDir v) || has "default.nix" v) roles;
    darwin = final.mapAttrs (_: v: v + "/darwin.nix") (final.filterAttrs (_: has "darwin.nix") roles);
    inline = builtins.attrNames (final.filterAttrs (_: v: !(isPathLike v)) roles);
  };

  # Map multiple directories to their discovered .nix files
  #
  # Type: AttrSet -> AttrSet
  #
  # Applies forAllNixFiles to multiple directories simultaneously,
  # creating a nested attribute set structure.
  #
  # Parameters:
  #   dirs - Attribute set of { name = path } to scan
  #
  # Returns:
  #   Nested attribute set { dirName = { fileName = path } }
  #
  # Example:
  #   mkDirMap {
  #     hosts = ./hosts;
  #     roles = ./roles;
  #   }
  #   => {
  #     hosts = { laptop = ./hosts/laptop.nix; server = ./hosts/server; };
  #     roles = { common = ./roles/common.nix; desktop = ./roles/desktop.nix; };
  #   }
  mkDirMap = final.mapAttrs (_: dir: final.omninix.forAllNixFiles dir (fn: fn));

  # Load a list of nixpkgs overlays from a path
  #
  # Type: Path -> [Overlay]
  #
  # A file, or a directory with default.nix, is imported and must return a
  # LIST of overlays. Any other directory is
  # discovered like roles/: every .nix file (or subdirectory with default.nix)
  # is one overlay, applied in name order.
  #
  # Example:
  #   overlays/overrides.nix  -> loadOverlays ./overlays == [ (import ./overlays/overrides.nix) ]
  loadOverlays = path:
    if builtins.readFileType path == "directory" && !(builtins.pathExists (path + "/default.nix"))
    then map import (final.attrValues (final.omninix.forAllNixFiles path (fn: fn)))
    else import path;
}
