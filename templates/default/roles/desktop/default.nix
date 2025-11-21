# Example role with a home side: one flag on the host turns on both the system
# config below and ./home.nix for every Home Manager user on that host. No
# matching profile to keep in sync with the role.
{
  config,
  lib,
  inputs,
  ...
}: {
  options.roles.desktop.enable = lib.mkEnableOption "Sway desktop (system + user side)";

  config = lib.mkIf config.roles.desktop.enable (lib.mkMerge [
    {
      programs.sway.enable = true;

      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        pulse.enable = true;
      };
    }

    # Guarded so the role still works on a flake without home-manager.
    (lib.optionalAttrs (inputs ? home-manager) {
      home-manager.sharedModules = [./home.nix];
    })
  ]);
}
