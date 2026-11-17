# My fleet

Built with [OmniNix](https://github.com/marcolongol/omninix).

1. On the machine, replace `hosts/example-host/hardware-configuration.nix`
   with the output of `nixos-generate-config --show-hardware-config`.
2. Rename `hosts/example-host` to the machine's name, and `users/example-user.nix`
   to your username (update `omninix.hostUsers` in the host to match).
3. `sudo nixos-rebuild switch --flake .#<host>`
4. Give your user a password: see `secrets/README.md`.

Add more with `nix flake new -t github:marcolongol/omninix#<template> <dir>`,
where the template is `host`, `darwin-host`, `user`, `role` or `profile`.
