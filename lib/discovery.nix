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
  forAllNixFiles = dir: f:
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
            # Precedence note: a file `foo.nix` and a directory `foo/` (with
            # default.nix) in the same directory both map to the key `foo`;
            # builtins.readDir ordering then decides which wins via listToAttrs.
            # Avoid naming a file and a directory the same within one scan dir.
            if type == "regular" && final.hasSuffix ".nix" fn
            then final.nameValuePair (final.removeSuffix ".nix" fn) (f "${dir}/${fn}")
            else if type == "directory" && builtins.pathExists "${dir}/${fn}/default.nix"
            then final.nameValuePair fn (f "${dir}/${fn}")
            else null
        ))
      ]
    else {};

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
  # LIST of overlays (the original contract). Any other directory is
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
