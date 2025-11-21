# OmniNix NixOS configuration builder
#
# Receives the extended-lib fixpoint `final` (for version-agnostic helpers).
# The flake `inputs` used to BUILD configs are a per-call argument (the
# consumer's), so their nixpkgs/home-manager/etc. drive the result.
{final}: {
  # Build NixOS system configurations for multiple hosts
  #
  # Type: { ... } -> AttrSet
  #
  # This is the core function that creates NixOS system configurations
  # for all hosts using the OmniNix framework. It handles multi-architecture
  # builds, optional dependencies, and module composition.
  #
  # Parameters:
  #   inputs              - (required) Flake inputs used to build configs
  #   hosts               - (required) AttrSet of { hostName = hostPath }
  #   defaultSystem       - Default system architecture ("x86_64-linux")
  #   roles               - AttrSet of role modules
  #   users               - AttrSet of user configurations
  #   profiles            - AttrSet of user profile modules
  #   homeManagerModules  - AttrSet of Home Manager modules
  #   nixosModules        - AttrSet of NixOS modules
  #   overlays            - List of Nixpkgs overlays
  #   extraModules        - List of additional modules to include
  #   specialArgs         - Additional arguments passed to modules
  #   secretsPath         - Path to sops secrets file (or null)
  #   omninixNixosModule    - Path to OmniNix NixOS module
  #   debug               - Enable verbose debug output (false)
  #
  # Returns:
  #   AttrSet of { hostName = nixosSystem }
  #
  # Features:
  #   - Per-host system architecture via omninix.system
  #   - Pkgs caching per architecture for performance
  #   - Optional dependency detection (home-manager, disko, etc.)
  #   - Automatic module composition
  #   - Debug tracing when enabled
  #
  # Example:
  #   mkNixosConfigurations {
  #     hosts = { laptop = ./hosts/laptop.nix; };
  #     roles = { desktop = ./roles/desktop.nix; };
  #     users = { alice = ./users/alice; };
  #     secretsPath = ./secrets.yaml;
  #     debug = true;  # Enable debug output
  #   }
  mkNixosConfigurations = {
    inputs,
    hosts,
    defaultSystem ? "x86_64-linux",
    # Per-host architecture override, e.g. { laptop = "aarch64-linux"; }. Hosts
    # not listed use defaultSystem. Host files are NixOS modules (functions), so
    # the system cannot be read from the file — it comes from this explicit map.
    hostSystems ? {},
    roles ? {},
    users ? {},
    profiles ? {},
    homeManagerModules ? {},
    nixosModules ? {},
    overlays ? [],
    # Allow unfree packages system-wide. Defaults to false (free software by
    # default); set allowUnfree = true in mkFlake to opt in.
    allowUnfree ? false,
    extraModules ? [],
    specialArgs ? {},
    secretsPath ? null,
    omninixNixosModule ? ../modules/nixos,
    debug ? false,
  }: let
    debugTrace = final.omninix.mkDebugTrace debug;
  in
    debugTrace "Building ${toString (builtins.length (builtins.attrNames hosts))} host(s)" (
      final.mapAttrs (
        hostName: hostPath: let
          # Per-host architecture from the explicit hostSystems map; hosts not
          # listed fall back to defaultSystem.
          system = let
            s = hostSystems.${hostName} or defaultSystem;
          in
            debugTrace "  ${hostName}: system ${s}" s;
        in
          # Use the CONSUMER's nixpkgs to build the system (eval-config +
          # modules come from their pinned nixpkgs, not OmniNix's).
          inputs.nixpkgs.lib.nixosSystem {
            inherit system;

            # Special arguments passed to all modules
            # These become available as function parameters in modules
            specialArgs =
              {
                inherit inputs hostName users profiles homeManagerModules secretsPath;
                # Shared helper so the NixOS home-manager.users.<name>
                # imports come from the same source as standalone configs.
                mkHomeModules = final.omninix.mkHomeModules;
              }
              // specialArgs;

            # Module composition: base + optional + user modules
            modules = let
              # Nixpkgs configuration module (overlays and config)
              nixpkgsModule = {
                nixpkgs.overlays = overlays;
                nixpkgs.config.allowUnfree = allowUnfree;
              };

              # Base required modules for OmniNix framework. The host file is a
              # standard NixOS module imported directly; the OmniNix NixOS module
              # provides the omninix.* options (hostUsers, persistence, ...).
              #
              # NOTE: the OmniNix home module is NOT imported here — it is a
              # Home Manager module and is brought in per-user via mkHomeModules
              # (modules/nixos). Importing it at the NixOS level would put
              # HM-only config (e.g. home.persistence, osConfig) in the wrong
              # scope.
              baseModules = [
                nixpkgsModule
                hostPath
                (import omninixNixosModule)
              ];

              # Foundational modules auto-wire when their input is present
              # (home-manager and sops-nix underpin the rest of the framework).
              # Anything else (impermanence, disko, stylix, …) is a plain module
              # the consumer imports themselves in a host/role/profile — there is
              # no blessed-integration list to maintain.
              optionalInputModules =
                (final.optional (inputs ? home-manager) inputs.home-manager.nixosModules.home-manager)
                ++ (final.optional (inputs ? sops-nix) inputs.sops-nix.nixosModules.sops);

              # User-provided modules from framework: roles, custom NixOS
              # modules, and extra modules.
              userModules =
                (final.attrValues nixosModules)
                ++ (final.attrValues roles)
                ++ extraModules;

              allModules = baseModules ++ optionalInputModules ++ userModules;
            in
              # Trace threaded through the returned value so it actually fires
              # under debug (a bare `_ = debugTrace ...` binding never evaluates).
              debugTrace "  ${hostName}: ${toString (builtins.length allModules)} module(s) (${toString (builtins.length userModules)} user, ${toString (builtins.length (final.attrValues roles))} role)" allModules;
          }
      )
      hosts
    );
}
