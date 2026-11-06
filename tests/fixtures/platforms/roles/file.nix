# NixOS only, as a file.
{lib, ...}: {options.fixture.file = lib.mkOption {default = true;};}
