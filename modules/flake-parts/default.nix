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
    hostsDir = dirOption "Hosts, one per `.nix` file or `<name>/default.nix`. Each becomes `nixosConfigurations.<name>`, or `darwinConfigurations.<name>` when its system is darwin.";
    rolesDir = dirOption "Roles, imported into every host: a file or `<name>/default.nix` for NixOS hosts, `<name>/darwin.nix` for Mac hosts. Each declares its own `roles.<name>.enable`.";
    extraRoles = mkOption {
      type = moduleSet;
      default = {};
      description = "More roles by name, e.g. `omninix.roles` or another flake's `roles`. `rolesDir` wins on a name clash. Pass role directories (paths) to bring their darwin halves too.";
    };
    usersDir = dirOption "Users (Home Manager modules), one per `.nix` file or `<name>/default.nix`. Each is a host user where `omninix.hostUsers.<name>.enable` is set, and also `homeConfigurations.<name>`.";
    profilesDir = dirOption "Profiles (Home Manager modules), imported for every user. Each declares its own `profiles.<name>.enable`.";
    extraProfiles = mkOption {
      type = moduleSet;
      default = {};
      description = "More profiles by name, e.g. `omninix.profiles`. `profilesDir` wins on a name clash.";
    };
    nixosModulesDir = dirOption "Always-on NixOS modules and option libraries, imported into every NixOS host and exported as `nixosModules`.";
    extraNixosModules = mkOption {
      type = moduleSet;
      default = {};
      description = "More NixOS modules by name, e.g. another flake's `nixosModules`, imported into every NixOS host. `nixosModulesDir` wins on a name clash.";
    };
    homeManagerModulesDir = dirOption "The same for Home Manager: imported for every user, exported as `homeModules`.";
    extraHomeManagerModules = mkOption {
      type = moduleSet;
      default = {};
      description = "More Home Manager modules by name, e.g. another flake's `homeModules`, imported for every user. `homeManagerModulesDir` wins on a name clash.";
    };
    darwinModulesDir = dirOption "The same for nix-darwin: imported into every Mac host, exported as `darwinModules`.";
    extraDarwinModules = mkOption {
      type = moduleSet;
      default = {};
      description = "More nix-darwin modules by name, e.g. another flake's `darwinModules`, imported into every Mac host. `darwinModulesDir` wins on a name clash.";
    };
    overlaysDir = dirOption "Overlays for every host, home and package build: one per `.nix` file, or a file or `default.nix` returning a list.";
    packagesDir = dirOption "Packages in `callPackage` form, one per `.nix` file: `pkgs.<name>` everywhere, `packages.<system>.<name>`, and the shareable `overlays.packages`.";
    secretsPath = dirOption "sops-nix secrets directory: `users/<name>.yaml` holds a user's `hashed-password`, and `<host>.yaml` is the host's default sops file.";
    defaultSystem = mkOption {
      type = types.str;
      default = "x86_64-linux";
      description = "System for hosts and users not listed in `hostSystems` / `userSystems`.";
    };
    hostSystems = mkOption {
      type = types.attrsOf types.str;
      default = {};
      example = {
        rpi = "aarch64-linux";
        macbook = "aarch64-darwin";
      };
      description = "Per-host system. A `-darwin` system makes the host a Mac, built with nix-darwin. Unknown host names are an error.";
    };
    userSystems = mkOption {
      type = types.attrsOf types.str;
      default = {};
      example = {alice = "aarch64-darwin";};
      description = "Per-user system for standalone `homeConfigurations`. Unknown user names are an error.";
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
      description = "Per-host input overrides, merged over the flake's inputs for that host only: its `nixosSystem` or `darwinSystem`, the auto-wired Home Manager and sops-nix modules, and its `inputs` argument. Unknown host names are an error.";
    };
    userInputs = mkOption {
      type = types.attrsOf (types.lazyAttrsOf types.raw);
      default = {};
      description = "The same as `hostInputs`, for standalone `homeConfigurations`.";
    };
    allowUnfree = mkOption {
      type = types.bool;
      default = false;
      description = "Allow unfree packages on every host, home and package build, and in `perSystem` pkgs. A single host can opt in with `nixpkgs.config.allowUnfree` instead.";
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
