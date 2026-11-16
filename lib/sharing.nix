# Using another flake's pieces (the extra* options): ours win a name clash,
# and a borrowed role or profile can't silently read our `inputs`.
{lib}: let
  # The extra pieces whose names we don't use ourselves; on a clash, ours win,
  # with a warning (a role's enable option is baked into its file, so only one
  # file per name can be imported).
  #
  # Type: String -> AttrSet -> AttrSet -> AttrSet
  newExtras = kind: ours: extra: let
    clashes = lib.attrNames (builtins.intersectAttrs ours extra);
  in
    lib.warnIf (clashes != [])
    "OmniNix: your ${kind} replace the extra ${kind} for: ${toString clashes}"
    (removeAttrs extra clashes);

  # Our pieces plus the new extras.
  #
  # Type: String -> AttrSet -> AttrSet -> AttrSet
  withExtras = kind: ours: extra: ours // newExtras kind ours extra;

  # A role or profile from another flake that asks for `inputs` would get
  # *ours* without a word. Give it an `inputs` that throws a readable error
  # when read instead. Pieces that don't ask for `inputs` pass through
  # untouched (same value, so the module system still dedups them).
  #
  # Type: String -> String -> Module -> Module
  borrow = kind: name: piece: let
    isFile = builtins.isPath piece || builtins.isString piece;
    module =
      if isFile
      then import piece
      else piece;
    args = lib.optionalAttrs (lib.isFunction module) (lib.functionArgs module);
    id =
      if isFile
      then toString piece
      else "omninix-borrowed-${kind}-${name}";
  in
    if !(args ? inputs)
    then piece
    else {
      key = id;
      _file = id;
      # setFunctionArgs keeps the argument names, so the module system still
      # passes this module what it asks for.
      imports = [
        (lib.setFunctionArgs (moduleArgs:
          module (moduleArgs
            // {
              inputs = throw ''
                OmniNix: ${kind}.${name} comes from another flake and reads `inputs`, which only
                that flake has. It isn't shareable as is: pass what it needs some other way.'';
            }))
        args)
      ];
    };
in {
  inherit newExtras withExtras borrow;
}
