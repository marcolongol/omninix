# The documentation site: an mdBook made of the README (as the landing page),
# the guides in docs/, and option reference pages generated from the modules.
# Build with `nix build .#docs`; open result/index.html.
{
  pkgs,
  lib,
  inputs,
  self,
}: let
  options = import ./options.nix {inherit pkgs lib inputs self;};
in
  pkgs.runCommand "omninix-docs" {nativeBuildInputs = [pkgs.mdbook];} ''
    mkdir -p src/options
    cp ${./book.toml} book.toml
    cp ${./SUMMARY.md} src/SUMMARY.md
    cp ${../.}/*.md src/

    # GitHub links point between the README and docs/; on the site they're
    # all pages of one book.
    sed 's#](docs/#](#g' ${../../README.md} > src/introduction.md
    sed -i 's#](\.\./README\.md#](introduction.md#g' src/*.md

    ${lib.concatStrings (lib.mapAttrsToList (name: doc: ''
        {
          printf '# %s\n\n%s\n\n' ${lib.escapeShellArg doc.title} ${lib.escapeShellArg doc.intro}
          cat ${doc.page}
        } > src/options/${name}.md
      '')
      options)}

    mdbook build --dest-dir $out
  ''
