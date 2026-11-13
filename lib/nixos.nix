# NixOS hosts: one nixosSystem per host.
{lib}: let
  # Names in `given` that aren't in `known`. Per-host maps like hostSystems
  # would otherwise ignore a misspelt host silently.
  #
  # Type: AttrSet -> AttrSet -> [String]
  #
  # Example:
  #   unknownNames { laptop = …; } { lpatop = "aarch64-linux"; }
  #   => [ "lpatop" ]
  unknownNames = known: given: lib.attrNames (removeAttrs given (lib.attrNames known));

  # Build every host in `hosts` ({ name = module; }, usually from
  # discoverNixFiles) into a nixosSystem.
  #
  # Each host gets:
  #   - networking.hostName = its name (mkDefault, so the host can change it)
  #   - nixpkgs.hostPlatform = hostSystems.<name> or defaultSystem (mkDefault,
  #     so a hardware-configuration.nix that disagrees is a conflict, not a
  #     silent override)
  #   - `hostName` and `inputs` as module arguments
  #   - OmniNix's NixOS module (modules/nixos): users and passwords
  #
  # Type: { inputs, hosts, defaultSystem ? String, hostSystems ? AttrSet } -> AttrSet
  mkNixosConfigurations = {
    inputs,
    hosts,
    defaultSystem ? "x86_64-linux",
    hostSystems ? {},
  }: let
    unknown = unknownNames hosts hostSystems;

    # The caller's nixpkgs builds the system, not ours: hosts must follow the
    # consumer's pin.
    mkHost = hostName: host:
      inputs.nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs hostName;};
        modules = [
          host
          ../modules/nixos
          {
            networking.hostName = lib.mkDefault hostName;
            nixpkgs.hostPlatform = lib.mkDefault (hostSystems.${hostName} or defaultSystem);
          }
        ];
      };
  in
    if unknown != []
    then throw "OmniNix: hostSystems names unknown host(s): ${toString unknown}"
    else lib.mapAttrs mkHost hosts;
in {
  inherit unknownNames mkNixosConfigurations;
}
