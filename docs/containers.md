# Containers and images

OmniNix has no container feature of its own: two things it already does
cover both kinds of container.

- **A distroless OCI image** (Docker, podman, Kubernetes) is a package that
  happens to build an image.
- **A system container** (LXC, Proxmox) is a host, built as an image.

## Distroless images: a package

An image is just another file in [`packagesDir`](packages.md), built with
nixpkgs' `dockerTools`:

```nix
# packages/hello-image.nix
{
  dockerTools,
  hello,
}:
dockerTools.buildLayeredImage {
  name = "hello";
  tag = "latest";
  config.Entrypoint = ["${hello}/bin/hello"];
}
```

```bash
nix build .#hello-image
podman load < result
podman run --rm hello:latest
```

The image holds the entrypoint's closure and nothing else: no shell, no
package manager, no init. Like any package in `packagesDir`, it gets your
other packages and the fleet's overlays, so it can ship one of your own
packages, and it is also `pkgs.hello-image` on your hosts (nothing is built
unless something uses it).

`config` is the OCI image config: `User` (to run as non-root, e.g.
`"1000:1000"`), `Env`, `ExposedPorts`, `WorkingDir`. For files outside the
store, such as CA certificates, add packages to `contents`, or make them in
`extraCommands`. The [dockerTools section of the nixpkgs
manual](https://nixos.org/manual/nixpkgs/stable/#sec-pkgs-dockerTools) has
the rest, including `streamLayeredImage`, which streams the image instead of
storing it.

## System containers: a host

Every host can be built as an image: `config.system.build.images` holds a
variant per platform. For a Proxmox LXC container, import the Proxmox module
in the host itself:

```nix
# hosts/ct/default.nix
{modulesPath, ...}: {
  imports = ["${modulesPath}/virtualisation/proxmox-lxc.nix"];
  system.stateVersion = "26.05";

  # Keep the host's OmniNix name; otherwise Proxmox sets the hostname.
  proxmoxLXC.manageHostName = true;
}
```

```bash
nixos-rebuild build-image --flake .#ct --image-variant proxmox-lxc
```

Upload the tarball to Proxmox as a CT template and create the container from
it, with OS type `nixos`.

Import the module in the host file rather than relying on the image variant
alone: the variant adds it only to the image, so the host's next
`nixos-rebuild switch` would drop it. With it imported, the container is a
host like the others: roles, users, secrets, and deployment
([Deploying](deployment.md)) all work as on a machine.

`proxmoxLXC.manageNetwork = true` configures networking from the host's
config instead of from Proxmox. Plain LXC and Incus use the `lxc` and
`lxc-metadata` variants instead; `proxmox` is a VM disk image.
