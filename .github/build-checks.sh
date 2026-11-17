#!/usr/bin/env bash
# Build every flake check for one system, in one `nix build`.
#
#   build-checks.sh <system> [--no-vms] [extra nix args...]
#
# --no-vms leaves out the VM tests (vm-*), for runners without KVM.
set -euo pipefail
system=$1
shift
skip='^$'
if [[ ${1:-} == --no-vms ]]; then
  skip='^vm-'
  shift
fi
# A read loop, not mapfile: macOS runners have bash 3.2.
names=()
while IFS= read -r name; do
  names+=("$name")
done < <(nix eval --json ".#checks.$system" --apply builtins.attrNames "$@" | jq -r '.[]' | grep -Ev "$skip")
echo "Building ${#names[@]} checks for $system: ${names[*]}"
nix build -L "${names[@]/#/.#checks.$system.}" "$@"
