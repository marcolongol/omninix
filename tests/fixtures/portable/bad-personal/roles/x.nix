# Not portable: a personal value.
{lib, ...}: {options.roles.x.server = lib.mkOption {default = "10.0.0.4";};}
