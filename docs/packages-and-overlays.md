# Packages and overlays

## Your own packages

```nix
omninix.packagesDir = ./packages;
```

Every `.nix` file there is a package in `callPackage` form:

```nix
# packages/hello.nix
{writeShellScriptBin}: writeShellScriptBin "hello" "echo hi"
```

You get it in two places:

- **`pkgs.hello`** on every host and in every Home Manager config, so modules
  can use it directly. No overlay to write.
- **`packages.<system>.hello`** as a flake output (`nix build .#hello`).

A package that takes `inputs` gets your flake's inputs, `self` included, for
when it is built from the flake's own outputs:

```nix
# packages/image.nix
{callPackage, inputs}:
callPackage ../image {
  inherit (inputs.self.homeConfigurations.alice) activationPackage;
}
```

A package whose `meta.platforms` excludes a system is left out of
`packages.<system>` there (it is still `pkgs.<name>`).

### Sharing them

Your packages are also exported as **`overlays.packages`**, so another flake
can add them to its own `pkgs`:

```nix
nixpkgs.overlays = [inputs.my-flake.overlays.packages];
```

It holds `packagesDir` only, never your `overlaysDir` overrides, which would
rebuild other people's packages. It only adds packages. Using one that would
replace an existing package, or one that takes `inputs` (only your flake has
those), is an error; the other packages still work. Define your own
`flake.overlays.packages` to replace it.

## Overriding nixpkgs

```nix
omninix.overlaysDir = ./overlays;
```

Every `.nix` file there is one overlay, applied in file-name order to every
host, home config and package build:

```nix
# overlays/freecad.nix
final: prev: {
  freecad = prev.freecad.overrideAttrs (old: {
    # ...
  });
}
```

Your `packagesDir` packages are applied first, so an overlay can override them
too.

If the directory has a `default.nix` (or you point `overlaysDir` at a single
file), that is imported instead and must return a **list** of overlays.

## Unfree packages

Off by default. Opt the whole flake in with:

```nix
omninix.allowUnfree = true;
```

This applies to hosts, home configs, packages and the flake-parts `perSystem`
pkgs alike.

For a single host instead, set `nixpkgs.config.allowUnfree = true;` in its
file.

## A different nixpkgs per host

Every host builds from your flake's `nixpkgs` by default. To put one on
another channel, say unstable on a desktop while servers stay on stable, add
the inputs and point the host at them:

```nix
inputs = {
  nixpkgs-unstable.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  home-manager-unstable = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs-unstable";
  };
};

omninix.hostInputs.desktop = {
  nixpkgs = inputs.nixpkgs-unstable;
  home-manager = inputs.home-manager-unstable;
};
```

The entry replaces those inputs for that host only: it's built with that
nixpkgs, gets that Home Manager module, and its modules see the swapped values
in `inputs`. Override `home-manager` together with `nixpkgs`, or every user on
the host gets a version-mismatch warning. Any other input can be swapped the
same way, e.g. a patched `sops-nix`.

`omninix.userInputs.<user>` does the same for a standalone home, for example a
Mac on unstable.

Your overlays and `packagesDir` packages apply on top of the host's nixpkgs.
The flake's `packages` outputs and `perSystem` pkgs stay on the flake's own
`nixpkgs`. A name in `hostInputs` or `userInputs` that isn't a host or user is
an error.

## `perSystem` pkgs (flake-parts)

With the flake-parts module, `perSystem`'s `pkgs` is the same package set the
hosts use: your overlays, packages and unfree setting included.

```nix
perSystem = {pkgs, ...}: {
  formatter = pkgs.alejandra;
  devShells.default = pkgs.mkShell {packages = [pkgs.hello];};
};
```

To use a different package set, set `_module.args.pkgs` with a plain definition
(or `lib.mkForce`). `lib.mkDefault` would clash with OmniNix's own default.

A `perSystem.packages.<name>` of your own replaces only that flake output. Hosts
keep the `packagesDir` version as `pkgs.<name>`.
