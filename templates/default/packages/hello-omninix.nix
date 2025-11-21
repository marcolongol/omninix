# Example package, auto-discovered from ./packages and exposed as
# packages.<system>.hello-omninix and pkgs.hello-omninix on every host. Written in callPackage form: the function args
# are filled from the (consumer's) nixpkgs package set.
{writeShellScriptBin}:
writeShellScriptBin "hello-omninix" ''
  echo "Hello from OmniNix!"
''
