# OmniNix standalone Home Manager configuration builder
#
# Receives the extended-lib fixpoint `final` (for generic helpers). The flake
# `inputs` used to build configs are a per-call argument (the consumer's).
{final}: {
  # Build standalone Home Manager configurations
  #
  # Type: { users :: AttrSet, ... } -> { <username> :: HomeConfiguration }
  #
  # Companion to mkNixosConfigurations for machines that already have
  # Home Manager but no NixOS (work laptops, non-NixOS hosts, etc.).
  # Each discovered user becomes a standalone homeConfigurations.<username>
  # output, activatable with `home-manager switch --flake .#<username>`.
  #
  # The per-user module set is identical to the one wired into
  # home-manager.users.<name> in modules/nixos (the OmniNix home module,
  # the user file, profiles, and Home Manager modules), so a user file can
  # be shared between the NixOS submodule path and standalone use.
  #
  # Returns {} when no home-manager input is available, keeping the output
  # harmless for consumers that don't use Home Manager.
  #
  # Example:
  #   mkHomeConfigurations {
  #     users = { alice = ./users/alice; };
  #     profiles = { developer = ./profiles/developer.nix; };
  #   }
  mkHomeConfigurations = {
    inputs,
    users,
    defaultSystem ? "x86_64-linux",
    # Per-user system override, e.g. { alice = "aarch64-darwin"; }. User files
    # are functions (unlike host files) so the system can't be read from them
    # like hosts; it comes from this explicit map. Users not listed use
    # defaultSystem.
    userSystems ? {},
    profiles ? {},
    homeManagerModules ? {},
    overlays ? [],
    allowUnfree ? false,
    extraModules ? [],
    specialArgs ? {},
    secretsPath ? null,
    omninixHomeModule ? ../modules/home,
    debug ? false,
  }: let
    debugTrace = final.omninix.mkDebugTrace debug;

    # pkgs is instantiated once per distinct system in use (defaultSystem plus
    # any userSystems values), and shared by all users on that system.
    pkgsBySystem = final.genAttrs (final.unique ([defaultSystem] ++ final.attrValues userSystems)) (
      system:
        import inputs.nixpkgs {
          inherit system overlays;
          config.allowUnfree = allowUnfree;
        }
    );
  in
    # Home Manager is optional: without the input there is nothing to
    # build, so we degrade gracefully to an empty attrset (mirrors the
    # optional-input detection in mkNixosConfigurations).
    if !(inputs ? home-manager)
    then debugTrace "Skipping home configurations (no home-manager input)" {}
    else
      debugTrace "Building ${toString (builtins.length (builtins.attrNames users))} home configuration(s)" (
        final.mapAttrs (
          userName: userPath: let
            system = debugTrace "Processing user: ${userName}" (userSystems.${userName} or defaultSystem);
            pkgs = pkgsBySystem.${system};

            # Identity module: standalone Home Manager has no NixOS user to
            # supply these, so infer them from the directory name. mkDefault
            # lets a user's own config override them. homeDirectory follows the
            # platform (darwin uses /Users). The stateVersion default matches
            # the NixOS fallback in modules/nixos.
            identityModule = {lib, ...}: {
              home.username = lib.mkDefault userName;
              home.homeDirectory =
                lib.mkDefault (
                  if lib.hasSuffix "darwin" system
                  then "/Users/${userName}"
                  else "/home/${userName}"
                );
              home.stateVersion = lib.mkDefault "26.05";
            };
          in
            inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;

              # Matches the modules/nixos extraSpecialArgs (inputs,
              # secretsPath) so a single user file can be shared between
              # the NixOS submodule and standalone paths.
              extraSpecialArgs =
                {
                  inherit inputs secretsPath;
                }
                // specialArgs;

              # Same import set as home-manager.users.<name> in
              # modules/nixos (via the shared mkHomeModules helper), plus
              # the standalone-only identity module.
              modules =
                [identityModule]
                ++ final.omninix.mkHomeModules {
                  inherit inputs;
                  lib = final;
                  userFile = userPath;
                  inherit profiles homeManagerModules extraModules omninixHomeModule;
                };
            }
        )
        users
      );
}
