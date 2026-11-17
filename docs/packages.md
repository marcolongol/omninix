# Packages, overlays and inputs

## Your own packages

```nix
omninix.packagesDir = ./packages;
```

Each file is a package in `callPackage` form:

```nix
# packages/hello-fleet.nix
{writeShellScriptBin}: writeShellScriptBin "hello-fleet" "echo hi"
```

It becomes:

- `pkgs.hello-fleet` on every host and in every home;
- `packages.<system>.hello-fleet`, on systems its `meta.platforms` allows;
- part of `overlays.packages`, for other flakes ([below](#sharing-them)).

Packages can use each other: `{echo-hello, ...}:` gets your own `echo-hello`.
A package that asks for `inputs` gets your flake's:

```nix
{writeText, inputs}: writeText "rev" (inputs.self.rev or "dirty")
```

## Overlays

```nix
omninix.overlaysDir = ./overlays;
```

Each file is one overlay, applied in name order after your packages, so an
overlay can override them too:

```nix
# overlays/freecad.nix
final: prev: {
  freecad = prev.freecad.overrideAttrs (old: {
    # ...
  });
}
```

To keep several overlays in one file, combine them with
`lib.composeManyExtensions`.

## Unfree packages

Off by default. For the whole fleet:

```nix
omninix.allowUnfree = true;
```

For one host, set `nixpkgs.config.allowUnfree = true;` in its file instead.

## perSystem `pkgs` (flake-parts)

When you use `packagesDir`, `overlaysDir` or `allowUnfree`, flake-parts'
`perSystem` gets the same package set as your hosts, so dev shells and checks
see your packages:

```nix
perSystem = {pkgs, ...}: {
  devShells.default = pkgs.mkShell {packages = [pkgs.hello-fleet];};
};
```

It's a default: set `_module.args.pkgs` in `perSystem` to use your own.

## A different nixpkgs for one host or user

`hostInputs` and `userInputs` override flake inputs for one host or user.
Everything about it follows: the system (or home), Home Manager, sops-nix, and
the `inputs` its modules receive.

```nix
inputs.nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
inputs.home-manager-unstable = {
  url = "github:nix-community/home-manager";
  inputs.nixpkgs.follows = "nixpkgs-unstable";
};

omninix.hostInputs.pi = {
  nixpkgs = inputs.nixpkgs-unstable;
  home-manager = inputs.home-manager-unstable; # Home Manager must match nixpkgs
};
omninix.userInputs.alice.nixpkgs = inputs.nixpkgs-unstable; # her standalone home
```

A name that isn't a host or user is an error, so a typo can't be ignored.

## Sharing them

`overlays.packages` gives other flakes your packages:

```nix
nixpkgs.overlays = [their-fleet.overlays.packages];
```

It only adds packages: one that would replace a package they already have,
or that asks for your `inputs`, fails when used instead of silently changing
their system. `overlaysDir` isn't part of it: those are your own overrides.
