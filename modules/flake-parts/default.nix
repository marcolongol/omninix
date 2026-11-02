# OmniNix flake-parts module (flakeModules.default): typed options over
# mkFlakeCore, the engine mkFlake also uses.
{omninixLib}: {
  config,
  lib,
  inputs,
  ...
}: let
  inherit (lib) mkOption types;
  cfg = config.omninix;

  # Passed through untouched (paths stay paths); one definition per name, like mkFlake.
  moduleSet = types.attrsOf (types.addCheck types.raw (v: builtins.isPath v || builtins.isString v || builtins.isFunction v || builtins.isAttrs v));

  dirOption = description:
    mkOption {
      type = types.nullOr types.path;
      default = null;
      inherit description;
    };

  core = omninixLib.omninix.mkFlakeCore inputs {
    inherit
      (cfg)
      hostsDir
      rolesDir
      extraRoles
      usersDir
      profilesDir
      extraProfiles
      nixosModulesDir
      homeManagerModulesDir
      overlaysDir
      packagesDir
      secretsPath
      defaultSystem
      hostSystems
      userSystems
      allowUnfree
      debug
      ;
  };
in {
  # Typed, mergeable flake.homeConfigurations; dedups with a consumer's own import.
  imports = lib.optional (inputs ? home-manager && inputs.home-manager ? flakeModules) inputs.home-manager.flakeModules.home-manager;

  options.omninix = {
    hostsDir = mkOption {
      type = types.path;
      description = "Directory of hosts; each .nix file or dir/default.nix becomes nixosConfigurations.<name>.";
    };
    rolesDir = dirOption "Directory of system roles, imported into every host.";
    extraRoles = mkOption {
      type = moduleSet;
      default = {};
      description = "Extra roles by name (e.g. omninix.roles). Local rolesDir wins on collision.";
    };
    usersDir = dirOption "Directory of users; each also becomes homeConfigurations.<name>.";
    profilesDir = dirOption "Directory of Home Manager profiles, imported for every user.";
    extraProfiles = mkOption {
      type = moduleSet;
      default = {};
      description = "Extra profiles by name (e.g. omninix.profiles). Local profilesDir wins on collision.";
    };
    nixosModulesDir = dirOption "Directory of NixOS modules imported into every host.";
    homeManagerModulesDir = dirOption "Directory of Home Manager modules imported for every user.";
    overlaysDir = dirOption "Overlays: one per .nix file, or a file/default.nix returning a list.";
    packagesDir = dirOption "Packages (callPackage form): pkgs.<name> everywhere and perSystem.packages.<name>.";
    secretsPath = dirOption "sops-nix secrets directory (users/<name>.yaml, <host>.yaml).";
    defaultSystem = mkOption {
      type = types.str;
      default = "x86_64-linux";
      description = "System for hosts and users not listed in hostSystems/userSystems.";
    };
    hostSystems = mkOption {
      type = types.attrsOf types.str;
      default = {};
      example = {rpi = "aarch64-linux";};
      description = "Per-host system override.";
    };
    userSystems = mkOption {
      type = types.attrsOf types.str;
      default = {};
      example = {alice = "aarch64-darwin";};
      description = "Per-user system override for standalone homeConfigurations.";
    };
    allowUnfree = mkOption {
      type = types.bool;
      default = false;
      description = "Allow unfree packages on hosts, home configs, packages and perSystem pkgs.";
    };
    debug = mkOption {
      type = types.bool;
      default = false;
      description = "Trace OmniNix discovery and builds.";
    };
  };

  config = {
    flake = {
      inherit (core.outputs) hosts roles profiles users nixosConfigurations homeConfigurations;
    };

    perSystem = {system, ...}: let
      pkgs = core.pkgsFor system;
    in {
      _module.args.pkgs = lib.mkDefault pkgs;
      # From OmniNix's pkgs, not the overridable arg, so they match host pkgs.
      packages = lib.mapAttrs (_: lib.mkDefault) (core.packagesOf pkgs);
    };
  };
}
