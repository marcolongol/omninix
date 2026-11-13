# Home Manager homes: what makes up a user's home, and standalone
# homeConfigurations built from the same user files as host homes.
{lib}: let
  # The modules that make up `name`'s home, on a host or standalone: the
  # shared home modules (profiles, always-on modules), their file in `users`
  # (if they have one) and a stateVersion default.
  #
  # Type: { users, sharedHomeModules } -> String -> [Module]
  userHomeModules = {
    users,
    sharedHomeModules,
  }: name:
    sharedHomeModules
    ++ lib.optional (users ? ${name}) users.${name}
    ++ [
      {
        # Frozen: never bump this with the nixpkgs pin, or users who don't
        # set it would silently move to a newer stateVersion.
        home.stateVersion = lib.mkDefault "26.05";
      }
    ];

  # Return `value`, or throw if there are user files or shared home modules
  # but no home-manager input to apply them (they would be silently dropped).
  #
  # Type: AttrSet -> { users, sharedHomeModules } -> a -> a
  withHomeManager = inputs: {
    users,
    sharedHomeModules,
  }: value:
    if (users != {} || sharedHomeModules != []) && !(inputs ? home-manager)
    then throw "OmniNix: Home Manager modules need a home-manager flake input (user files: ${toString (lib.attrNames users)}; shared home modules: ${toString (lib.length sharedHomeModules)})"
    else value;

  # Build every user in `users` ({ name = module; }) as a standalone home.
  #
  # Each home gets:
  #   - userHomeModules (shared home modules, the user's file and the
  #     stateVersion default)
  #   - home.username = its name, and home.homeDirectory = /root for root,
  #     /Users/<name> on darwin, /home/<name> otherwise (all mkDefault)
  #   - pkgs for userSystems.<name> or defaultSystem
  #   - `inputs` as a module argument
  #
  # Type: { inputs, users, sharedHomeModules ? [Module], defaultSystem ? String, userSystems ? AttrSet } -> AttrSet
  mkHomeConfigurations = {
    inputs,
    users,
    sharedHomeModules ? [],
    defaultSystem ? "x86_64-linux",
    userSystems ? {},
  }: let
    homes = {inherit users sharedHomeModules;};
    unknown = lib.omninix.unknownNames users userSystems;

    mkHome = name: _: let
      system = userSystems.${name} or defaultSystem;
    in
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = inputs.nixpkgs.legacyPackages.${system};
        extraSpecialArgs = {inherit inputs;};
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
    if unknown != []
    then throw "OmniNix: userSystems names unknown user(s): ${toString unknown}"
    else withHomeManager inputs homes (lib.mapAttrs mkHome users);
in {
  inherit userHomeModules withHomeManager mkHomeConfigurations;
}
