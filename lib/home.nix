# Home Manager homes: what makes up a user's home, and standalone
# homeConfigurations built from the same user files as host homes.
{lib}: let
  # The modules that make up `name`'s home, on a host or standalone: the
  # shared home modules (profiles, always-on modules), their file in `users`
  # (if they have one), a stateVersion default, sops-nix's module when the
  # flake has the input, and their secret file as the default sops file.
  #
  # Type: { users, sharedHomeModules, secretsPath } -> String -> [Module]
  userHomeModules = {
    users,
    sharedHomeModules,
    secretsPath,
  }: name: let
    secret = lib.omninix.secretFile secretsPath "users/${name}";
  in
    sharedHomeModules
    ++ lib.optional (users ? ${name}) users.${name}
    ++ [
      {
        # Frozen: never bump this with the nixpkgs pin, or users who don't
        # set it would silently move to a newer stateVersion.
        home.stateVersion = lib.mkDefault "26.05";
      }

      # `inputs` is a special argument here, so imports may depend on it.
      ({inputs, ...}: {imports = lib.optional (inputs ? sops-nix) inputs.sops-nix.homeManagerModules.sops;})
    ]
    ++ lib.optional (secret != null) {sops.defaultSopsFile = lib.mkDefault secret;};

  # Return `value`, or throw if there are user files or shared home modules
  # but no home-manager input to apply them (they would be silently dropped).
  #
  # Type: AttrSet -> { users, sharedHomeModules, ... } -> a -> a
  withHomeManager = inputs: {
    users,
    sharedHomeModules,
    ...
  }: value:
    if (users != {} || sharedHomeModules != []) && !(inputs ? home-manager)
    then throw "OmniNix: Home Manager modules need a home-manager flake input (user files: ${toString (lib.attrNames users)}; shared home modules: ${toString (lib.length sharedHomeModules)})"
    else value;

  # Build every user in `users` ({ name = module; }) as a standalone home.
  #
  # Each home gets:
  #   - userHomeModules (shared home modules, the user's file, the
  #     stateVersion default and sops-nix)
  #   - home.username = its name, and home.homeDirectory = /root for root,
  #     /Users/<name> on darwin, /home/<name> otherwise (all mkDefault)
  #   - pkgs for userSystems.<name> or defaultSystem
  #   - `inputs` as a module argument
  # all from the flake's inputs with userInputs.<name> on top.
  #
  # Type: { inputs, users, sharedHomeModules ? [Module], defaultSystem ? String, userSystems ? AttrSet,
  #         userInputs ? AttrSet, secretsPath ? Path } -> AttrSet
  mkHomeConfigurations = {
    inputs,
    users,
    sharedHomeModules ? [],
    defaultSystem ? "x86_64-linux",
    userSystems ? {},
    userInputs ? {},
    secretsPath ? null,
  }: let
    homes = {inherit users sharedHomeModules secretsPath;};

    mkHome = name: _: let
      system = userSystems.${name} or defaultSystem;
      inputs' = inputs // (userInputs.${name} or {});
    in
      inputs'.home-manager.lib.homeManagerConfiguration {
        pkgs = inputs'.nixpkgs.legacyPackages.${system};
        extraSpecialArgs = {inputs = inputs';};
        modules =
          userHomeModules homes name
          ++ [
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
    lib.omninix.withKnownNames "user" users {inherit userSystems userInputs;}
    (lib.omninix.withSops inputs secretsPath
      (withHomeManager inputs homes (lib.mapAttrs mkHome users)));
in {
  inherit userHomeModules withHomeManager mkHomeConfigurations;
}
