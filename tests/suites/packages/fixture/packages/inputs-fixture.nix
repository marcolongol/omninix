# Asks for `inputs`, so it gets the flake's inputs.
{
  writeText,
  inputs,
}:
writeText "inputs-fixture" (toString (inputs ? nixpkgs))
