# OmniNix profile: developer
#
# NOTE: contains UNFREE packages (ngrok, dbeaver-bin). Enabling this profile
# therefore requires `allowUnfree = true` in your mkFlake call.
#
# NOTE: uses several newer Home Manager program modules (programs.claude-code,
# programs.lazydocker, programs.k9s, programs.ssh.enableDefaultConfig). These
# need a reasonably recent home-manager (≈ 24.11+ / matching nixos-25.05+).
# On an older home-manager pin you may get "option does not exist" errors.
{
  config,
  lib,
  pkgs,
  ...
}: {
  options.profiles.developer.enable = lib.mkEnableOption "developer tools and CLI configuration";

  config = lib.mkIf config.profiles.developer.enable {
    home.packages = with pkgs; [
      curl
      wget
      gnumake
      cmake
      docker-compose
      docker-buildx
      docker-client
      kubernetes-helm
      talosctl # niche: Talos Linux CLI
      kubectl
      krew
      ngrok # UNFREE — requires allowUnfree
      restic
      fluxcd
      cilium-cli
      dbeaver-bin # UNFREE — requires allowUnfree
      dig
      tilt
    ];

    programs.git = {
      enable = true;
      settings = {
        core.editor = "vim";
        pull.rebase = true;

        # Security & Performance
        push.autoSetupRemote = true;
        fetch.prune = true;
        rebase.autoStash = true;
        rerere.enabled = true;

        # Better Diffs & Merges
        diff.algorithm = "histogram";
        diff.colorMoved = "default";
        merge.conflictStyle = "zdiff3";

        # Branch Management
        branch.sort = "-committerdate";
        tag.sort = "version:refname";
      };
    };

    programs.direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    programs.claude-code = {
      enable = true;
    };

    programs.jq = {
      enable = true;
    };

    programs.lazygit = {
      enable = true;
    };

    programs.lazydocker = {
      enable = true;
    };

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
    };

    programs.k9s = {
      enable = true;
    };

    omninix.persistence.directories = [
      ".claude"
      ".config/github-copilot"
      ".config/Code"
      ".krew"
    ];

    omninix.persistence.files = [
      ".claude.json"
      ".kube/config"
    ];

    home.sessionPath = ["$HOME/.krew/bin"];
  };
}
