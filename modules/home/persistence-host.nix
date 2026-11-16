# Host homes only: hand a user's omninix.persistence to impermanence's
# home.persistence when the host persists to /persist. Not in standalone
# homes, which have no host (osConfig) to ask.
#
# impermanence's NixOS module brings its Home Manager module itself, so
# home.persistence exists exactly when the host imported impermanence.
{
  config,
  lib,
  options,
  osConfig,
  ...
}: {
  # Under `config`, and with optionalAttrs rather than mkIf: setting an option
  # that doesn't exist is an error even inside a false mkIf.
  config = lib.optionalAttrs (options.home ? persistence) (lib.mkIf (osConfig.environment.persistence."/persist".enable or false) {
    home.persistence."/persist" = {
      inherit (config.omninix.persistence) directories files;
    };
  });
}
