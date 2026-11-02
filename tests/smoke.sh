#!/usr/bin/env bash
# OmniNix template smoke test.
#
# Initialises the template against the local checkout and asserts it evaluates
# through flakeModules.default, then swaps in a mkFlake flake.nix on the same
# scaffold and lock and asserts both entry points build the same host.
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

  echo "-- [$1] standalone home config evaluates --"
  sv="$(nix eval --raw '.#homeConfigurations.example-user.config.home.stateVersion')"
  [ "$sv" = "26.05" ] || fail "[$1] home.stateVersion was '$sv', expected 26.05"
}

toplevel() {
  nix eval --raw '.#nixosConfigurations.example-host.config.system.build.toplevel.drvPath'
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
via_module="$(toplevel)"

# Same scaffold and lock, mkFlake entry point.
cat >flake.nix <<NIX
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";
    omninix.url = "path:$OMNINIX_DIR";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = {omninix, ...} @ inputs:
    omninix.lib.omninix.mkFlake inputs {
      hostsDir = ./hosts;
      rolesDir = ./roles;
      extraRoles = omninix.roles;
      usersDir = ./users;
      profilesDir = ./profiles;
      extraProfiles = omninix.profiles;
      packagesDir = ./packages;
      systems = ["x86_64-linux" "aarch64-linux"];
    };
}
NIX
git add -A
nix flake lock >/dev/null

check mkFlake
[ "$(toplevel)" = "$via_module" ] || fail "mkFlake and flakeModules.default build different example-host toplevels"

echo "PASS: template initialises and evaluates via flakeModules.default and mkFlake"
