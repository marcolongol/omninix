# Hosts: one system per host, NixOS or nix-darwin. Both are built the same
# way; a small platform record says what differs.
{lib}: let
  # What differs between NixOS and nix-darwin hosts.
  platforms = {
    nixos = {
      defaultSystem = "x86_64-linux";
      # The caller's nixpkgs (or this host's override) builds the system, not
      # ours: hosts must follow the consumer's pin.
      build = inputs: inputs.nixpkgs.lib.nixosSystem;
      core = ../modules/nixos;
      secrets = ../modules/nixos/secrets.nix;
      homeManager = inputs: inputs.home-manager.nixosModules.home-manager;
      extraModules = _: [];
    };

    darwin = {
      defaultSystem = "aarch64-darwin";
      build = inputs:
        if inputs ? nix-darwin
        then inputs.nix-darwin.lib.darwinSystem
        else
          throw ''
            OmniNix: darwin hosts need a nix-darwin flake input:

              inputs.nix-darwin = {
                url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
                inputs.nixpkgs.follows = "nixpkgs";
              };'';
      core = ../modules/darwin;
      secrets = ../modules/darwin/secrets.nix;
      homeManager = inputs: inputs.home-manager.darwinModules.home-manager;
      # nix-darwin uses its own nixpkgs input unless told otherwise; use the
      # host's, as on NixOS.
      extraModules = inputs: [
        {
          nixpkgs.source = inputs.nixpkgs;
          nixpkgs.flake.source = inputs.nixpkgs.outPath;
        }
      ];
    };
  };

  # Build every host in `hosts` ({ name = module; }, usually from
  # discoverNixFiles) for `platform` (platforms.nixos or platforms.darwin).
  #
  # Each host gets:
  #   - networking.hostName = its name (mkDefault, so the host can change it)
  #   - nixpkgs.hostPlatform = hostSystems.<name> or defaultSystem (mkDefault,
  #     so a hardware-configuration.nix that disagrees is a conflict, not a
  #     silent override)
  #   - `hostName` and `inputs` as module arguments, where `inputs` is the
  #     flake's inputs with hostInputs.<name> on top (e.g. another nixpkgs
  #     for one host); the host is built from those inputs throughout
  #   - OmniNix's module for the platform (modules/nixos or modules/darwin)
  #   - every module in `sharedModules` (roles, always-on modules)
  #   - nixpkgs.overlays = overlays, and allowUnfree when true
  #   - with a sops-nix input, sops-nix, wired by convention to secretsPath
  #     (lib/secrets.nix)
  #   - with a home-manager input, a home for every active user, built from
  #     `sharedHomeModules` (profiles, always-on modules) and their file in
  #     `users` ({ name = module; }) when they have one
  #
  # Type: Platform -> { inputs, hosts, users ? AttrSet, sharedModules ? [Module],
  #         sharedHomeModules ? [Module], defaultSystem ? String,
  #         hostSystems ? AttrSet, hostInputs ? AttrSet, secretsPath ? Path,
  #         overlays ? [Overlay], allowUnfree ? Bool } -> AttrSet
  mkHostConfigurations = platform: {
    inputs,
    hosts,
    users ? {},
    sharedModules ? [],
    sharedHomeModules ? [],
    defaultSystem ? platform.defaultSystem,
    hostSystems ? {},
    hostInputs ? {},
    secretsPath ? null,
    overlays ? [],
    allowUnfree ? false,
  }: let
    homes = {inherit users sharedHomeModules secretsPath;};

    mkHost = hostName: host: let
      inputs' = inputs // (hostInputs.${hostName} or {});
    in
      platform.build inputs' {
        specialArgs = {
          inherit hostName;
          inputs = inputs';
        };
        modules =
          [
            host
            platform.core
            {
              networking.hostName = lib.mkDefault hostName;
              nixpkgs.hostPlatform = lib.mkDefault (hostSystems.${hostName} or defaultSystem);
            }
            (lib.omninix.nixpkgsModule {inherit overlays allowUnfree;})
          ]
          ++ platform.extraModules inputs'
          ++ sharedModules
          ++ lib.optional (inputs' ? sops-nix)
          (lib.modules.importApply platform.secrets {secretFile = lib.omninix.secretFile secretsPath;})
          ++ lib.optional (inputs' ? home-manager)
          (lib.modules.importApply ../modules/shared/home-manager.nix {
            homeManagerModule = platform.homeManager inputs';
            homeModules = lib.omninix.userHomeModules homes;
          });
      };
  in
    lib.omninix.withKnownNames "host" hosts {inherit hostSystems hostInputs;}
    (lib.omninix.withSops inputs secretsPath
      (lib.omninix.withHomeManager inputs homes (lib.mapAttrs mkHost hosts)));
in {
  mkNixosConfigurations = mkHostConfigurations platforms.nixos;
  mkDarwinConfigurations = mkHostConfigurations platforms.darwin;
}
