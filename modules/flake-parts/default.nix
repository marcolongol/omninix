# OmniNix's flake-parts module (flakeModules.default): point omninix.*Dir at
# your directories and get your fleet.
#
# Applied with importApply, so `omninixLib` (our lib.omninix) arrives by
# closure: inside a consumer's flake, `lib` and `inputs` are theirs.
{omninixLib}: {
  config,
  lib,
  inputs,
  ...
}: let
  cfg = config.omninix;

  # A directory's pieces, or {} when it isn't set.
  discover = dir:
    if dir == null
    then {}
    else omninixLib.discoverNixFiles ["default.nix"] dir;

  # A directory of shareable pieces, with its internal/: `all` is used here,
  # `exportable` is exported.
  discoverPiecesWith = markers: dir:
    if dir == null
    then {
      all = {};
      exportable = {};
    }
    else omninixLib.discoverPieces markers dir;
  discoverPieces = discoverPiecesWith ["default.nix"];

  hosts = discover cfg.hostsDir;
  users = discover cfg.usersDir;

  # A role directory may hold only a darwin half.
  ownRoles = discoverPiecesWith ["default.nix" "darwin.nix"] cfg.rolesDir;
  ownProfiles = discoverPieces cfg.profilesDir;
  ownNixosModules = discoverPieces cfg.nixosModulesDir;
  ownDarwinModules = discoverPieces cfg.darwinModulesDir;
  ownHomeModules = discoverPieces cfg.homeModulesDir;

  # Ours plus the extras, ours winning a clash. Roles merge whole, by name,
  # and only then split into halves, so a host never mixes halves from two
  # flakes. Borrowed roles and profiles can't read our `inputs` (borrow).
  ownRoleHalves = omninixLib.splitRoles ownRoles.all;
  extraRoleHalves = omninixLib.splitRoles (omninixLib.newExtras "roles" ownRoles.all cfg.extraRoles);
  borrowAll = kind: lib.mapAttrs (omninixLib.borrow kind);
  roleHalves = {
    nixos = ownRoleHalves.nixos // borrowAll "roles" extraRoleHalves.nixos;
    darwin = ownRoleHalves.darwin // borrowAll "roles" extraRoleHalves.darwin;
  };
  profiles = omninixLib.withExtras "profiles" ownProfiles.all (borrowAll "profiles" cfg.extraProfiles);
  nixosModules = omninixLib.withExtras "nixosModules" ownNixosModules.all cfg.extraNixosModules;
  darwinModules = omninixLib.withExtras "darwinModules" ownDarwinModules.all cfg.extraDarwinModules;
  homeModules = omninixLib.withExtras "homeModules" ownHomeModules.all cfg.extraHomeModules;

  # A host is a Mac when its system is darwin. Each builder sees only its
  # own hosts' entries in the per-host maps; typos are caught across all
  # hosts first (see config.flake).
  isDarwin = name: lib.hasSuffix "-darwin" (cfg.hostSystems.${name} or cfg.defaultSystem);
  darwinHosts = lib.filterAttrs (name: _: isDarwin name) hosts;
  nixosHosts = lib.filterAttrs (name: _: !(isDarwin name)) hosts;
  onlyFor = someHosts: lib.filterAttrs (name: _: someHosts ? ${name});
  packages = discover cfg.packagesDir;

  # One package set everywhere: the packages, then overlaysDir in name order.
  overlays = omninixLib.allOverlays {
    inherit inputs packages;
    overlays = discover cfg.overlaysDir;
  };
  changesPkgs = overlays != [] || cfg.allowUnfree;
  nixpkgsArgs = {
    inherit overlays;
    inherit (cfg) allowUnfree;
  };

  # Every host imports its platform's role halves and always-on modules;
  # every home the profiles and the always-on home modules.
  sharedHomeModules = lib.attrValues profiles ++ lib.attrValues homeModules;

  # What both builders get.
  hostArgs = someHosts: {
    inherit inputs users sharedHomeModules;
    inherit (cfg) defaultSystem secretsPath allowUnfree;
    inherit (nixpkgsArgs) overlays;
    hosts = someHosts;
    hostSystems = onlyFor someHosts cfg.hostSystems;
    hostInputs = onlyFor someHosts cfg.hostInputs;
  };

  dirOption = description:
    lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      inherit description;
    };

  systemsOption = what:
    lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      example = {pi = "aarch64-linux";};
      description = "Per-${what} system, overriding defaultSystem. Unknown names are an error.";
    };

  # Another flake's pieces, by name: paths or modules, passed through as is.
  extraOption = what: example:
    lib.mkOption {
      type = lib.types.attrsOf (lib.types.addCheck lib.types.raw (v: builtins.isPath v || builtins.isString v || builtins.isFunction v || builtins.isAttrs v));
      default = {};
      example = lib.literalExpression example;
      description = "More ${what} by name, e.g. from another flake. Yours win a name clash. Used here, never exported.";
    };

  inputsOption = what:
    lib.mkOption {
      # lazyAttrsOf raw: inputs are passed through untouched, and only read
      # when used.
      type = lib.types.attrsOf (lib.types.lazyAttrsOf lib.types.raw);
      default = {};
      example = lib.literalExpression "{ pi.nixpkgs = inputs.nixpkgs-unstable; }";
      description = "Per-${what} flake inputs, merged over the flake's own for that ${what} only (its nixpkgs, Home Manager and `inputs` argument). Unknown names are an error.";
    };
in {
  options.omninix = {
    hostsDir = dirOption "Hosts: each `<name>.nix` or `<name>/default.nix` becomes nixosConfigurations.<name>, or darwinConfigurations.<name> when its system (hostSystems) is darwin.";
    usersDir = dirOption "Users (Home Manager modules): the home of `<name>` on every host enabling them, and homeConfigurations.<name>.";
    rolesDir = dirOption "Roles: modules every host imports, each off until a host sets roles.<name>.enable. A file, or a directory's default.nix, is for NixOS hosts; a directory's darwin.nix is for Macs. Exported as `roles`.";
    profilesDir = dirOption "Profiles: Home Manager modules every home imports, each off until a user sets profiles.<name>.enable. Exported as `profiles`.";
    nixosModulesDir = dirOption "Always-on NixOS modules every host imports. Exported as `nixosModules`.";
    darwinModulesDir = dirOption "Always-on nix-darwin modules every Mac imports. Exported as `darwinModules`.";
    homeModulesDir = dirOption "Always-on Home Manager modules every home imports. Exported as `homeModules`.";
    packagesDir = dirOption "Packages, one `callPackage` file each (a package asking for `inputs` gets the flake's): pkgs.<name> on every host and home, packages.<system>.<name>, and the shareable overlays.packages.";
    overlaysDir = dirOption "Overlays, one per file, applied in name order after the packages (so they can override them) on every host and home and in perSystem pkgs.";
    allowUnfree = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow unfree packages on every host and home and in perSystem pkgs. A single host can set nixpkgs.config.allowUnfree itself instead.";
    };
    secretsPath = dirOption "sops-nix secrets: `users/<user>.yaml` (key `hashed-password`) is that user's password and their default sops file in Home Manager; `<host>.yaml` is the host's default sops file. Needs a sops-nix input.";

    defaultSystem = lib.mkOption {
      type = lib.types.str;
      default = "x86_64-linux";
      description = "System for hosts and users not listed in hostSystems / userSystems.";
    };
    hostSystems = systemsOption "host";
    userSystems = systemsOption "user";
    hostInputs = inputsOption "host";
    userInputs = inputsOption "user";

    extraRoles =
      extraOption "roles (a role given as a module, not a path, has no darwin half and reaches NixOS hosts only)"
      "{ inherit (their-config.roles) desktop; }";
    extraProfiles = extraOption "profiles" "{ inherit (their-config.profiles) developer; }";
    extraNixosModules = extraOption "always-on NixOS modules" "{ disko = inputs.disko.nixosModules.disko; }";
    extraDarwinModules = extraOption "always-on nix-darwin modules" "{ inherit (their-config.darwinModules) dock; }";
    extraHomeModules = extraOption "always-on Home Manager modules" "{ nixievim = inputs.nixievim.homeManagerModules.default; }";
  };

  config.flake = lib.mkMerge [
    {
      nixosConfigurations =
        omninixLib.withKnownNames "host" hosts {inherit (cfg) hostSystems hostInputs;}
        (omninixLib.mkNixosConfigurations (hostArgs nixosHosts
            // {sharedModules = lib.attrValues roleHalves.nixos ++ lib.attrValues nixosModules;}));

      # Exports: our own pieces, never internal/ or extra* (re-exporting another
      # flake's pieces would pin them at our version).
      roles = ownRoles.exportable;
      profiles = ownProfiles.exportable;

      # mkDefault per entry: nixosModules is typed by flake-parts, and its
      # entries merge. A flake's own entry of the same name should replace
      # ours, not merge with it.
      nixosModules = lib.mapAttrs (_: lib.mkDefault) ownNixosModules.exportable;
    }

    # Only when there is something to put there, so a flake without users or
    # home modules doesn't get empty outputs it might define itself.
    (lib.mkIf (users != {}) {
      homeConfigurations = omninixLib.mkHomeConfigurations {
        inherit inputs users sharedHomeModules;
        inherit (cfg) defaultSystem userSystems userInputs secretsPath;
        inherit (nixpkgsArgs) overlays allowUnfree;
      };
    })
    (lib.mkIf (darwinHosts != {}) {
      darwinConfigurations =
        omninixLib.withKnownNames "host" hosts {inherit (cfg) hostSystems hostInputs;}
        (omninixLib.mkDarwinConfigurations (hostArgs darwinHosts
            // {sharedModules = lib.attrValues roleHalves.darwin ++ lib.attrValues darwinModules;}));
    })
    (lib.mkIf (ownDarwinModules.exportable != {}) {darwinModules = ownDarwinModules.exportable;})
    (lib.mkIf (ownHomeModules.exportable != {}) {homeModules = ownHomeModules.exportable;})

    # mkDefault: a flake's own overlays.packages replaces ours.
    (lib.mkIf (packages != {}) {
      overlays.packages = lib.mkDefault (omninixLib.exportOverlay packages);
    })
  ];

  # perSystem gets the same package set as hosts and homes, so
  # packages.<system> matches what they install. Only when something
  # changes it, and mkDefault, so a flake can still set its own pkgs.
  config.perSystem = {system, ...}: let
    pkgs = import inputs.nixpkgs {
      inherit system;
      inherit (nixpkgsArgs) overlays;
      config.allowUnfree = cfg.allowUnfree;
    };
  in
    lib.mkIf changesPkgs {
      _module.args.pkgs = lib.mkDefault pkgs;
      packages = lib.mapAttrs (_: lib.mkDefault) (omninixLib.packagesFor packages pkgs);
    };
}
