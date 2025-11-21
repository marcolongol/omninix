# OmniNix validation helpers
#
# Validation helpers used across the framework. Two flavours live here:
#   - assert* guards: return `true` when valid or throw, for use in `assert`s.
#   - validate* path helpers: return the path (or null) so they can be threaded
#     straight into discovery; the optional one warns via `final.warn` instead
#     of throwing. These take the extended-lib fixpoint `final`.
{final}: {
  # Validate that a value is a string
  #
  # Type: String -> Any -> Bool
  #
  # Parameters:
  #   name  - Name for error messages
  #   value - Value to validate
  #
  # Returns:
  #   true if valid, throws otherwise
  #
  # Example:
  #   assertIsString "username" config.username
  assertIsString = name: value:
    if !builtins.isString value
    then throw "OmniNix: ${name} must be a string, got: ${builtins.typeOf value}"
    else true;

  # Validate that a value is a list
  #
  # Type: String -> Any -> Bool
  assertIsList = name: value:
    if !builtins.isList value
    then throw "OmniNix: ${name} must be a list, got: ${builtins.typeOf value}"
    else true;

  # Validate that a value is in a set of allowed values
  #
  # Type: String -> List -> Any -> Bool
  #
  # Example:
  #   assertOneOf "system" ["x86_64-linux" "aarch64-linux"] config.system
  assertOneOf = name: allowed: value:
    if !(builtins.elem value allowed)
    then throw "OmniNix: ${name} must be one of ${toString allowed}, got: ${toString value}"
    else true;

  # Validate that a path exists
  #
  # Type: String -> Path -> Bool
  #
  # Example:
  #   assertPathExists "config file" ./config.nix
  assertPathExists = name: path:
    if !builtins.pathExists path
    then throw "OmniNix: ${name} does not exist: ${toString path}"
    else true;

  # Validate that all elements in a list are strings
  #
  # Type: String -> List -> Bool
  #
  # Example:
  #   assertAllStrings "roles" config.roles
  assertAllStrings = name: list:
    if !builtins.all builtins.isString list
    then throw "OmniNix: ${name} must be a list of strings"
    else true;

  # Validate that a value is not empty (works for lists, strings, attrsets)
  #
  # Type: String -> Any -> Bool
  #
  # Example:
  #   assertNotEmpty "hostUsers" config.hostUsers
  assertNotEmpty = name: value:
    if builtins.isList value && value == []
    then throw "OmniNix: ${name} cannot be an empty list"
    else if builtins.isString value && value == ""
    then throw "OmniNix: ${name} cannot be an empty string"
    else if builtins.isAttrs value && value == {}
    then throw "OmniNix: ${name} cannot be an empty attribute set"
    else true;

  # Validate that a required directory exists, returning the path
  #
  # Type: String -> Path -> Path
  #
  # Throws an error with a helpful message if the path doesn't exist; otherwise
  # returns the path so it can be threaded straight into discovery.
  #
  # Parameters:
  #   name - Human-readable name for the error message
  #   path - Path to validate
  validatePath = name: path:
    if !builtins.pathExists path
    then
      throw ''
        OmniNix Error: Required directory does not exist: ${name}
        Path: ${toString path}

        Make sure the path is correct and the directory exists.
      ''
    else path;

  # Validate an optional directory, warning (not throwing) if it's missing
  #
  # Type: String -> Path? -> Path?
  #
  # Returns the path if it exists, or null otherwise (with a warning when a
  # non-null path was given but doesn't exist).
  #
  # Parameters:
  #   name - Human-readable name for the warning message
  #   path - Path to validate (or null)
  validateOptionalPath = name: path:
    if path != null && !builtins.pathExists path
    then
      # lib.warn (not builtins.trace): emits on stderr as a proper warning and
      # is suppressible by consumers, matching the warnIf used elsewhere.
      final.warn ''
        OmniNix: optional directory does not exist and will be ignored: ${name}
        Path: ${toString path}
      ''
      null
    else path;
}
