Discovery fixture: a stray non-`.nix` file that MUST be ignored by
`forAllNixFiles` (regression guard: non-.nix files must not be keyed verbatim
and later imported, which causes eval errors).
