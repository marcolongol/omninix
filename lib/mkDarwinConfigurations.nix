# OmniNix nix-darwin configuration builder
#
# The darwin counterpart of mkNixosConfigurations: same arguments, with the
# darwin halves of roles and darwinModules. Receives the extended-lib
# fixpoint `final`; `inputs` (the consumer's) is a per-call argument.
{final}: {
  # Build nix-darwin system configurations for the darwin hosts
  #
  # Type: { ... } -> AttrSet
  #
  # Each host is built with its inputs' nix-darwin (`hostInputs` merged over
  # `inputs`) and packages from its inputs' nixpkgs, like a NixOS host.
  mkDarwinConfigurations = {
    inputs,
    hosts,
    defaultSystem ? "aarch64-darwin",
    hostSystems ? {},
    hostInputs ? {},
    roles ? {},
    users ? {},
    profiles ? {},
    homeManagerModules ? {},
    darwinModules ? {},
    overlays ? [],
    allowUnfree ? false,
    extraModules ? [],
    specialArgs ? {},
    secretsPath ? null,
    omninixDarwinModule ? ../modules/darwin,
    debug ? false,
  }: let
    debugTrace = final.omninix.mkDebugTrace debug;
  in
    assert final.omninix.assertKnownNames "hostSystems" hosts hostSystems;
    assert final.omninix.assertKnownNames "hostInputs" hosts hostInputs;
      debugTrace "Building ${toString (builtins.length (builtins.attrNames hosts))} darwin host(s)" (
        final.mapAttrs (
          hostName: hostPath: let
            inputs' = inputs // (hostInputs.${hostName} or {});
            system = hostSystems.${hostName} or defaultSystem;
          in
            if !(inputs' ? nix-darwin)
            then
              throw ''
                OmniNix: ${hostName} is a darwin host (${system}), which needs a nix-darwin input:

                  inputs.nix-darwin = {
                    url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
                    inputs.nixpkgs.follows = "nixpkgs";
                  };''
            else
              inputs'.nix-darwin.lib.darwinSystem {
                specialArgs =
                  {
                    inherit hostName users profiles homeManagerModules secretsPath;
                    inputs = inputs';
                    mkHomeModules = final.omninix.mkHomeModules;
                  }
                  // specialArgs;

                modules =
                  [
                    {
                      nixpkgs.hostPlatform = system;
                      # The host's nixpkgs, not nix-darwin's own input: the
                      # same packages a NixOS host on these inputs would get.
                      nixpkgs.source = inputs'.nixpkgs;
                      nixpkgs.flake.source = inputs'.nixpkgs.outPath;
                      nixpkgs.overlays = overlays;
                      # Only when on, as for NixOS hosts (a host may opt in itself).
                      nixpkgs.config = final.optionalAttrs allowUnfree {allowUnfree = true;};
                    }
                    hostPath
                    omninixDarwinModule
                  ]
                  ++ final.optional (inputs' ? home-manager) inputs'.home-manager.darwinModules.home-manager
                  ++ final.optional (inputs' ? sops-nix) inputs'.sops-nix.darwinModules.sops
                  ++ final.attrValues darwinModules
                  ++ final.attrValues roles
                  ++ extraModules;
              }
        )
        hosts
      );
}
