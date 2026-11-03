# Not portable: a home location in a URL.
{lib, ...}: {options.roles.x.url = lib.mkOption {default = "https://example.com/forecast?latitude=43.1566&longitude=-77.6088";};}
