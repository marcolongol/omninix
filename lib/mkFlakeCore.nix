# OmniNix flake engine (internal)
#
# Receives the extended-lib fixpoint `final`. mkFlakeCore discovers the
# directories and builds the outputs; flakeModules.default (modules/flake-parts)
# is its only public entry point, so its shape may change between releases.
{final}: {
  # Takes the consumer's `inputs` and the flakeModules.default settings.
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
    # `internal/` subdir (discoverPieces): used here, never exported. Role
    # directories may hold only a darwin half (discoverRoles).
    pieces = final.mapAttrs (kind:
      if kind == "roles"
      then final.omninix.discoverRoles
      else final.omninix.discoverPieces) (
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

      # Roles merge whole, by name (local wins, as above), and only then split
      # into their NixOS and darwin halves, so a host never mixes halves from
      # two flakes. Each half gets the borrow check on its own.
      roleCollisions = builtins.attrNames (builtins.intersectAttrs (discovered.roles or {}) extraRoles);
      ownRoles = final.omninix.splitRoles (discovered.roles or {});
      extraRoleHalves = final.omninix.splitRoles (builtins.removeAttrs extraRoles roleCollisions);
      mergedRoles =
        final.warnIf (roleCollisions != [])
        "OmniNix: local roles override extra roles for: ${toString roleCollisions}"
        (ownRoles.nixos // final.mapAttrs (borrow "roles") extraRoleHalves.nixos);
      mergedDarwinRoles = ownRoles.darwin // final.mapAttrs (borrow "roles") extraRoleHalves.darwin;
      mergedProfiles = withExtra "profiles" (final.mapAttrs (borrow "profiles") extraProfiles);
      mergedNixosModules = withExtra "nixosModules" extraNixosModules;
      mergedHomeManagerModules = withExtra "homeManagerModules" extraHomeManagerModules;

      result =
        discovered
        // {
          hosts = discovered.hosts or {};
          roles = mergedRoles;
          darwinRoles = mergedDarwinRoles;
          # extraRoles given as modules rather than paths: NixOS only.
          inlineExtraRoles = extraRoleHalves.inline;
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
        "  Roles (darwin halves): ${toString (builtins.attrNames mergedDarwinRoles)}"
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
