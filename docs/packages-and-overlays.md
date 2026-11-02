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
