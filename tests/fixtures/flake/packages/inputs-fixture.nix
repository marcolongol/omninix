# Takes `inputs`, so OmniNix passes the consumer's flake inputs.
{
  writeText,
  inputs,
}:
writeText "inputs-fixture" (builtins.toJSON (inputs ? marker))
