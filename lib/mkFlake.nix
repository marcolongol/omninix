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
  #   hostsDir                - (required) Path to hosts directory
  #   rolesDir                - Path to roles directory (optional)
  #   usersDir                - Path to users directory (optional)
  #   profilesDir             - Path to profiles directory (optional)
  #   nixosModulesDir         - Path to NixOS modules directory (optional)
  #   homeManagerModulesDir   - Path to Home Manager modules directory (optional)
  #   overlaysDir             - Overlays: one per .nix file, or a file/default.nix returning a list (optional)
  #   secretsPath             - Path to sops secrets file (optional)
  #   defaultSystem           - Default system architecture ("x86_64-linux")
  #   debug                   - Enable verbose debug output (false)
  #
  # Returns:
  #   {
  #     nixosConfigurations = { hostName = nixosSystem; ... };
  #     homeConfigurations  = { userName = homeManagerConfiguration; ... };
  #   }
  #
  # Features:
  #   - Auto-discovers .nix files in all directories
  #   - Validates required directories exist
  #   - Warns about missing optional directories
  #   - Ensures at least one host exists
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
    hostsDir,
    rolesDir ? null,
    extraRoles ? {},
    usersDir ? null,
    profilesDir ? null,
    extraProfiles ? {},
    nixosModulesDir ? null,
    homeManagerModulesDir ? null,
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
  in
    assert final.omninix.assertAllStrings "systems" systems;
      core.outputs
      # Auto-discovered packages: packages.<system>.<name>, read from the same
      # overlaid pkgs the hosts use. Only emitted when packagesDir is provided.
      // final.optionalAttrs core.hasPackages {
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
    homeManagerModulesDir,
    overlaysDir,
    packagesDir,
    secretsPath,
    defaultSystem,
    hostSystems,
    userSystems,
    allowUnfree,
    debug,
  }: let
    debugTrace = final.omninix.mkDebugTrace debug;
    inherit (final.omninix) validatePath validateOptionalPath;

    # Run validation on all input paths
    # Required paths throw errors, optional paths produce warnings
    validatedHostsDir = validatePath "hostsDir" hostsDir;
    validatedRolesDir = validateOptionalPath "rolesDir" rolesDir;
    validatedUsersDir = validateOptionalPath "usersDir" usersDir;
    validatedProfilesDir = validateOptionalPath "profilesDir" profilesDir;
    validatedNixosModulesDir = validateOptionalPath "nixosModulesDir" nixosModulesDir;
    validatedHomeManagerModulesDir = validateOptionalPath "homeManagerModulesDir" homeManagerModulesDir;
    validatedOverlaysDir = validateOptionalPath "overlaysDir" overlaysDir;
    validatedPackagesDir = validateOptionalPath "packagesDir" packagesDir;
    validatedSecretsPath = validateOptionalPath "secretsPath" secretsPath;
  in let
    # Auto-discover all .nix files in provided directories
    # Uses mkDirMap to scan each directory and build nested attr sets
    # Only includes directories that passed validation (non-null)
    dirs = let
      discovered = debugTrace "Scanning directories for .nix files..." (
        final.omninix.mkDirMap (
          {hosts = validatedHostsDir;}
          // final.optionalAttrs (validatedRolesDir != null) {roles = validatedRolesDir;}
          // final.optionalAttrs (validatedUsersDir != null) {users = validatedUsersDir;}
          // final.optionalAttrs (validatedProfilesDir != null) {profiles = validatedProfilesDir;}
          // final.optionalAttrs (validatedNixosModulesDir != null) {nixosModules = validatedNixosModulesDir;}
          // final.optionalAttrs (validatedHomeManagerModulesDir != null) {homeManagerModules = validatedHomeManagerModulesDir;}
        )
      );

      # Merge discovered roles with extraRoles. LOCAL WINS: your ./roles
      # override imported extraRoles on name collision (warned below). A role's
      # enable option name is baked into its file, so only one file per name may
      # be imported — cherry-pick a library with `inherit (omninix.roles) ...` or
      # `builtins.removeAttrs` (or omninix.lib.omninix.pick/drop) to avoid overlaps.
      roleCollisions = builtins.attrNames (builtins.intersectAttrs (discovered.roles or {}) extraRoles);
      profileCollisions = builtins.attrNames (builtins.intersectAttrs (discovered.profiles or {}) extraProfiles);

      mergedRoles =
        final.warnIf (roleCollisions != [])
        "OmniNix: local ./roles override extraRoles for: ${toString roleCollisions}"
        (extraRoles // (discovered.roles or {}));

      mergedProfiles =
        final.warnIf (profileCollisions != [])
        "OmniNix: local ./profiles override extraProfiles for: ${toString profileCollisions}"
        (extraProfiles // (discovered.profiles or {}));

      result =
        discovered
        // {
          roles = mergedRoles;
          profiles = mergedProfiles;
        };
    in
      # Emit discovery traces by threading them through the result so they
      # actually fire when debug is enabled. A bare `_N = debugTrace ...` let
      # binding is never referenced, so Nix's laziness means it never evaluates
      # (the previous form silently produced no debug output at all).
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
        "  NixOS Modules: ${toString (builtins.attrNames (discovered.nixosModules or {}))}"
        "  Home Manager Modules: ${toString (builtins.attrNames (discovered.homeManagerModules or {}))}"
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
    # builds. Applied first so overlaysDir can still override them.
    packagesOverlay = pfinal: _: final.mapAttrs (_: path: pfinal.callPackage path {}) discoveredPackages;

    overlays = final.optional (discoveredPackages != {}) packagesOverlay ++ userOverlays;

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
    # binding would never be forced under laziness (the previous no-hosts check
    # was silently dead).
    assert final.omninix.assertIsString "defaultSystem" defaultSystem;
    assert (dirs ? hosts && dirs.hosts != {})
    || throw ''
      OmniNix Error: No hosts found in hostsDir!
      Path: ${toString validatedHostsDir}

      Make sure you have at least one .nix file or directory with default.nix
      in your hosts directory.
    ''; {
      inherit pkgsFor;
      hasPackages = validatedPackagesDir != null;
      outputs = {
        inherit (dirs) hosts roles profiles users;
        # Build all NixOS configurations from discovered files
        nixosConfigurations = debugTrace "Building NixOS configurations..." (
          final.omninix.mkNixosConfigurations (sharedArgs
            // {
              inherit (dirs) hosts;
              inherit hostSystems;
              roles = dirs.roles or {};
              nixosModules = dirs.nixosModules or {};
            })
        );
        # Standalone Home Manager configurations from the same users/profiles.
        homeConfigurations = debugTrace "Building home configurations..." (
          final.omninix.mkHomeConfigurations (sharedArgs // {inherit userSystems;})
        );
      };
      # packagesDir packages read from a pkgsFor result.
      packagesOf = pkgs:
        debugTrace "Building ${toString (builtins.length (builtins.attrNames discoveredPackages))} package(s) for ${pkgs.stdenv.hostPlatform.system}" (
          final.mapAttrs (name: _: pkgs.${name}) discoveredPackages
        );
    };
}
