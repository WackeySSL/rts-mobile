#!/usr/bin/env bash
# The same-scene sheet (ADR 0050 section 8, plan row P629): writes the sheet PNG a PR attaches and
# names the bands the roster misses.
# Usage: bash scripts/same-scene.sh OUT.png
# Env:   GODOT=<binary> (default: godot).
# Exit:  0 the look holds, 1 a band is missed, 2 a wrong argument, 3 Godot missing
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "same-scene: GODOT MISSING: '$GODOT' is not on PATH (set GODOT=/path/to/godot)." >&2
  exit 3
fi
exec "$GODOT" --headless --path . -s res://tools/artgen/same_scene.gd -- "$@"
