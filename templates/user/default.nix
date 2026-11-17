# A new user's Home Manager config: their home on every host that enables
# them (omninix.hostUsers.<name>), and homeConfigurations.<name>.
{pkgs, ...}: {
  # profiles.common.enable = true;
  home.packages = [pkgs.ripgrep];
}
