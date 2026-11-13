# sops-nix by convention, under secretsPath:
#   users/<user>.yaml   key `hashed-password`: that user's password; also
#                       their default sops file in Home Manager
#   <host>.yaml         the host's default sops file
#
# Needs nothing from lib, so it ignores its argument.
_: let
  # `<secretsPath>/<name>.yaml` if secretsPath is set and the file exists,
  # else null.
  #
  # Type: Path? -> String -> Path?
  #
  # Example:
  #   secretFile ./secrets "users/alice"  => ./secrets/users/alice.yaml
  secretFile = secretsPath: name: let
    file = secretsPath + "/${name}.yaml";
  in
    if secretsPath != null && builtins.pathExists file
    then file
    else null;

  # Return `value`, or throw if secretsPath is set but there's no sops-nix
  # input to decrypt anything with.
  #
  # Type: AttrSet -> Path? -> a -> a
  withSops = inputs: secretsPath: value:
    if secretsPath != null && !(inputs ? sops-nix)
    then throw "OmniNix: secretsPath needs a sops-nix flake input"
    else value;
in {
  inherit secretFile withSops;
}
