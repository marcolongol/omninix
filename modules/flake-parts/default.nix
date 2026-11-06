# OmniNix flake-parts module (flakeModules.default): typed options over
# mkFlakeCore, the internal engine.
{omninixLib}: {
  config,
  lib,
  inputs,
  ...
}: let
  inherit (lib) mkOption types;
  cfg = config.omninix;

  # Passed through untouched (paths stay paths); one definition per name.
  moduleSet = types.attrsOf (types.addCheck types.raw (v: builtins.isPath v || builtins.isString v || builtins.isFunction v || builtins.isAttrs v));

  dirOption = description:
    mkOption {
      type = types.nullOr types.path;
      default = null;
      inherit description;
    };

  # Also decides how flake.homeModules is typed (see config below).
  hmFlakeModule = inputs ? home-manager && inputs.home-manager ? flakeModules;
  # Declares a typed flake.darwinConfigurations, so hand-written darwin hosts
  # merge with OmniNix's; imported by path, so it dedups with your own import.
  darwinFlakeModule = inputs ? nix-darwin && inputs.nix-darwin ? flakeModules;

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
      extraNixosModules
      homeManagerModulesDir
      extraHomeManagerModules
      darwinModulesDir
      extraDarwinModules
      overlaysDir
      packagesDir
      secretsPath
      defaultSystem
      hostSystems
      userSystems
      hostInputs
      userInputs
      allowUnfree
      debug
      ;
  };
in {
  # Typed, mergeable flake.homeConfigurations; dedups with a consumer's own import.
  imports =
    lib.optional hmFlakeModule inputs.home-manager.flakeModules.home-manager
    ++ lib.optional darwinFlakeModule inputs.nix-darwin.flakeModules.default;

  options.omninix = {
    hostsDir = dirOption "Directory of hosts; each .nix file or dir/default.nix becomes nixosConfigurations.<name>.";
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
    extraNixosModules = mkOption {
      type = moduleSet;
      default = {};
      description = "Extra NixOS modules by name (e.g. another flake's nixosModules), imported into every host. Local nixosModulesDir wins on collision.";
    };
    homeManagerModulesDir = dirOption "Directory of Home Manager modules imported for every user.";
    extraHomeManagerModules = mkOption {
      type = moduleSet;
      default = {};
      description = "Extra Home Manager modules by name (e.g. another flake's homeModules), imported for every user. Local homeManagerModulesDir wins on collision.";
    };
    darwinModulesDir = dirOption "Directory of nix-darwin modules imported into every darwin host, exported as darwinModules.";
    extraDarwinModules = mkOption {
      type = moduleSet;
      default = {};
      description = "Extra nix-darwin modules by name (e.g. another flake's darwinModules), imported into every darwin host. Local darwinModulesDir wins on collision.";
    };
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
    hostInputs = mkOption {
      type = types.attrsOf (types.lazyAttrsOf types.raw);
      default = {};
      example = lib.literalExpression ''
        {
          rpi = {
            nixpkgs = inputs.nixpkgs-unstable;
            home-manager = inputs.home-manager-unstable;
          };
        }
      '';
      description = "Per-host input overrides, merged over the flake's inputs for that host only (its nixosSystem, home-manager/sops-nix modules and `inputs` argument).";
    };
    userInputs = mkOption {
      type = types.attrsOf (types.lazyAttrsOf types.raw);
      default = {};
      description = "Per-user input overrides for standalone homeConfigurations, like hostInputs.";
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
      inherit (core.outputs) hosts roles profiles users nixosConfigurations homeConfigurations darwinConfigurations;
      # mkDefault so a consumer's own same-named export replaces ours instead of
      # merging with it (deferredModule merges definitions).
      nixosModules = lib.mapAttrs (_: lib.mkDefault) core.outputs.nixosModules;
      # No typed option declares it, so like an untyped homeModules: the whole
      # value is the default.
      darwinModules = lib.mkDefault core.outputs.darwinModules;
      # Typed per entry only with HM's flakeModule; otherwise flake.homeModules is
      # a freeform raw value, which would keep per-entry mkDefault literally.
      homeModules =
        if hmFlakeModule
        then lib.mapAttrs (_: lib.mkDefault) core.outputs.homeModules
        else lib.mkDefault core.outputs.homeModules;
      # Same: your own overlays.packages wins.
      overlays = lib.mkIf core.hasPackages (lib.mapAttrs (_: lib.mkDefault) core.overlays);
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
