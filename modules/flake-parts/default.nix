# OmniNix's flake-parts module (flakeModules.default): point omninix.*Dir at
# your directories and get your fleet.
#
# Applied with importApply, so `omninixLib` (our lib.omninix) arrives by
# closure: inside a consumer's flake, `lib` and `inputs` are theirs.
{omninixLib}: {
  config,
  lib,
  inputs,
  ...
}: let
  cfg = config.omninix;

  # A directory's pieces, or {} when it isn't set.
  discover = dir:
    if dir == null
    then {}
    else omninixLib.discoverNixFiles ["default.nix"] dir;

  hosts = discover cfg.hostsDir;
  users = discover cfg.usersDir;
  roles = discover cfg.rolesDir;
  profiles = discover cfg.profilesDir;
  nixosModules = discover cfg.nixosModulesDir;
  homeModules = discover cfg.homeModulesDir;

  # Every host imports the roles and the always-on NixOS modules; every home
  # the profiles and the always-on home modules.
  sharedModules = lib.attrValues roles ++ lib.attrValues nixosModules;
  sharedHomeModules = lib.attrValues profiles ++ lib.attrValues homeModules;

  dirOption = description:
    lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      inherit description;
    };

  systemsOption = what:
    lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      example = {pi = "aarch64-linux";};
      description = "Per-${what} system, overriding defaultSystem. Unknown names are an error.";
    };

  inputsOption = what:
    lib.mkOption {
      # lazyAttrsOf raw: inputs are passed through untouched, and only read
      # when used.
      type = lib.types.attrsOf (lib.types.lazyAttrsOf lib.types.raw);
      default = {};
      example = lib.literalExpression "{ pi.nixpkgs = inputs.nixpkgs-unstable; }";
      description = "Per-${what} flake inputs, merged over the flake's own for that ${what} only (its nixpkgs, Home Manager and `inputs` argument). Unknown names are an error.";
    };
in {
  options.omninix = {
    hostsDir = dirOption "Hosts: each `<name>.nix` or `<name>/default.nix` becomes nixosConfigurations.<name>.";
    usersDir = dirOption "Users (Home Manager modules): the home of `<name>` on every host enabling them, and homeConfigurations.<name>.";
    rolesDir = dirOption "Roles: NixOS modules every host imports, each off until a host sets roles.<name>.enable. Exported as `roles`.";
    profilesDir = dirOption "Profiles: Home Manager modules every home imports, each off until a user sets profiles.<name>.enable. Exported as `profiles`.";
    nixosModulesDir = dirOption "Always-on NixOS modules every host imports. Exported as `nixosModules`.";
    homeModulesDir = dirOption "Always-on Home Manager modules every home imports. Exported as `homeModules`.";

    defaultSystem = lib.mkOption {
      type = lib.types.str;
      default = "x86_64-linux";
      description = "System for hosts and users not listed in hostSystems / userSystems.";
    };
    hostSystems = systemsOption "host";
    userSystems = systemsOption "user";
    hostInputs = inputsOption "host";
    userInputs = inputsOption "user";
  };

  config.flake = lib.mkMerge [
    {
      nixosConfigurations = omninixLib.mkNixosConfigurations {
        inherit inputs hosts users sharedModules sharedHomeModules;
        inherit (cfg) defaultSystem hostSystems hostInputs;
      };

      inherit roles profiles;

      # mkDefault per entry: nixosModules is typed by flake-parts, and its
      # entries merge. A flake's own entry of the same name should replace
      # ours, not merge with it.
      nixosModules = lib.mapAttrs (_: lib.mkDefault) nixosModules;
    }

    # Only when there is something to put there, so a flake without users or
    # home modules doesn't get empty outputs it might define itself.
    (lib.mkIf (users != {}) {
      homeConfigurations = omninixLib.mkHomeConfigurations {
        inherit inputs users sharedHomeModules;
        inherit (cfg) defaultSystem userSystems userInputs;
      };
    })
    (lib.mkIf (homeModules != {}) {inherit homeModules;})
  ];
}
