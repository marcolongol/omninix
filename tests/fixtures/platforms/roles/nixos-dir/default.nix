# NixOS only, as a directory.
{lib, ...}: {options.fixture.nixosDir = lib.mkOption {default = true;};}
