{inputs, ...}: let
  lib = import ../../lib {inherit inputs;};

  # What consumers import. importApply hands it our namespace by closure;
  # inside their flake, `lib` and `inputs` are theirs.
  flakeModule = lib.modules.importApply ../flake-parts {omninixLib = lib.omninix;};
in {
  # OmniNix uses its own flake module, like any consumer (see flake.nix).
  # Imported by path, not via self.flakeModules: that would be infinite
  # recursion, since imports are needed before `self` exists.
  imports = [flakeModule];

  flake = {
    flakeModules.default = flakeModule;

    # `nix flake init -t github:marcolongol/omninix` for a whole fleet, or
    # `nix flake new -t …#<template> <dir>` for one piece.
    templates = {
      default = {
        path = ../../templates/default;
        description = "A fleet: one host, one user, a role, a profile and secrets";
      };
      host = {
        path = ../../templates/host;
        description = "A NixOS host (into hosts/<name>)";
      };
      darwin-host = {
        path = ../../templates/darwin-host;
        description = "A Mac (into hosts/<name>)";
      };
      user = {
        path = ../../templates/user;
        description = "A user (into users/<name>)";
      };
      role = {
        path = ../../templates/role;
        description = "A role (into roles/<name>)";
      };
      profile = {
        path = ../../templates/profile;
        description = "A profile (into profiles/<name>)";
      };
    };
  };

  perSystem = {pkgs, ...}: {
    formatter = pkgs.alejandra;
  };
}
