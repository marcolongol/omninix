# NixOS hosts: one nixosSystem per host.
{lib}: let
  # Build every host in `hosts` ({ name = module; }, usually from
  # discoverNixFiles) into a nixosSystem.
  #
  # Each host gets:
  #   - networking.hostName = its name (mkDefault, so the host can change it)
  #   - nixpkgs.hostPlatform = hostSystems.<name> or defaultSystem (mkDefault,
  #     so a hardware-configuration.nix that disagrees is a conflict, not a
  #     silent override)
  #   - `hostName` and `inputs` as module arguments, where `inputs` is the
  #     flake's inputs with hostInputs.<name> on top (e.g. another nixpkgs
  #     for one host); the host is built from those inputs throughout
  #   - OmniNix's NixOS module (modules/nixos): users and passwords
  #   - every module in `sharedModules` (roles, always-on modules)
  #   - nixpkgs.overlays = overlays, and allowUnfree when true
  #   - with a sops-nix input, sops-nix, wired by convention to secretsPath
  #     (lib/secrets.nix)
  #   - with a home-manager input, a home for every active user, built from
  #     `sharedHomeModules` (profiles, always-on modules) and their file in
  #     `users` ({ name = module; }) when they have one
  #
  # Type: { inputs, hosts, users ? AttrSet, sharedModules ? [Module],
  #         sharedHomeModules ? [Module], defaultSystem ? String,
  #         hostSystems ? AttrSet, hostInputs ? AttrSet, secretsPath ? Path,
  #         overlays ? [Overlay], allowUnfree ? Bool } -> AttrSet
  mkNixosConfigurations = {
    inputs,
    hosts,
    users ? {},
    sharedModules ? [],
    sharedHomeModules ? [],
    defaultSystem ? "x86_64-linux",
    hostSystems ? {},
    hostInputs ? {},
    secretsPath ? null,
    overlays ? [],
    allowUnfree ? false,
  }: let
    homes = {inherit users sharedHomeModules secretsPath;};

    # The caller's nixpkgs (or this host's override) builds the system, not
    # ours: hosts must follow the consumer's pin.
    mkHost = hostName: host: let
      inputs' = inputs // (hostInputs.${hostName} or {});
    in
      inputs'.nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit hostName;
          inputs = inputs';
        };
        modules =
          [
            host
            ../modules/nixos
            {
              networking.hostName = lib.mkDefault hostName;
              nixpkgs.hostPlatform = lib.mkDefault (hostSystems.${hostName} or defaultSystem);
            }
            (lib.omninix.nixpkgsModule {inherit overlays allowUnfree;})
          ]
          ++ sharedModules
          ++ lib.optional (inputs' ? sops-nix)
          (lib.modules.importApply ../modules/nixos/secrets.nix {secretFile = lib.omninix.secretFile secretsPath;})
          ++ lib.optional (inputs' ? home-manager)
          (lib.modules.importApply ../modules/nixos/home-manager.nix {homeModules = lib.omninix.userHomeModules homes;});
      };
  in
    lib.omninix.withKnownNames "host" hosts {inherit hostSystems hostInputs;}
    (lib.omninix.withSops inputs secretsPath
      (lib.omninix.withHomeManager inputs homes (lib.mapAttrs mkHost hosts)));
in {
  inherit mkNixosConfigurations;
}
