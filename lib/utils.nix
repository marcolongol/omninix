# OmniNix generic utility functions
#
# Small, broadly-useful helpers. Receives the extended-lib fixpoint `final`.
{final}: {
  # Map attributes to list, filter nulls, and convert back to attrs
  #
  # Type: (String -> String -> NameValuePair?) -> AttrSet -> AttrSet
  #
  # This is a utility function that applies a function to each attribute
  # in an attribute set, filters out null results, and converts the list
  # back to an attribute set.
  #
  # Parameters:
  #   f     - Function that takes (name, value) and returns either a
  #           nameValuePair or null
  #   attrs - Input attribute set to process
  #
  # Returns:
  #   Attribute set containing only non-null results from f
  #
  # Example:
  #   mapAttrsMaybe (name: type:
  #     if type == "regular"
  #     then nameValuePair name "${name}.nix"
  #     else null
  #   ) { file1 = "regular"; dir1 = "directory"; }
  #   => { file1 = "file1.nix"; }
  mapAttrsMaybe = f: attrs:
    final.pipe attrs [
      (final.mapAttrsToList f)
      (builtins.filter (x: x != null))
      builtins.listToAttrs
    ];

  # Make a debug-trace helper bound to a debug flag
  #
  # Type: Bool -> String -> a -> a
  #
  # Returns a `msg: val:` function that traces msg (prefixed) and returns
  # val when debug is true, or returns val untouched otherwise. Shared by
  # mkNixosConfigurations, mkHomeConfigurations, and mkFlake.
  mkDebugTrace = debug: msg: val:
    if debug
    then builtins.trace "[OmniNix Debug] ${msg}" val
    else val;

  # Select only the named entries from an attrset (e.g. cherry-pick roles or
  # profiles from a library before passing as extraRoles/extraProfiles).
  #
  # Type: [String] -> AttrSet -> AttrSet
  #
  # Throws (via getAttrs) if a requested name is absent, so typos surface.
  #
  # Example:
  #   omninix.pick [ "docker" "nginx" ] omninix.roles
  pick = names: attrs: let
    missing = builtins.filter (n: !(attrs ? ${n})) names;
  in
    if missing != []
    then
      throw ''
        OmniNix: pick: attribute(s) not found: ${toString missing}
        Available: ${toString (builtins.attrNames attrs)}
      ''
    else final.getAttrs names attrs;

  # Drop the named entries from an attrset (e.g. take a whole library except the
  # ones you override locally).
  #
  # Type: [String] -> AttrSet -> AttrSet
  #
  # Example:
  #   omninix.drop [ "docker" ] omninix.roles
  drop = names: attrs: builtins.removeAttrs attrs names;
}
