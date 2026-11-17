# A user's Home Manager config: their home on every host that enables them,
# and homeConfigurations.example-user for `home-manager switch` elsewhere.
{pkgs, ...}: {
  profiles.common.enable = true;

  home.packages = [pkgs.ripgrep];

  programs.git = {
    enable = true;
    settings.user = {
      name = "Your Name";
      email = "you@example.com";
    };
  };
}
