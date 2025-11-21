# Example role: ephemeral root with a persistent /persist. YOURS to own and edit.
#
# Reads the system-level omninix.persistence.* aggregation into impermanence's
# environment.persistence. User-level persistence (home.persistence) is wired by
# OmniNix automatically — see the README, "Impermanence (persistence aggregation)".
#
# To use it:
#   1. Uncomment the `impermanence` input in flake.nix.
#   2. Set `roles.impermanent.enable = true;` on a host.
{ config, lib, inputs, ... }:
{
  # Guarded so the file still evaluates (disabled) before you add the input.
  imports = lib.optional (inputs ? impermanence)
    inputs.impermanence.nixosModules.impermanence;

  options.roles.impermanent.enable =
    lib.mkEnableOption "ephemeral root with a persistent /persist";

  # optionalAttrs (not a nested mkIf) so environment.persistence is genuinely
  # absent until the impermanence module is loaded — otherwise the option-exists
  # check trips even with the role disabled. Enabled without the input fails
  # eval: a silently skipped /persist on a wiped root loses the host keys.
  config = lib.mkIf config.roles.impermanent.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = inputs ? impermanence;
          message = "roles.impermanent is enabled but the `impermanence` flake input is missing.";
        }
      ];
    }
    (lib.optionalAttrs (inputs ? impermanence) {
    environment.persistence."/persist" = {
      enable = true;
      hideMounts = true;
      # Base system state + whatever roles/hosts added to omninix.persistence.
      directories = [
        "/var/log"
        "/var/lib/nixos"
        "/etc/ssh"
      ] ++ config.omninix.persistence.directories;
      files = [
        "/etc/machine-id"
      ] ++ config.omninix.persistence.files;
    };
    })
  ]);
}
