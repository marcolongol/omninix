# omninix-info on every host (opt out with omninix.info.enable = false):
# what OmniNix built the host from, and what it's running.
#
# This is the host's half: omninix.info.data, worked out when the host is
# built (its roles, users with their groups and profiles, the config's and
# inputs' revisions, open ports, secret names), handed to the command
# (packages/omninix-info), which adds what only the running machine knows.
#
# Baking in the config's revision means every commit is a new system, even
# one that changes nothing for this host. Turning info off drops that too.
#
# Applied with importApply, so OmniNix's own revision arrives by closure.
{omninixRevision}: {
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.omninix.info;

  # The names in a set of { enable; ... } (roles, profiles) that are on.
  enabledNames = set: lib.attrNames (lib.filterAttrs (_: v: v.enable or false) set);

  # A flake input's (or the config's) revision and commit date. A dirty tree
  # has a dirtyShortRev; a path: input has neither.
  revision = input: {
    revision = input.shortRev or input.dirtyShortRev or null;
    date = let
      d = input.lastModifiedDate or null;
    in
      if d == null
      then null
      else "${builtins.substring 0 4 d}-${builtins.substring 4 2 d}-${builtins.substring 6 2 d}";
  };

  # Options that only exist on some hosts (NixOS-only, or from sops-nix and
  # Home Manager) are read with `or`.
  data = {
    host = config.networking.hostName;
    inherit (pkgs.stdenv.hostPlatform) system;
    stateVersion = toString config.system.stateVersion;
    config = revision (inputs.self or {});
    omninix = omninixRevision;
    inputs = lib.mapAttrs (_: revision) (removeAttrs inputs ["self"]);
    roles = enabledNames (config.roles or {});
    users = lib.genAttrs config.omninix.activeUsers (name: {
      groups = config.users.users.${name}.extraGroups or [];
      profiles = enabledNames (config.home-manager.users.${name}.profiles or {});
    });
    ports = {
      tcp = config.networking.firewall.allowedTCPPorts or [];
      udp = config.networking.firewall.allowedUDPPorts or [];
    };
    secrets = lib.attrNames (config.sops.secrets or {});
  };

in {
  options.omninix.info = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install `omninix-info` (`--json` for scripts), and set system.configurationRevision to the config's commit. Every commit is then a new system, even one that changes nothing for this host; turn this off to avoid that.";
    };

    fancy = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Draw omninix-info's output with gum (boxes, colours). It adds gum (about 15 MiB) to the host; off, the output is plain text with colours and no extra dependencies.";
    };

    data = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      readOnly = true;
      default = data;
      defaultText = lib.literalMD "what OmniNix knows about this host";
      description = "What omninix-info shows that's known when the host is built. Read-only.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [(pkgs.callPackage ./command.nix {
        inherit (cfg) fancy;
        info = cfg.data;
      })];
    # Also shown by nixos-version --configuration-revision (darwin-version on
    # Macs).
    system.configurationRevision = lib.mkDefault (inputs.self.rev or inputs.self.dirtyRev or null);
  };
}
