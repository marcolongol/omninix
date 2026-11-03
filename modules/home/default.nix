# OmniNix home module
#
# Defines the per-user persistence options under the omninix.* namespace.
# The actual wiring of these into impermanence's home.persistence happens in the
# NixOS+HM bridge (modules/nixos) where the impermanence HM module — and thus the
# home.persistence option — is guaranteed to exist. It cannot live here because
# this module is also imported by standalone homeConfigurations, which have no
# impermanence module (so home.persistence would not exist).
{lib, ...}: {
  # Profiles are enable-based: each profile file declares its own
  # `options.profiles.<name>.enable` and gates its config with it.
  options.omninix.persistence = {
    directories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "User folders to persist under /persist/home/<user> when impermanence is active.";
    };
    files = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "User files to persist under /persist/home/<user> when impermanence is active.";
    };
  };
}
