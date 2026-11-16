# Standalone homes (homeConfigurations), built from the fleet with the same
# home modules as host homes (fleet.homeModulesFor).
{lib}: let
  # Every user in the fleet, as a standalone home.
  #
  # Each home gets:
  #   - fleet.homeModulesFor <name> (profiles, home modules, the user's file,
  #     the stateVersion default, sops-nix)
  #   - home.username = its name, and home.homeDirectory = /root for root,
  #     /Users/<name> on darwin, /home/<name> otherwise (all mkDefault)
  #   - pkgs for its system, with the fleet's overlays applied by Home
  #     Manager's nixpkgs options
  #   - `inputs` (with its userInputs on top) as an argument
  #
  # Type: Settings -> { name = home; }
  mkHomeConfigurations = settings: let
    fleet = lib.omninix.mkFleet settings;

    build = name: _: let
      system = fleet.userSystemOf name;
      inputs = fleet.userInputsFor name;
    in
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = inputs.nixpkgs.legacyPackages.${system};
        extraSpecialArgs = {inherit inputs;};
        modules =
          fleet.homeModulesFor name
          ++ [
            # Host homes share the host's pkgs instead (useGlobalPkgs).
            (lib.omninix.nixpkgsModule {inherit (fleet) overlays allowUnfree;})
            {
              # On a host, NixOS supplies these from the user account; here
              # nothing does.
              home.username = lib.mkDefault name;
              home.homeDirectory = lib.mkDefault (
                if name == "root"
                then "/root"
                else if lib.hasSuffix "-darwin" system
                then "/Users/${name}"
                else "/home/${name}"
              );
            }
          ];
      };
  in
    lib.omninix.check fleet (lib.mapAttrs build fleet.users);
in {
  inherit mkHomeConfigurations;
}
