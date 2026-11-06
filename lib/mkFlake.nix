# OmniNix high-level flake builder
#
# Receives the extended-lib fixpoint `final`. (mkFlake takes the consumer's
# `inputs` as its own first argument.)
{final}: {
  # High-level flake builder with auto-discovery
  #
  # Type: Inputs -> { ... } -> { nixosConfigurations :: AttrSet, homeConfigurations :: AttrSet }
  #
  # This is the main entry point for OmniNix. It automatically discovers
  # hosts, roles, users, and profiles from directories and creates a
  # complete flake output with all NixOS configurations, plus standalone
  # Home Manager configurations (one per discovered user) for non-NixOS
  # machines.
  #
  # Parameters:
  #   inputs                  - Flake inputs (first parameter, curried)
  #   hostsDir                - Path to hosts directory (optional; without it
  #                             there are no nixosConfigurations)
  #   rolesDir                - Path to roles directory (optional)
  #   extraRoles              - Roles merged with rolesDir; local wins ({})
  #   usersDir                - Path to users directory (optional)
  #   profilesDir             - Path to profiles directory (optional)
  #   extraProfiles           - Profiles merged with profilesDir; local wins ({})
  #   nixosModulesDir         - Path to NixOS modules directory (optional)
  #   extraNixosModules       - NixOS modules merged with nixosModulesDir; local wins ({})
  #   homeManagerModulesDir   - Path to Home Manager modules directory (optional)
  #   extraHomeManagerModules - HM modules merged with homeManagerModulesDir; local wins ({})
  #   overlaysDir             - Overlays: one per .nix file, or a file/default.nix returning a list (optional)
  #   packagesDir             - Packages exposed as pkgs.<name> and packages.<system>.<name> (optional)
  #   secretsPath             - Path to sops secrets file (optional)
  #   defaultSystem           - Default system architecture ("x86_64-linux")
  #   hostSystems             - Per-host system override ({})
  #   userSystems             - Per-user system override for homeConfigurations ({})
  #   hostInputs              - Per-host input overrides, e.g. a host on unstable ({})
  #   userInputs              - Per-user input overrides for homeConfigurations ({})
  #   systems                 - Systems to emit packages for ([defaultSystem])
  #   allowUnfree             - Allow unfree packages (false)
  #   debug                   - Enable verbose debug output (false)
  #
  # Returns:
  #   {
  #     nixosConfigurations = { hostName = nixosSystem; ... };
  #     homeConfigurations  = { userName = homeManagerConfiguration; ... };
  #     hosts, users        = discovered attrsets;
  #     roles, profiles, nixosModules, homeModules
  #                         = this flake's own entries, without `internal/` ones
  #                           and without extra* (so they can be shared);
  #     packages.<system>   = ...;  # only when packagesDir is set
  #     overlays.packages   = packagesDir as an add-only overlay (same condition)
  #   }
  #
  # Features:
  #   - Auto-discovers .nix files in all directories
  #   - `internal/` in roles, profiles and module dirs: used here, never exported
  #   - Warns about missing directories
  #   - Ensures at least one host exists when hostsDir is given
  #   - Debug tracing when enabled
  #
  # Example:
  #   outputs = { self, nixpkgs, omninix, ... }@inputs:
  #     omninix.lib.omninix.mkFlake inputs {
  #       hostsDir = ./hosts;
  #       rolesDir = ./roles;
  #       usersDir = ./users;
  #       profilesDir = ./profiles;
  #       secretsPath = ./secrets.yaml;
  #       debug = true;  # Enable debug output
  #     };
  mkFlake = inputs: {
    hostsDir ? null,
    rolesDir ? null,
    extraRoles ? {},
    usersDir ? null,
    profilesDir ? null,
    extraProfiles ? {},
    nixosModulesDir ? null,
    extraNixosModules ? {},
    homeManagerModulesDir ? null,
    extraHomeManagerModules ? {},
    overlaysDir ? null,
    packagesDir ? null,
    secretsPath ? null,
    defaultSystem ? "x86_64-linux",
    # Per-host architecture override for nixosConfigurations,
    # e.g. { laptop = "aarch64-linux"; }. Hosts not listed use defaultSystem.
    hostSystems ? {},
    systems ? [defaultSystem],
    # Per-user system override for standalone homeConfigurations,
    # e.g. { alice = "aarch64-darwin"; }. Users not listed use defaultSystem.
    userSystems ? {},
    # Per-host / per-user input overrides, e.g.
    # { rpi = { nixpkgs = inputs.nixpkgs-unstable; home-manager = …; }; }.
    hostInputs ? {},
    userInputs ? {},
    # Allow unfree packages. Defaults to false (free software by default);
    # set true to opt the whole flake (NixOS + HM + packages) into unfree.
    allowUnfree ? false,
    debug ? false,
  }: let
    core = final.omninix.mkFlakeCore inputs {
      inherit
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
        hostInputs
        userInputs
        allowUnfree
        debug
        ;
    };
  in
    assert final.omninix.assertAllStrings "systems" systems;
      core.outputs
      # Auto-discovered packages: packages.<system>.<name>, read from the same
      # overlaid pkgs the hosts use. Only emitted when packagesDir is provided.
      // final.optionalAttrs core.hasPackages {
        inherit (core) overlays;
        packages = final.genAttrs systems (system: core.packagesOf (core.pkgsFor system));
      };

  # Engine shared by mkFlake and flakeModules.default. Internal, unstable shape.
  mkFlakeCore = inputs: {
    hostsDir,
    rolesDir,
    extraRoles,
    usersDir,
    profilesDir,
    extraProfiles,
    nixosModulesDir,
    extraNixosModules,
    homeManagerModulesDir,
    extraHomeManagerModules,
    overlaysDir,
    packagesDir,
    secretsPath,
    defaultSystem,
    hostSystems,
    userSystems,
    hostInputs,
    userInputs,
    allowUnfree,
    debug,
  }: let
    debugTrace = final.omninix.mkDebugTrace debug;
    inherit (final.omninix) validateOptionalPath;

    # Run validation on all input paths; missing directories produce warnings.
    # hostsDir is optional too, so a flake can hold only users (standalone
    # homeConfigurations) or only roles/profiles for other fleets to import.
    validatedHostsDir = validateOptionalPath "hostsDir" hostsDir;
    validatedRolesDir = validateOptionalPath "rolesDir" rolesDir;
    validatedUsersDir = validateOptionalPath "usersDir" usersDir;
    validatedProfilesDir = validateOptionalPath "profilesDir" profilesDir;
    validatedNixosModulesDir = validateOptionalPath "nixosModulesDir" nixosModulesDir;
    validatedHomeManagerModulesDir = validateOptionalPath "homeManagerModulesDir" homeManagerModulesDir;
    validatedOverlaysDir = validateOptionalPath "overlaysDir" overlaysDir;
    validatedPackagesDir = validateOptionalPath "packagesDir" packagesDir;
    validatedSecretsPath = validateOptionalPath "secretsPath" secretsPath;
  in let
    # Auto-discover all .nix files in provided directories. Hosts and users
    # are plain scans; roles, profiles and module dirs also pick up their
    # `internal/` subdir (discoverPieces): used here, never exported.
    pieces = final.mapAttrs (_: final.omninix.discoverPieces) (
      final.optionalAttrs (validatedRolesDir != null) {roles = validatedRolesDir;}
      // final.optionalAttrs (validatedProfilesDir != null) {profiles = validatedProfilesDir;}
      // final.optionalAttrs (validatedNixosModulesDir != null) {nixosModules = validatedNixosModulesDir;}
      // final.optionalAttrs (validatedHomeManagerModulesDir != null) {homeManagerModules = validatedHomeManagerModulesDir;}
    );

    # This flake's own entries minus internal/: what it exports for sharing.
    # Never includes extra* (re-exporting another flake's pieces would pin
    # them at this flake's version and define them twice for consumers).
    exportable = final.mapAttrs (_: p: p.exportable) pieces;

    dirs = let
      discovered = debugTrace "Scanning directories for .nix files..." (
        final.omninix.mkDirMap (
          final.optionalAttrs (validatedHostsDir != null) {hosts = validatedHostsDir;}
          // final.optionalAttrs (validatedUsersDir != null) {users = validatedUsersDir;}
        )
        // final.mapAttrs (_: p: p.all) pieces
      );

      # Merge discovered entries with their extra* counterpart. LOCAL WINS:
      # your own directory overrides imported extras on name collision
      # (warned). A role's enable option name is baked into its file, so only
      # one file per name may be imported — cherry-pick a library with
      # `inherit (omninix.roles) ...` or `builtins.removeAttrs` (or
      # omninix.lib.omninix.pick/drop) to avoid overlaps.
      withExtra = kind: extra: let
        local = discovered.${kind} or {};
        collisions = builtins.attrNames (builtins.intersectAttrs local extra);
      in
        final.warnIf (collisions != [])
        "OmniNix: local ${kind} override extra ${kind} for: ${toString collisions}"
        (extra // local);

      # A role or profile from another flake that asks for `inputs` (or another
      # OmniNix extra) would silently get *this* flake's value. Give it one
      # that throws a readable error instead. Pieces that ask for none of them
      # pass through untouched (same identity, so imports still dedup).
      borrow = kind: name: piece: let
        mod =
          if builtins.isPath piece || builtins.isString piece
          then import piece
          else piece;
        args = final.optionalAttrs (builtins.isFunction mod) (final.functionArgs mod);
        poisoned = final.genAttrs (builtins.filter (a: args ? ${a}) ["inputs" "secretsPath" "hostName" "users" "profiles" "homeManagerModules" "mkHomeModules"]) (
          a:
            throw ''
              OmniNix: ${kind}.${name} comes from another flake and reads `${a}`, which only
              that flake has. It isn't shareable as is (see OmniNix's docs/sharing.md).''
        );
      in
        if poisoned == {}
        then piece
        else let
          id =
            if builtins.isPath piece || builtins.isString piece
            then toString piece
            else "omninix-borrowed-${kind}-${name}";
        in {
          key = id;
          _file = id;
          imports = [(final.setFunctionArgs (a: mod (a // poisoned)) args)];
        };

      mergedRoles = withExtra "roles" (final.mapAttrs (borrow "roles") extraRoles);
      mergedProfiles = withExtra "profiles" (final.mapAttrs (borrow "profiles") extraProfiles);
      mergedNixosModules = withExtra "nixosModules" extraNixosModules;
      mergedHomeManagerModules = withExtra "homeManagerModules" extraHomeManagerModules;

      result =
        discovered
        // {
          hosts = discovered.hosts or {};
          roles = mergedRoles;
          profiles = mergedProfiles;
          nixosModules = mergedNixosModules;
          homeManagerModules = mergedHomeManagerModules;
        };
    in
      # Emit discovery traces by threading them through the result so they
      # actually fire when debug is enabled. A bare `_N = debugTrace ...` let
      # binding is never referenced, so Nix's laziness means it never evaluates.
      builtins.foldl' (acc: msg: debugTrace msg acc) result [
        "Discovery results:"
        "  Hosts: ${toString (builtins.attrNames (discovered.hosts or {}))}"
        "  Roles (discovered): ${toString (builtins.attrNames (discovered.roles or {}))}"
        "  Roles (extra): ${toString (builtins.attrNames extraRoles)}"
        "  Roles (merged): ${toString (builtins.attrNames mergedRoles)}"
        "  Users: ${toString (builtins.attrNames (discovered.users or {}))}"
        "  Profiles (discovered): ${toString (builtins.attrNames (discovered.profiles or {}))}"
        "  Profiles (extra): ${toString (builtins.attrNames extraProfiles)}"
        "  Profiles (merged): ${toString (builtins.attrNames mergedProfiles)}"
        "  NixOS Modules (merged): ${toString (builtins.attrNames mergedNixosModules)}"
        "  Home Manager Modules (merged): ${toString (builtins.attrNames mergedHomeManagerModules)}"
        "  Exported: ${toString (final.mapAttrsToList (k: v: "${k}=[${toString (builtins.attrNames v)}]") exportable)}"
      ];

    # Overlays from overlaysDir: one overlay per discovered .nix file, or the
    # list a file / default.nix returns (see loadOverlays).
    userOverlays =
      if validatedOverlaysDir != null
      then debugTrace "Loading overlays from ${toString validatedOverlaysDir}" (final.omninix.loadOverlays validatedOverlaysDir)
      else [];

    # packagesDir packages, keyed by file name. Names come from readDir, not
    # from pkgs, so the overlay below cannot recurse.
    discoveredPackages =
      if validatedPackagesDir != null
      then final.omninix.forAllNixFiles validatedPackagesDir (fn: fn)
      else {};

    # Expose packagesDir as pkgs.<name> on hosts, home configs and package
    # builds. Applied first so overlaysDir can still override them. A package
    # that takes `inputs` gets the consumer's flake inputs (self included);
    # only requested args are passed, since callPackage rejects unknown ones.
    packagesOverlay = pfinal: _:
      final.mapAttrs (
        _: path:
          pfinal.callPackage path (builtins.intersectAttrs (final.functionArgs (import path)) {inherit inputs;})
      )
      discoveredPackages;

    overlays = final.optional (discoveredPackages != {}) packagesOverlay ++ userOverlays;

    # Exported overlays.packages: packagesDir only (never overlaysDir, whose
    # overrides would rebuild other people's packages), add-only, and per
    # attribute so one unshareable package doesn't break the others.
    exportPackages = pkgsFinal: pkgsPrev:
      final.mapAttrs (
        name: path:
          if pkgsPrev ? ${name}
          then throw "OmniNix: overlays.packages: `${name}` would replace an existing package"
          else if (final.functionArgs (import path)) ? inputs
          then throw "OmniNix: overlays.packages: `${name}` takes `inputs`, which only this flake has"
          else pkgsFinal.callPackage path {}
      )
      discoveredPackages;
    # `nix flake check` requires the overlay's arguments to be named final/prev.
    packagesExportOverlay = final: prev: exportPackages final prev;

    pkgsFor = system:
      import inputs.nixpkgs {
        inherit system overlays;
        config.allowUnfree = allowUnfree;
      };

    # Args shared by both builders, so the discovered directories and
    # global settings are spelled out once. Each builder adds its own
    # specifics on top (hosts/roles/nixosModules for NixOS). `inputs` is the
    # consumer's, so their nixpkgs/home-manager/etc. build the configs.
    sharedArgs = {
      inherit inputs defaultSystem overlays debug allowUnfree;
      users = dirs.users or {};
      profiles = dirs.profiles or {};
      homeManagerModules = dirs.homeManagerModules or {};
      secretsPath = validatedSecretsPath;
    };
  in
    # Input guards (validations.nix helpers). These run as real `assert`s in
    # front of the result so they actually fire — a bare `_ = assert ...` let
    # binding would never be forced under laziness.
    assert final.omninix.assertIsString "defaultSystem" defaultSystem;
    # An empty hostsDir is almost certainly a mistake; leaving it unset is not.
    assert (validatedHostsDir == null || dirs.hosts != {})
    || throw ''
      OmniNix Error: No hosts found in hostsDir!
      Path: ${toString validatedHostsDir}

      Make sure you have at least one .nix file or directory with default.nix
      in your hosts directory.
    ''; {
      inherit pkgsFor;
      hasPackages = validatedPackagesDir != null;
      # Shareable overlays, emitted with packages (only when packagesDir is set).
      overlays = {packages = packagesExportOverlay;};
      outputs = {
        inherit (dirs) hosts users;
        # Shareable: own entries only, without internal/ or extra*.
        roles = exportable.roles or {};
        profiles = exportable.profiles or {};
        nixosModules = exportable.nixosModules or {};
        homeModules = exportable.homeManagerModules or {};
        # Build all NixOS configurations from discovered files
        nixosConfigurations = debugTrace "Building NixOS configurations..." (
          final.omninix.mkNixosConfigurations (sharedArgs
            // {
              inherit (dirs) hosts;
              inherit hostSystems hostInputs;
              roles = dirs.roles or {};
              nixosModules = dirs.nixosModules or {};
            })
        );
        # Standalone Home Manager configurations from the same users/profiles.
        homeConfigurations = debugTrace "Building home configurations..." (
          final.omninix.mkHomeConfigurations (sharedArgs // {inherit userSystems userInputs;})
        );
      };
      # packagesDir packages read from a pkgsFor result, minus those whose
      # meta.platforms exclude this system (they stay available as pkgs.<name>).
      packagesOf = pkgs:
        debugTrace "Building ${toString (builtins.length (builtins.attrNames discoveredPackages))} package(s) for ${pkgs.stdenv.hostPlatform.system}" (
          final.filterAttrs (_: final.meta.availableOn pkgs.stdenv.hostPlatform) (
            final.mapAttrs (name: _: pkgs.${name}) discoveredPackages
          )
        );
    };
}
