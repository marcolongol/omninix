# Home side of roles.desktop. Applied to every user on a host with the role via
# home-manager.sharedModules, so no enable option or guard here.
{pkgs, ...}: {
  programs.foot.enable = true;
  programs.firefox.enable = true;

  home.packages = with pkgs; [
    wl-clipboard
  ];

  omninix.persistence.directories = [".mozilla"];
}
