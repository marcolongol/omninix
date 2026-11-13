# The darwin half: declares the same switch, sets nix-darwin options.
{lib, ...}: {options.roles.both.enable = lib.mkEnableOption "both (darwin half)";}
