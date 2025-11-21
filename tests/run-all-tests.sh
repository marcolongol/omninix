#!/usr/bin/env bash
# Run the full OmniNix test suite.
#
#   - `nix flake check` builds the eval checks (Layer 1 lib + Layer 2
#     config-behaviour) and, on Linux, the Layer 4 VM boot test.
#   - tests/smoke.sh initialises the template and asserts it evaluates.
#
# FAST=1 skips the heavy VM test (builds only the eval check + smoke), useful
# for a quick local loop.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMNINIX_DIR="$(dirname "$SCRIPT_DIR")"

echo "╔════════════════════════════════════╗"
echo "║          OmniNix Test Suite          ║"
echo "╚════════════════════════════════════╝"

if [ "${FAST:-0}" = "1" ]; then
  system="$(nix eval --raw --impure --expr builtins.currentSystem)"
  echo "== eval checks (FAST: skipping VM) =="
  nix build "$OMNINIX_DIR#checks.${system}.eval" --no-link --print-build-logs
else
  echo "== nix flake check (eval + VM tests) =="
  nix flake check "$OMNINIX_DIR" --print-build-logs
fi

echo "== template smoke test =="
bash "$SCRIPT_DIR/smoke.sh"

echo ""
echo "🎉 All OmniNix tests passed."
