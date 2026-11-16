# The fleet: everything OmniNix knows about a flake, worked out once.
#
# mkFleet takes the settings (the flake module's options, with pieces in
# place of directories) and returns one record. The builders and OmniNix's
# own modules read what they need from that record; nothing else is passed
# around.
{lib}: let
  # Every setting and its default. The flake module's options use these too,
  # so each default is written once.
  defaults = {
    # Pieces: { name = module; }, usually discovered from the *Dir options.
    hosts = {};
    users = {};
    roles = {};
    profiles = {};
    nixosModules = {};
    darwinModules = {};
    homeModules = {};
    packages = {};
    overlays = {};

    # Another flake's pieces, by name (sharing).
    extraRoles = {};
    extraProfiles = {};
    extraNixosModules = {};
    extraDarwinModules = {};
    extraHomeModules = {};

    secretsPath = null;
    allowUnfree = false;
    defaultSystem = "x86_64-linux";
    hostSystems = {};
    userSystems = {};
    hostInputs = {};
    userInputs = {};
  };

  # The fleet record. `inputs` (the flake's) is required; every other
  # setting has a default above.
  #
  # Type: { inputs, ...settings } -> Fleet
  mkFleet = settings: let
    s = defaults // settings;
    inherit (s) inputs;
    o = lib.omninix;

    systemOf = name: s.hostSystems.${name} or s.defaultSystem;
    userSystemOf = name: s.userSystems.${name} or s.defaultSystem;
    isDarwin = name: lib.hasSuffix "-darwin" (systemOf name);

    # Ours plus the extras, ours winning a clash. Roles merge whole, by name,
    # and only then split into platform halves, so a host never mixes halves
    # from two flakes. Borrowed roles and profiles can't read our `inputs`.
    borrowAll = kind: lib.mapAttrs (o.borrow kind);
    ownRoleHalves = o.splitRoles s.roles;
    extraRoleHalves = o.splitRoles (o.newExtras "roles" s.roles s.extraRoles);
    profiles = o.withExtras "profiles" s.profiles (borrowAll "profiles" s.extraProfiles);
    homeModules = o.withExtras "homeModules" s.homeModules s.extraHomeModules;
    sharedHomeModules = lib.attrValues profiles ++ lib.attrValues homeModules;

    # `<secretsPath>/<name>.yaml`, or null when there's no such file.
    secretFile = name: let
      file = s.secretsPath + "/${name}.yaml";
    in
      if s.secretsPath != null && builtins.pathExists file
      then file
      else null;

    darwinHosts = lib.filterAttrs (name: _: isDarwin name) s.hosts;

    # Everything wrong with the settings, as messages. Builders check this
    # once and throw them all together (`check`).
    errors =
      lib.optional (unknownSettings != []) "unknown settings: ${toString unknownSettings}"
      ++ lib.mapAttrsToList (option: names: "${option} names unknown host(s): ${toString names}")
      (o.unknownNamesIn s.hosts {inherit (s) hostSystems hostInputs;})
      ++ lib.mapAttrsToList (option: names: "${option} names unknown user(s): ${toString names}")
      (o.unknownNamesIn s.users {inherit (s) userSystems userInputs;})
      ++ lib.optional (s.secretsPath != null && !(inputs ? sops-nix))
      "secretsPath needs a sops-nix flake input"
      ++ lib.optional ((s.users != {} || sharedHomeModules != []) && !(inputs ? home-manager))
      "Home Manager modules need a home-manager flake input (user files: ${toString (lib.attrNames s.users)}; shared home modules: ${toString (lib.length sharedHomeModules)})"
      ++ lib.optional (darwinHosts != {} && !(inputs ? nix-darwin)) ''
        darwin hosts (${toString (lib.attrNames darwinHosts)}) need a nix-darwin flake input:

          inputs.nix-darwin = {
            url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
            inputs.nixpkgs.follows = "nixpkgs";
          };'';
    unknownSettings = lib.attrNames (removeAttrs settings (["inputs"] ++ lib.attrNames defaults));
  in {
    inherit inputs errors secretFile systemOf userSystemOf darwinHosts;
    inherit (s) users packages secretsPath allowUnfree;

    nixosHosts = lib.filterAttrs (name: _: !(isDarwin name)) s.hosts;

    # A host's or user's inputs: the flake's, with their override on top.
    inputsFor = name: inputs // (s.hostInputs.${name} or {});
    userInputsFor = name: inputs // (s.userInputs.${name} or {});

    # The modules every host of a platform imports: its role halves, then
    # the always-on modules.
    hostModules = {
      nixos =
        lib.attrValues (ownRoleHalves.nixos // borrowAll "roles" extraRoleHalves.nixos)
        ++ lib.attrValues (o.withExtras "nixosModules" s.nixosModules s.extraNixosModules);
      darwin =
        lib.attrValues (ownRoleHalves.darwin // borrowAll "roles" extraRoleHalves.darwin)
        ++ lib.attrValues (o.withExtras "darwinModules" s.darwinModules s.extraDarwinModules);
    };

    # The modules of `name`'s home, on a host or standalone.
    homeModulesFor = name: let
      secret = secretFile "users/${name}";
    in
      sharedHomeModules
      ++ lib.optional (s.users ? ${name}) s.users.${name}
      ++ [
        {
          # Frozen: never bump this with the nixpkgs pin, or users who don't
          # set it would silently move to a newer stateVersion.
          home.stateVersion = lib.mkDefault "26.05";
        }
        ../modules/shared/requirements.nix
        ../modules/home/persistence.nix
        # `inputs` is a special argument here, so imports may depend on it.
        ({inputs, ...}: {imports = lib.optional (inputs ? sops-nix) inputs.sops-nix.homeManagerModules.sops;})
      ]
      ++ lib.optional (secret != null) {sops.defaultSopsFile = lib.mkDefault secret;};

    # The packages first, then the overlays in name order.
    overlays = o.allOverlays {
      inherit inputs;
      inherit (s) packages overlays;
    };
  };

  # Return `value`, or throw every error in the fleet at once.
  #
  # Type: Fleet -> a -> a
  check = fleet: value:
    if fleet.errors == []
    then value
    else throw "OmniNix: ${lib.concatStringsSep "\nOmniNix: " fleet.errors}";
in {
  inherit mkFleet check;
  fleetDefaults = defaults;
}
