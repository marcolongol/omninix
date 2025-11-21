Discovery fixture: a stray non-`.nix` file that MUST be ignored by
`forAllNixFiles` (regression guard for H2 — non-.nix files were keyed verbatim
and later imported, causing eval errors).
