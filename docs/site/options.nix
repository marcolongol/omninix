# Option reference pages, generated from the modules' own descriptions with
# nixosOptionsDoc: each page evaluates the builders on a minimal host or home
# and renders the options it documents as CommonMark.
{
  pkgs,
  lib,
  inputs,
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
              path = lib.removePrefix "${inputs.self}/" (toString decl);
            in {
              name = path;
              url = "${repo}/${path}";
            })
            opt.declarations;
        };
    })
    .optionsCommonMark;

  # One host or home, with a secrets directory so the secrets options exist.
  settings = extra:
    {
      inherit inputs;
      secretsPath = ../../tests/suites/secrets/secrets;
    }
    // extra;

  nixos = extra:
    (lib.omninix.mkNixosConfigurations (settings ({
        hosts.example = {
          boot.isContainer = true;
          system.stateVersion = "26.05";
        };
      }
      // extra)))
    .example
    .options;

  darwin =
    (lib.omninix.mkDarwinConfigurations (settings {
      hosts.example.system.stateVersion = 7;
      hostSystems.example = "aarch64-darwin";
    }))
    .example
    .options;

  home =
    (lib.omninix.mkHomeConfigurations (settings {users.example = {};}))
    .example
    .options;

  flake =
    (inputs.flake-parts.lib.evalFlakeModule {inherit inputs;} {
      imports = [inputs.self.flakeModules.default];
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
    intro = "Set in a NixOS host, a role or a NixOS module.";
    page = render {inherit (nixos {}) omninix;};
  };
  darwin = {
    title = "Host options (nix-darwin)";
    intro = "Set in a Mac host, the darwin half of a role, or a nix-darwin module.";
    page = render {inherit (darwin) omninix;};
  };
  home = {
    title = "User options (Home Manager)";
    intro = "Set in a user file, a profile or a Home Manager module.";
    page = render {inherit (home) omninix;};
  };
  roles = {
    title = "Shipped roles";
    intro = "Roles that come with OmniNix. Add them by name, e.g. `extraRoles = {inherit (omninix.roles) impermanent;};`.";
    page = render {inherit (nixos {roles.impermanent = inputs.self.roles.impermanent;}) roles;};
  };
}
