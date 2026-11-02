# OmniNix Test Suite

Automated tests for the OmniNix framework. The eval tests run as flake checks
(`lib.runTests`, no extra inputs); the VM test boots a real host; the smoke test
exercises the template.

## Running

```bash
./tests/run-all-tests.sh        # eval checks + VM test + template smoke
FAST=1 ./tests/run-all-tests.sh # skip the heavy VM test
nix flake check                 # eval checks + VM test (no template smoke)
```

## Layout

| File | Layer | What it covers |
|------|-------|----------------|
| `lib-tests.nix` | 1 — pure lib | `forAllNixFiles`/.nix filter, `mkDirMap`, `mapAttrsMaybe`, `pick`/`drop` (+ throw), `validations.assert*` |
| `flake-tests.nix` | 2b — flake entry points | `mkFlake` output shape on `fixtures/flake` (output names, no `packages` without `packagesDir`, `systems` default, package drv == host `pkgs` drv), and `flakeModules.default` against `mkFlake` on the same fixture: consumer inputs, host/home/discovered-path parity, packages merge and local override, overlaid and overridable `perSystem` pkgs, `homeConfigurations` merge, double-import dedup, typed options, `extraRoles` one-definition-per-name |
| `config-tests.nix` | 2 — config behaviour | Evaluates fixture hosts via `mkNixosConfigurations` and asserts on `config.*`: fail-closed passwords, opt-in groups, per-host `hostSystems`, impermanence integration assertion, `allowUnfree`, the `omninix.*` namespace |
| `vm-test.nix` | 4 — integration | Boots a host with `runNixOSTest`; asserts the user is created, has `wheel`, lacks `docker`, has a home dir and a password hash |
| `checks.nix` | harness | Aggregates the eval suites into `checks.<system>.eval` (fails, printing offending cases, if any test ≠ expected) and exposes `checks.<system>.vm` on Linux |
| `smoke.sh` | 3 — template | `nix flake init -t` against the local checkout, asserts it evaluates via `flakeModules.default` (incl. formatter, `pkgs`/`packages` parity on the host's system), then swaps in a `mkFlake` flake.nix on the same scaffold and asserts the same example-host toplevel |
| `fixtures/discovery/` | — | Inputs for the discovery tests, including a stray `README.md`/`.txt` that must be ignored |

## How the eval checks fail

`checks.<system>.eval` runs `lib.runTests` over Layers 1, 2 and 2b. `runTests` returns
the list of cases whose `expr` differs from `expected`; the derivation builds
iff that list is empty, otherwise it prints each failing case (name, expected,
got) and exits non-zero. No `|| true`, no unconditional "passed".

## Adding tests

- **Lib/config test:** add a `testSomething = { expr = ...; expected = ...; };`
  entry to `lib-tests.nix` or `config-tests.nix`. Names should start with
  `test`. For expected-failure cases assert on
  `(builtins.tryEval expr).success`.
- **VM assertion:** extend the `testScript` in `vm-test.nix`.

## CI

Deferred for now. When added, CI is just:

```yaml
- run: nix flake check               # eval + VM
- run: bash tests/run-all-tests.sh   # + template smoke
```

The module tests evaluate full flake-parts flakes, so `checks.<system>.eval` takes about 16s and 2.25 GB (was about 8s / 0.9 GB).
