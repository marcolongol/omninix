# omninix.persistence in homes: paths in the user's home to keep across
# reboots. Declared in every home, standalone ones included, so profiles can
# set them unconditionally. modules/home/persistence-host.nix applies them on
# hosts that persist.
{lib, ...}: {
  options.omninix.persistence = {
    directories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [".ssh" "Documents"];
      description = "Folders in the home to keep under /persist/home/<user>, when the host persists.";
    };
    files = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Files in the home to keep under /persist/home/<user>, when the host persists.";
    };
  };
}
