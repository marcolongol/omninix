#!/usr/bin/env bash
# OmniNix template smoke test.
#
# Initialises the template against the local checkout and asserts it evaluates
# through flakeModules.default.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMNINIX_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

check() {
  echo "-- [$1] nix flake show --"
  nix flake show >/dev/null || fail "[$1] nix flake show failed"

  echo "-- [$1] example host evaluates with expected groups --"
  nix eval --json '.#nixosConfigurations.example-host.config.users.users.example-user.extraGroups' \
    | grep -q 'wheel' || fail "[$1] example-user did not receive the expected 'wheel' group"

  echo "-- [$1] packagesDir packages are in host pkgs --"
  host_sys="$(nix eval --raw '.#nixosConfigurations.example-host.pkgs.stdenv.hostPlatform.system')"
  name="$(nix eval --raw '.#nixosConfigurations.example-host.pkgs.hello-omninix.name')"
  [ "$name" = "hello-omninix" ] || fail "[$1] pkgs.hello-omninix was '$name', expected hello-omninix"
  [ "$(nix eval --raw '.#nixosConfigurations.example-host.pkgs.hello-omninix.drvPath')" = \
    "$(nix eval --raw ".#packages.$host_sys.hello-omninix.drvPath")" ] \
    || fail "[$1] packages output and host pkgs disagree on hello-omninix"

  echo "-- [$1] roles.impermanent is imported from omninix, not re-exported --"
  [ "$(nix eval '.#nixosConfigurations.example-host.options.roles' --apply 'r: r ? impermanent')" = true ] \
    || fail "[$1] host is missing omninix's roles.impermanent"
  [ "$(nix eval '.#roles' --apply 'r: r ? impermanent')" = false ] \
    || fail "[$1] roles output re-exports omninix's impermanent"

  echo "-- [$1] nix flake check accepts the outputs (overlay arg names, …) --"
  nix flake check --no-build >/dev/null 2>&1 || fail "[$1] nix flake check --no-build failed"

  echo "-- [$1] overlays.packages is exported --"
  [ "$(nix eval '.#overlays' --apply 'o: builtins.attrNames o' --json)" = '["packages"]' ] \
    || fail "[$1] overlays.packages is missing"

  echo "-- [$1] standalone home config evaluates --"
  sv="$(nix eval --raw '.#homeConfigurations.example-user.config.home.stateVersion')"
  [ "$sv" = "26.05" ] || fail "[$1] home.stateVersion was '$sv', expected 26.05"
}

echo "== OmniNix template smoke test =="
cd "$TEST_DIR"

nix flake init -t "$OMNINIX_DIR" >/dev/null
# Point the template at the local checkout instead of the published flake.
sed -i 's|omninix.url = "github:marcolongol/omninix";|omninix.url = "path:'"$OMNINIX_DIR"'";|' flake.nix
git init -q
git add -A
nix flake lock >/dev/null

check flakeModules.default
echo "-- [flakeModules.default] formatter --"
[ "$(nix eval --raw ".#formatter.$(nix eval --raw --impure --expr builtins.currentSystem).pname")" = "alejandra" ] \
  || fail "formatter is not alejandra"

echo "PASS: template initialises and evaluates via flakeModules.default"
