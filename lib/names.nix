# Checking per-name maps (hostSystems, hostInputs, userSystems, userInputs)
# against the hosts or users they're about. A misspelt name would otherwise
# be ignored silently.
{lib}: let
  # Names in `given` that aren't in `known`.
  #
  # Type: AttrSet -> AttrSet -> [String]
  #
  # Example:
  #   unknownNames { laptop = …; } { lpatop = "aarch64-linux"; }
  #   => [ "lpatop" ]
  unknownNames = known: given: lib.attrNames (removeAttrs given (lib.attrNames known));

  # unknownNames for several maps at once, keeping only maps with a bad name.
  #
  # Type: AttrSet -> { mapName = AttrSet; } -> { mapName = [String]; }
  #
  # Example:
  #   unknownNamesIn { laptop = …; } { hostSystems = { lpatop = …; }; hostInputs = {}; }
  #   => { hostSystems = [ "lpatop" ]; }
  unknownNamesIn = known: maps: lib.filterAttrs (_: names: names != []) (lib.mapAttrs (_: unknownNames known) maps);

  # Return `value`, or throw naming every bad name in every map.
  #
  # Type: String -> AttrSet -> AttrSet -> a -> a
  #
  # Example message:
  #   OmniNix: hostSystems names unknown host(s): lpatop; hostInputs names unknown host(s): pie
  withKnownNames = kind: known: maps: value: let
    unknown = unknownNamesIn known maps;
  in
    if unknown == {}
    then value
    else throw "OmniNix: ${lib.concatStringsSep "; " (lib.mapAttrsToList (option: names: "${option} names unknown ${kind}(s): ${toString names}") unknown)}";
in {
  inherit unknownNames unknownNamesIn withKnownNames;
}
