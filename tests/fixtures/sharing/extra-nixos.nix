# Sharing fixture: declares a probe option so tests can see where it was imported.
{lib, ...}: {options.fixture.nixosExtra = lib.mkEnableOption "nixosExtra";}
