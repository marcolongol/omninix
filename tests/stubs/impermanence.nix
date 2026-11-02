# Options-only stand-in for impermanence's NixOS module (omninix has no impermanence input).
{lib, ...}: {
  options.environment.persistence = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        hideMounts = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        directories = lib.mkOption {
          type = lib.types.listOf lib.types.anything;
          default = [];
        };
        files = lib.mkOption {
          type = lib.types.listOf lib.types.anything;
          default = [];
        };
      };
    });
    default = {};
  };
}
