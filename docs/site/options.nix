# Option reference pages, generated from the modules' own descriptions with
# nixosOptionsDoc. Each page evaluates the module it documents in a minimal
# configuration and renders its options as CommonMark.
{
  pkgs,
  lib,
  inputs,
  self,
}: let
  repo = "https://github.com/marcolongol/omninix/blob/main";

  # Declarations point at the source on GitHub instead of the Nix store.
  render = options:
    (pkgs.nixosOptionsDoc {
      inherit options;
      transformOptions = opt:
        opt
        // {
          declarations =
            map (decl: let
              path = lib.removePrefix "${self}/" (toString decl);
            in {
              name = path;
              url = "${repo}/${path}";
            })
            opt.declarations;
        };
    })
    .optionsCommonMark;

  nixos = modules:
    (inputs.nixpkgs.lib.nixosSystem {
      inherit (pkgs.stdenv.hostPlatform) system;
      modules =
        [
          {
            boot.isContainer = true;
            system.stateVersion = "26.05";
          }
        ]
        ++ modules;
    })
    .options;

  darwin =
    (inputs.nix-darwin.lib.darwinSystem {
      modules = [
        self.darwinModules.default
        {
          nixpkgs.hostPlatform = "aarch64-darwin";
          system.stateVersion = 7;
        }
      ];
    })
    .options;

  home = modules:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules =
        [
          {
            home.username = "example";
            home.homeDirectory = "/home/example";
            home.stateVersion = "26.05";
          }
        ]
        ++ modules;
    })
    .options;

  flake =
    (inputs.flake-parts.lib.evalFlakeModule {inherit inputs;} {
      imports = [self.flakeModules.default];
      systems = [];
    })
    .options;
in {
  flake = {
    title = "Flake options";
    intro = "Set under `omninix` in a flake-parts flake that imports `omninix.flakeModules.default`.";
    page = render {inherit (flake) omninix;};
  };
  nixos = {
    title = "Host options (NixOS)";
    intro = "Set in a NixOS host, a role or a NixOS module. Also available in any `nixosSystem` through `omninix.nixosModules.default`.";
    page = render {inherit (nixos [self.nixosModules.default]) omninix;};
  };
  darwin = {
    title = "Host options (nix-darwin)";
    intro = "Set in a Mac host or the darwin half of a role. Also available in any `darwinSystem` through `omninix.darwinModules.default`.";
    page = render {inherit (darwin) omninix;};
  };
  home = {
    title = "User options (Home Manager)";
    intro = "Set in a user file, a profile or a Home Manager module. Also available in any Home Manager config through `omninix.homeModules.default`.";
    page = render {inherit (home [self.homeModules.default]) omninix;};
  };
  roles = {
    title = "Shipped roles";
    intro = "Roles that come with OmniNix. Add them with `extraRoles = omninix.roles;`, or one with `extraRoles = {inherit (omninix.roles) impermanent;};`.";
    page = render {inherit (nixos [self.nixosModules.default self.roles.impermanent]) roles;};
  };
  profiles = {
    title = "Shipped profiles";
    intro = "Profiles that come with OmniNix. Add them with `extraProfiles = omninix.profiles;`.";
    page = render {inherit (home [self.homeModules.default self.profiles.developer]) profiles;};
  };
}
