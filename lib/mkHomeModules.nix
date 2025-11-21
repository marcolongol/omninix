# OmniNix per-user Home Manager module set
#
# Plain attrset: mkHomeModules takes everything it needs (`inputs` and its own
# `lib`) as parameters, so this file needs neither the fixpoint nor a closure.
{
  # Assemble the Home Manager module set for a single OmniNix user
  #
  # Type: { inputs, lib, userFile?, profiles?, homeManagerModules?, ... } -> [Module]
  #
  # Single source of truth for "what modules make up a user's home",
  # shared by both consumers:
  #   - modules/nixos (home-manager.users.<name>.imports), and
  #   - mkHomeConfigurations (standalone homeConfigurations.<user>).
  #
  # Returns, in order: the OmniNix home module, the user file (if any), the
  # optional sops-nix HM module (when that input exists), all profiles, all
  # Home Manager modules, then any extraModules. Keeping this in one place
  # means a new optional input or import only changes here, not in two
  # hand-synced sites.
  #
  # `inputs` is the consumer's flake inputs (for optional input detection).
  # `lib` is taken as a parameter (rather than closed over) so the NixOS
  # module can pass its own module-system lib; only base lib functions are
  # used. `userFile` is null for hosts that list a user without a config.
  #
  # Note: impermanence's HM module is intentionally NOT imported here. Current
  # impermanence auto-imports it via its NixOS module (manual imports throw a
  # deprecation assertion) and no longer ships a usable standalone HM flake
  # output. OmniNix also doesn't wire persistentFolders/Files into home.persistence
  # yet, so this import was vestigial.
  mkHomeModules = {
    inputs,
    lib,
    userFile ? null,
    profiles ? {},
    homeManagerModules ? {},
    omninixHomeModule ? ../modules/home,
    extraModules ? [],
  }:
    [(import omninixHomeModule)]
    ++ (lib.optionals (userFile != null) [(import userFile)])
    ++ (lib.optional (inputs ? sops-nix) inputs.sops-nix.homeManagerModules.sops)
    ++ (lib.attrValues profiles)
    ++ (lib.attrValues homeManagerModules)
    ++ extraModules;
}
