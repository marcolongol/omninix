# Hosts: one system per host, NixOS or nix-darwin, built from the fleet
# (lib/fleet.nix). Both platforms are built the same way; a small record
# says what differs.
{lib}: let
  platforms = {
    nixos = {
      name = "nixos";
      hostsOf = fleet: fleet.nixosHosts;
      # The host's nixpkgs builds the system, not ours: hosts must follow
      # the consumer's pin.
      build = inputs: inputs.nixpkgs.lib.nixosSystem;
      core = ../modules/nixos;
      secrets = ../modules/nixos/secrets.nix;
      sopsModule = inputs: inputs.sops-nix.nixosModules.sops;
      homeManagerModule = inputs: inputs.home-manager.nixosModules.home-manager;
      extraModules = _: [];
    };

    darwin = {
      name = "darwin";
      hostsOf = fleet: fleet.darwinHosts;
      build = inputs: inputs.nix-darwin.lib.darwinSystem;
      core = ../modules/darwin;
      secrets = ../modules/darwin/secrets.nix;
      sopsModule = inputs: inputs.sops-nix.darwinModules.sops;
      homeManagerModule = inputs: inputs.home-manager.darwinModules.home-manager;
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

  # What one host is built from: its inputs, and the `specialArgs` and
  # `modules` handed to the platform's system function. The VM tests boot a
  # host from this, so they test exactly what the builder makes.
  #
  # Each host gets:
  #   - networking.hostName = its name (mkDefault, so the host can change it)
  #   - nixpkgs.hostPlatform = its system (mkDefault, so a
  #     hardware-configuration.nix that disagrees is a conflict, not a
  #     silent override)
  #   - `hostName` and `inputs` (with its hostInputs on top) as arguments
  #   - OmniNix's module for the platform, the fleet's overlays, and
  #     omninix-info
  #   - the platform's role halves and always-on modules
  #   - with a sops-nix input: sops-nix, wired to secretsPath
  #   - with a home-manager input: a home for every active user
  #
  # Type: Platform -> Fleet -> String -> Module -> { inputs, specialArgs, modules }
  hostEvalArgs = platform: fleet: hostName: host: let
    inputs = fleet.inputsFor hostName;
  in {
    inherit inputs;
    specialArgs = {inherit hostName inputs;};
    modules =
      [
        host
        platform.core
        {
          networking.hostName = lib.mkDefault hostName;
          nixpkgs.hostPlatform = lib.mkDefault (fleet.systemOf hostName);
        }
        (lib.omninix.nixpkgsModule {inherit (fleet) overlays allowUnfree;})
        (lib.modules.importApply ../modules/shared/info {omninixRevision = lib.omninix.revision;})
      ]
      ++ platform.extraModules inputs
      ++ fleet.hostModules.${platform.name}
      # OmniNix's own modules get the fleet the same way: importApply.
      ++ lib.optionals (inputs ? sops-nix) [
        (platform.sopsModule inputs)
        (lib.modules.importApply platform.secrets {inherit fleet;})
      ]
      ++ lib.optionals (inputs ? home-manager) [
        (platform.homeManagerModule inputs)
        (lib.modules.importApply ../modules/shared/home-manager.nix {inherit fleet;})
      ];
  };

  # Every host of `platform` in the fleet, built.
  #
  # Type: Platform -> Settings -> { name = system; }
  mkHostConfigurations = platform: settings: let
    fleet = lib.omninix.mkFleet settings;
    build = hostName: host: let
      args = hostEvalArgs platform fleet hostName host;
    in
      platform.build args.inputs {inherit (args) specialArgs modules;};
  in
    lib.omninix.check fleet (lib.mapAttrs build (platform.hostsOf fleet));
in {
  mkNixosConfigurations = mkHostConfigurations platforms.nixos;
  mkDarwinConfigurations = mkHostConfigurations platforms.darwin;
  nixosHostEvalArgs = settings: hostEvalArgs platforms.nixos (lib.omninix.mkFleet settings);
}
