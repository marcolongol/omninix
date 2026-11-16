# omninix.persistence on hosts: paths to keep across reboots when the host
# wipes its root. Any role or host can add to them; roles.impermanent applies
# them. Declared on every host, so pieces can set them unconditionally.
{lib, ...}: {
  options.omninix.persistence = {
    directories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["/var/lib/docker"];
      description = "System directories to keep under /persist. Applied by roles.impermanent when it's enabled.";
    };
    files = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "System files to keep under /persist. Applied by roles.impermanent when it's enabled.";
    };
  };
}
