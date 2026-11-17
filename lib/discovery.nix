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
  # Type: [String] -> Path? -> { pieces :: AttrSet; clashes :: [String]; }
  scanNixFiles = markers: dir: let
    # An unset (null) or missing directory has no pieces.
    entries =
      if dir != null && builtins.pathExists dir
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

  # The pieces in `dir`; {} if it's unset or doesn't exist. Throws when a file and a
  # directory share a name, since either choice would silently drop one.
  #
  # Type: [String] -> Path? -> AttrSet
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

  # A directory of shareable pieces (roles, profiles, modules): its own
  # entries plus those in its `internal/` subdirectory. Both are used locally;
  # only the former are exported. "internal" is never a piece itself, and a
  # name in both places throws instead of one silently winning.
  #
  # Type: [String] -> Path? -> { all :: AttrSet; exportable :: AttrSet; }
  #
  # Example:
  #   roles/{desktop.nix, internal/site.nix}
  #   discoverPieces ["default.nix"] ./roles
  #   => { all = { desktop = …; site = …; }; exportable = { desktop = …; }; }
  discoverPieces = markers: dir: let
    top = removeAttrs (discoverNixFiles markers dir) ["internal"];
    internal = lib.optionalAttrs (dir != null) (discoverNixFiles markers (dir + "/internal"));
    clashes = lib.attrNames (builtins.intersectAttrs top internal);
  in
    if clashes != []
    then throw "OmniNix: ${toString dir} and its internal/ both define: ${toString clashes}"
    else {
      all = top // internal;
      exportable = top;
    };

  # Roles for each platform. A role directory may hold a NixOS half
  # (default.nix), a darwin half (darwin.nix), or both; a role file is NixOS
  # only, and so is a role given as a module rather than a path (there's
  # nothing to look inside). Discover roles with markers
  # ["default.nix" "darwin.nix"] so darwin-only directories are found.
  #
  # Type: AttrSet -> { nixos :: AttrSet; darwin :: AttrSet; }
  #
  # Example:
  #   splitRoles { docker = ./roles/docker.nix; desktop = ./roles/desktop; }
  #   => { nixos = { docker = ./roles/docker.nix; desktop = ./roles/desktop; };
  #        darwin = { desktop = ./roles/desktop/darwin.nix; }; }
  #   (when roles/desktop has both halves)
  splitRoles = roles: let
    isDir = role: (builtins.isPath role || builtins.isString role) && builtins.readFileType role == "directory";
    has = file: path: isDir path && builtins.pathExists (path + "/${file}");
  in {
    nixos = lib.filterAttrs (_: role: !(isDir role) || has "default.nix" role) roles;
    darwin = lib.mapAttrs (_: dir: dir + "/darwin.nix") (lib.filterAttrs (_: has "darwin.nix") roles);
  };
in {
  inherit scanNixFiles discoverNixFiles discoverPieces splitRoles;
}
