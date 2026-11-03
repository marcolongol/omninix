# Not portable: reads a flake input around the argument list.
{config, ...}: {environment.etc.x.text = config._module.specialArgs.inputs.foo or "";}
