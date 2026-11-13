# Directory discovery: turn a directory into { name = path; }, one entry per
# piece (host, role, user, profile, module, package...).
#
# A piece is either:
#   - a regular file `<name>.nix`, or
#   - a directory `<name>/` holding one of the `markers` files (usually
#     `default.nix`; roles also accept `darwin.nix`).
# Everything else (README.md, .gitkeep, unmarked directories) is ignored.
{lib}: let
  # Scan without judging: the pieces found, plus the names claimed by both a
  # file and a directory. Kept separate from discoverNixFiles so the clash
  # can be tested as data.
  #
  # Type: [String] -> Path -> { pieces :: AttrSet; clashes :: [String]; }
  scanNixFiles = markers: dir: let
    entries =
      if builtins.pathExists dir
      then builtins.readDir dir
      else {};

    isNixFile = name: type: type == "regular" && lib.hasSuffix ".nix" name;
    isMarkedDir = name: type:
      type == "directory" && lib.any (m: builtins.pathExists (dir + "/${name}/${m}")) markers;

    # `dir + "/x"` keeps a path a path. "${dir}/x" would be a string naming a
    # store copy of `dir` alone, so a piece couldn't import anything outside
    # it.
    files = lib.mapAttrs' (name: _: lib.nameValuePair (lib.removeSuffix ".nix" name) (dir + "/${name}")) (lib.filterAttrs isNixFile entries);
    dirs = lib.mapAttrs (name: _: dir + "/${name}") (lib.filterAttrs isMarkedDir entries);
  in {
    pieces = files // dirs;
    clashes = lib.attrNames (builtins.intersectAttrs files dirs);
  };

  # The pieces in `dir`; {} if it doesn't exist. Throws when a file and a
  # directory share a name, since either choice would silently drop one.
  #
  # Type: [String] -> Path -> AttrSet
  #
  # Example:
  #   hosts/{laptop.nix, server/default.nix}
  #   discoverNixFiles ["default.nix"] ./hosts
  #   => { laptop = ./hosts/laptop.nix; server = ./hosts/server; }
  discoverNixFiles = markers: dir: let
    scan = scanNixFiles markers dir;
  in
    if scan.clashes != []
    then throw "OmniNix: ${toString dir} has both a file and a directory named: ${toString scan.clashes}"
    else scan.pieces;
in {
  inherit scanNixFiles discoverNixFiles;
}
