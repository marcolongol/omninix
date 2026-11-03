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

  # Also decides how flake.homeModules is typed (see config below).
  hmFlakeModule = inputs ? home-manager && inputs.home-manager ? flakeModules;

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
  imports = lib.optional hmFlakeModule inputs.home-manager.flakeModules.home-manager;

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

    checks.portable = {
      enable = lib.mkEnableOption "checks that this flake's exported roles, profiles and modules work in other flakes";
      system = mkOption {
        type = types.str;
        default = cfg.defaultSystem;
        defaultText = lib.literalExpression "config.omninix.defaultSystem";
        description = "System the checks evaluate on (Linux).";
      };
      requires = mkOption {
        type = types.attrsOf (types.attrsOf (types.listOf types.raw));
        default = {};
        example = lib.literalExpression "{ roles.desktop = [ inputs.stylix.nixosModules.stylix ]; }";
        description = "Modules a consumer must bring, per piece (NixOS modules for roles/nixosModules, Home Manager modules for profiles/homeModules).";
      };
      scenarios = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            nixos = mkOption {
              type = types.raw;
              default = {};
              description = "NixOS module enabling pieces with sample values.";
            };
            home = mkOption {
              type = types.raw;
              default = {};
              description = "Home Manager module for the probe user.";
            };
            requires = mkOption {
              type = types.listOf types.raw;
              default = [];
              description = "NixOS modules this scenario needs.";
            };
            homeRequires = mkOption {
              type = types.listOf types.raw;
              default = [];
              description = "Home Manager modules this scenario needs.";
            };
          };
        });
        default = {};
        description = "Deep evaluations with pieces enabled.";
      };
      exclude = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["roles.desktop"];
        description = "Pieces not checked yet, as \"<kind>.<name>\" (warns while non-empty).";
      };
      enableOptions = mkOption {
        type = types.attrsOf (types.attrsOf types.str);
        default = {};
        example = {nixosModules.foo = "programs.foo.enable";};
        description = "Enable options for the enabled-without-requires check; roles and profiles default to roles.<camelName>.enable / profiles.<camelName>.enable.";
      };
      allow = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Strings the personal-value lint ignores.";
      };
    };
  };

  config = {
    flake = {
      inherit (core.outputs) hosts roles profiles users nixosConfigurations homeConfigurations;
      # mkDefault so a consumer's own same-named export replaces ours instead of
      # merging with it (deferredModule merges definitions).
      nixosModules = lib.mapAttrs (_: lib.mkDefault) core.outputs.nixosModules;
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
      portable = cfg.checks.portable;
    in {
      _module.args.pkgs = lib.mkDefault pkgs;
      checks = lib.mkIf (portable.enable && system == portable.system) (
        omninixLib.omninix.mkPortableCheck {
          inherit inputs;
          inherit (portable) system requires scenarios exclude enableOptions allow;
          pieces = {inherit (core.outputs) roles profiles nixosModules homeModules;};
        }
      );
      # From OmniNix's pkgs, not the overridable arg, so they match host pkgs.
      packages = lib.mapAttrs (_: lib.mkDefault) (core.packagesOf pkgs);
    };
  };
}
