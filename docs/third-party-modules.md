# Third-party modules

OmniNix has no list of supported integrations. disko, stylix, nixos-hardware,
agenix, impermanence, a private flake: they're all plain modules, and your flake
`inputs` are available in every host, role, user and profile. You just import
them.

Only two inputs are wired up automatically when you declare them:
**home-manager** and **sops-nix**.

## Fleet-wide

Put a small wrapper in a modules directory; every file there is imported into
every host (or every user):

```nix
omninix = {
  nixosModulesDir = ./modules/nixos; # every .nix -> every host
  homeManagerModulesDir = ./modules/home; # every .nix -> every user
};
```

```nix
# modules/nixos/third-party.nix
{inputs, ...}: {
  imports = [
    inputs.disko.nixosModules.disko
    inputs.impermanence.nixosModules.impermanence
  ];
}
```

## One host

```nix
# hosts/laptop/default.nix
{inputs, ...}: {
  imports = [inputs.nixos-hardware.nixosModules.dell-xps-13-9310];
}
```

## Behind a role

`imports` can't depend on a role's `enable` option (NixOS resolves imports
before it reads any config). So import the module unconditionally, and only gate
the **settings** on the role:

```nix
# roles/secrets.nix
{config, lib, inputs, ...}: {
  imports = [inputs.agenix.nixosModules.default];

  options.roles.secrets.enable = lib.mkEnableOption "agenix secrets";
  config = lib.mkIf config.roles.secrets.enable {
    age.secrets.api-key.file = ../secrets/api-key.age;
  };
}
```

Most modules do nothing until you configure them, so importing them everywhere
is harmless.

## Import each module once

Some modules, impermanence among them, break when imported twice ("option ...
is already declared"). Import them in exactly one place. OmniNix's own
`roles.impermanent` never imports impermanence for that reason; it expects you
to.

## Home Manager modules

The same works on the user side: `inputs.<x>.homeManagerModules.<y>` can be
imported in any user, profile, or `homeManagerModulesDir` file, and it works in
standalone `homeConfigurations` too.
