# OmniNix's flake-parts module (flakeModules.default): point omninix.*Dir at
# your directories and get your fleet.
#
# Three steps: discover the directories into pieces, hand pieces and the
# other options to the builders as settings (lib/fleet.nix), export your own
# pieces.
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
  defaults = omninixLib.fleetDefaults;

  # --- 1. directories -> pieces ---------------------------------------------

  # Unset directories (null) are simply empty.
  plain = lib.mapAttrs (_: omninixLib.discoverNixFiles ["default.nix"]) {
    hosts = cfg.hostsDir;
    users = cfg.usersDir;
    packages = cfg.packagesDir;
    overlays = cfg.overlaysDir;
  };

  # Shareable pieces, as { all; exportable; }: their internal/ subdirectory
  # is used here (`all`) but never exported (`exportable`).
  shareable =
    lib.mapAttrs (_: omninixLib.discoverPieces ["default.nix"]) {
      profiles = cfg.profilesDir;
      nixosModules = cfg.nixosModulesDir;
      darwinModules = cfg.darwinModulesDir;
      homeModules = cfg.homeModulesDir;
    }
    # A role directory may hold only a darwin half.
    // {roles = omninixLib.discoverPieces ["default.nix" "darwin.nix"] cfg.rolesDir;};

  # --- 2. pieces + options -> settings ----------------------------------------

  settings =
    {inherit inputs;}
    // plain
    // lib.mapAttrs (_: pieces: pieces.all) shareable
    // {
      inherit
        (cfg)
        extraRoles
        extraProfiles
        extraNixosModules
        extraDarwinModules
        extraHomeModules
        secretsPath
        allowUnfree
        defaultSystem
        hostSystems
        userSystems
        hostInputs
        userInputs
        ;
    };
  fleet = omninixLib.mkFleet settings;

  # --- options ----------------------------------------------------------------

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

  inputsOption = what:
    lib.mkOption {
      # lazyAttrsOf raw: inputs are passed through untouched, and only read
      # when used.
      type = lib.types.attrsOf (lib.types.lazyAttrsOf lib.types.raw);
      default = {};
      example = lib.literalExpression "{ pi.nixpkgs = inputs.nixpkgs-unstable; }";
      description = "Per-${what} flake inputs, merged over the flake's own for that ${what} only (its nixpkgs, Home Manager and `inputs` argument). Unknown names are an error.";
    };

  # Another flake's pieces, by name: paths or modules, passed through as is.
  extraOption = what: example:
    lib.mkOption {
      type = lib.types.attrsOf (lib.types.addCheck lib.types.raw (v: builtins.isPath v || builtins.isString v || builtins.isFunction v || builtins.isAttrs v));
      default = {};
      example = lib.literalExpression example;
      description = "More ${what} by name, e.g. from another flake. Yours win a name clash. Used here, never exported.";
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
    secretsPath = dirOption "sops-nix secrets: `users/<user>.yaml` (key `hashed-password`) is that user's password and their default sops file in Home Manager; `<host>.yaml` is the host's default sops file. Needs a sops-nix input.";

    allowUnfree = lib.mkOption {
      type = lib.types.bool;
      default = defaults.allowUnfree;
      description = "Allow unfree packages on every host and home and in perSystem pkgs. A single host can set nixpkgs.config.allowUnfree itself instead.";
    };
    defaultSystem = lib.mkOption {
      type = lib.types.str;
      default = defaults.defaultSystem;
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

  # --- 3. outputs -----------------------------------------------------------------

  config.flake = lib.mkMerge [
    {
      nixosConfigurations = omninixLib.mkNixosConfigurations settings;

      # mkDefault per entry: nixosModules is typed by flake-parts, and its
      # entries merge. A flake's own entry of the same name should replace
      # ours, not merge with it.
      nixosModules = lib.mapAttrs (_: lib.mkDefault) shareable.nixosModules.exportable;
    }

    # Only when there is something to put there, so a flake doesn't get
    # empty outputs it might define itself.
    (lib.mkIf (fleet.users != {}) {homeConfigurations = omninixLib.mkHomeConfigurations settings;})
    (lib.mkIf (fleet.darwinHosts != {}) {darwinConfigurations = omninixLib.mkDarwinConfigurations settings;})
    # Exports: our own pieces, never internal/ or extra* (re-exporting
    # another flake's pieces would pin them at our version).
    (lib.mkIf (shareable.roles.exportable != {}) {roles = shareable.roles.exportable;})
    (lib.mkIf (shareable.profiles.exportable != {}) {profiles = shareable.profiles.exportable;})
    (lib.mkIf (shareable.darwinModules.exportable != {}) {darwinModules = shareable.darwinModules.exportable;})
    (lib.mkIf (shareable.homeModules.exportable != {}) {homeModules = shareable.homeModules.exportable;})
    # mkDefault: a flake's own overlays.packages replaces ours.
    (lib.mkIf (fleet.packages != {}) {overlays.packages = lib.mkDefault (omninixLib.exportOverlay fleet.packages);})
  ];

  # perSystem gets the same package set as hosts and homes, so
  # packages.<system> matches what they install. Only when something changes
  # it, and mkDefault, so a flake can still set its own pkgs.
  config.perSystem = {system, ...}: let
    pkgs = import inputs.nixpkgs {
      inherit system;
      inherit (fleet) overlays;
      config.allowUnfree = fleet.allowUnfree;
    };
  in
    lib.mkIf (fleet.overlays != [] || fleet.allowUnfree) {
      _module.args.pkgs = lib.mkDefault pkgs;
      packages = lib.mapAttrs (_: lib.mkDefault) (omninixLib.packagesFor fleet.packages pkgs);
    };
}
