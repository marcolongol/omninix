# OmniNix's nix-darwin module: users on Macs.
#
# OmniNix doesn't create macOS accounts: hostUsers describes accounts that
# already exist, as nix-darwin does by default. macOS manages passwords and
# groups itself, so there's no password rule and no extraGroups here
# (setting it is an "option does not exist" error).
{
  config,
  lib,
  ...
}: let
  inherit (config.omninix) activeUsers;
in {
  imports = [../shared/host-users.nix];

  config = lib.mkIf (activeUsers != []) {
    # Home Manager needs to know where each home is.
    users.users = lib.genAttrs activeUsers (name: {home = lib.mkDefault "/Users/${name}";});

    # User-level settings (system.defaults, homebrew, ...) apply to the
    # primary user; with one active user, that's the obvious one.
    system.primaryUser = lib.mkIf (lib.length activeUsers == 1) (lib.mkDefault (lib.head activeUsers));
  };
}
