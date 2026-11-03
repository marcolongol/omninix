# Sharing fixture: declares a probe option so tests can see where it was imported.
{lib, ...}: {options.fixture.profilePublic = lib.mkEnableOption "profilePublic";}
