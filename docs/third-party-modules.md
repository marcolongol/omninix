# Third-party modules

disko, stylix, nixos-hardware, agenix, a private flake: they're all plain
modules, and OmniNix has no list of supported ones. You import them.

OmniNix imports only the modules of inputs it builds on, when your flake has
them: **home-manager**, **sops-nix**, and **nix-darwin** for Macs.

## Fleet-wide

Give them to `extra*` by name; they're imported into every host or every home:

```nix
omninix = {
  extraNixosModules = {
    disko = inputs.disko.nixosModules.disko;
    stylix = inputs.stylix.nixosModules.stylix;
  };
  extraHomeModules = {
    nixvim = inputs.nixvim.homeModules.nixvim;
  };
};
```

Most such modules do nothing until configured, so importing them everywhere is
harmless. Each must be imported only once: don't also import it in a host.

## Per host

Your flake's inputs are a module argument in every host, role, user and
profile:

```nix
# hosts/laptop/default.nix
{inputs, ...}: {
  imports = [
    inputs.nixos-hardware.nixosModules.framework-13-7040-amd
    inputs.disko.nixosModules.disko
    ./disk-config.nix
  ];
}
```

## In homes

The same works for Home Manager modules, in a user file, a profile, or
fleet-wide with `extraHomeModules`. Home Manager modules that a NixOS module
brings along (impermanence does) need nothing from you.

## Configuring them from a role

A role that configures a third-party module should check the module is there,
and say what's missing if it isn't: see
[Guard what you configure](sharing.md#3-guard-what-you-configure).
