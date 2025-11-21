#!/usr/bin/env bash
# OmniNix template smoke test.
#
# Honest replacement for the old test-basic-build.sh (which ran `nix flake check
# ... || true` and then unconditionally printed success). This initialises the
# template against the local checkout and asserts it actually evaluates, with
# real exit codes — any failure fails the script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMNINIX_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

echo "== OmniNix template smoke test =="
cd "$TEST_DIR"

nix flake init -t "$OMNINIX_DIR" >/dev/null
# Point the template at the local checkout instead of the published flake.
sed -i 's|omninix.url = "github:marcolongol/omninix";|omninix.url = "path:'"$OMNINIX_DIR"'";|' flake.nix
git init -q
git add -A
nix flake lock >/dev/null

echo "-- nix flake show --"
nix flake show >/dev/null || fail "nix flake show failed"

echo "-- example host evaluates with expected groups --"
nix eval --json '.#nixosConfigurations.example-host.config.users.users.example-user.extraGroups' \
  | grep -q 'wheel' || fail "example-user did not receive the expected 'wheel' group"

echo "-- packagesDir packages are in host pkgs --"
name="$(nix eval --raw '.#nixosConfigurations.example-host.pkgs.hello-omninix.name')"
[ "$name" = "hello-omninix" ] || fail "pkgs.hello-omninix was '$name', expected hello-omninix"
[ "$(nix eval --raw '.#nixosConfigurations.example-host.pkgs.hello-omninix.drvPath')" = \
  "$(nix eval --raw ".#packages.$(nix eval --raw --impure --expr builtins.currentSystem).hello-omninix.drvPath")" ] \
  || fail "packages output and host pkgs disagree on hello-omninix"

echo "-- standalone home config evaluates --"
sv="$(nix eval --raw '.#homeConfigurations.example-user.config.home.stateVersion')"
[ "$sv" = "26.05" ] || fail "home.stateVersion was '$sv', expected 26.05"

echo "PASS: template initialises and evaluates"
