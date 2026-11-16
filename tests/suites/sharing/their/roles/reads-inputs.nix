# Reads `inputs`, which only its own flake has: not shareable as is.
{inputs, ...}: {environment.etc.theirs-input.text = toString (inputs ? nixpkgs);}
