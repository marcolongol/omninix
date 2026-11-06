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
  # home-manager.users.<name> by modules/home-manager.nix (the OmniNix home module,
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
    # are modules (functions), so the system can't be read from them; it comes
    # from this explicit map. Users not listed use defaultSystem.
    userSystems ? {},
    # Per-user input overrides, e.g. { alice = { nixpkgs = …; home-manager = …; }; },
    # merged over `inputs` for that user's standalone home only.
    userInputs ? {},
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

    pkgsFor = nixpkgs: system:
      import nixpkgs {
        inherit system overlays;
        config.allowUnfree = allowUnfree;
      };

    # pkgs is instantiated once per distinct system in use (defaultSystem plus
    # any userSystems values), and shared by all users on that system who
    # don't override nixpkgs in userInputs.
    pkgsBySystem = final.genAttrs (final.unique ([defaultSystem] ++ final.attrValues userSystems)) (pkgsFor inputs.nixpkgs);
  in
    assert final.omninix.assertKnownNames "userSystems" users userSystems;
    assert final.omninix.assertKnownNames "userInputs" users userInputs;
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
              # This user's inputs: the flake's, with its userInputs entry on top.
              inputs' = inputs // (userInputs.${userName} or {});
              pkgs =
                if (userInputs.${userName} or {}) ? nixpkgs
                then pkgsFor inputs'.nixpkgs system
                else pkgsBySystem.${system};

              # Identity module: standalone Home Manager has no NixOS user to
              # supply these, so infer them from the directory name. mkDefault
              # lets a user's own config override them. homeDirectory follows the
              # platform (darwin uses /Users), except root's, which is /root.
              # The stateVersion default matches the host one in modules/home-manager.nix.
              identityModule = {lib, ...}: {
                home.username = lib.mkDefault userName;
                home.homeDirectory = lib.mkDefault (
                  if userName == "root"
                  then "/root"
                  else if lib.hasSuffix "darwin" system
                  then "/Users/${userName}"
                  else "/home/${userName}"
                );
                # Frozen: never bump with the nixpkgs pin. Users who don't set it
                # would silently move to a newer stateVersion.
                home.stateVersion = lib.mkDefault "26.05";
              };
            in
              inputs'.home-manager.lib.homeManagerConfiguration {
                inherit pkgs;

                # Matches the modules/home-manager.nix extraSpecialArgs (inputs,
                # secretsPath) so a single user file can be shared between
                # hosts and standalone use.
                extraSpecialArgs =
                  {
                    inherit secretsPath;
                    inputs = inputs';
                  }
                  // specialArgs;

                # Same import set as home-manager.users.<name> on hosts (via
                # the shared mkHomeModules helper), plus the standalone-only
                # identity module.
                modules =
                  [identityModule]
                  ++ final.omninix.mkHomeModules {
                    inherit userName secretsPath;
                    inputs = inputs';
                    lib = final;
                    userFile = userPath;
                    inherit profiles homeManagerModules extraModules omninixHomeModule;
                  };
              }
          )
          users
        );
}
