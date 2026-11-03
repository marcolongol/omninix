# Example role with a home side: one flag on the host turns on both the system
# config below and ./home.nix for every Home Manager user on that host.
{
  config,
  lib,
  options,
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

    # Guarded on the option, not on `inputs`, so the role still works without
    # home-manager and can be shared with other flakes.
    (lib.optionalAttrs (options ? home-manager) {
      home-manager.sharedModules = [./home.nix];
    })
  ]);
}
