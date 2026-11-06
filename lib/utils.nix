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
  # the builders and mkFlakeCore.
  mkDebugTrace = debug: msg: val:
    if debug
    then builtins.trace "[OmniNix Debug] ${msg}" val
    else val;
}
