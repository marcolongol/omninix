# omninix.hostUsers and activeUsers, on NixOS and nix-darwin hosts alike.
# Each platform's module adds what it does with them.
{
  config,
  lib,
  ...
}: {
  options.omninix = {
    hostUsers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.enable = lib.mkEnableOption "this user on this host";
      });
      default = {};
      example = {alice.enable = true;};
      description = "Users to enable on this host.";
    };

    activeUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = lib.attrNames (lib.filterAttrs (_: u: u.enable) config.omninix.hostUsers);
      defaultText = lib.literalExpression "names of the enabled omninix.hostUsers";
      description = "Names of the users enabled on this host. Read-only; use it instead of filtering omninix.hostUsers again.";
    };
  };
}
