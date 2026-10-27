#!/usr/bin/env bash
# Regenerate the isometric SVG frames from the 3D models (ADR 0023 section 5, plan rows P99, P99b).
# Usage: bash scripts/gen-art.sh [--all | --model PATH] [--check]
#          no argument or --all   every model under assets/art/models
#          --model PATH           one model (res://assets/art/models/<faction>/<id>.tres, or the
#                                 same path from the project root)
#          --check                write nothing; name the files that differ
# Output: assets/art/iso/<faction>/<category>/<type_id>_<part>_d<NN>.svg (parts hull, turret, head,
#         shadow) with a "Keep File" .import next to each, <type_id>_sheet.tres, the item card
#         assets/art/iso/icons/item_<type_id>.svg and assets/art/iso/index.tres. The output is
#         deterministic: a second run writes nothing. Godot writes the .import of a new card on the
#         next import (any test run or this script's first step).
# Env:    GODOT=<binary> (default: godot).
# Exit:   0 done, also when nothing changed (--check: nothing differs)
#         1 a model is invalid, or Godot printed a script error (Godot itself exits 0 after those, so
#           the log is scanned)
#         2 a wrong argument, or --model names a file that is not a model
#         3 Godot missing
#         4 --check found a difference
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "gen-art: GODOT MISSING: '$GODOT' is not on PATH (set GODOT=/path/to/godot)." >&2
  exit 3
fi

# The generator's classes are global ones: the class cache must know them (a fresh clone has none).
bash scripts/seed-extension-list.sh
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

LOG="$(mktemp -t gen-art.XXXXXX)"
trap 'rm -f "$LOG"' EXIT
status=0
"$GODOT" --headless --path . --script res://tools/artgen/gen_art.gd -- "$@" 2>&1 | tee "$LOG" || status=$?
if grep -q -E 'SCRIPT ERROR|^ERROR:|Parse Error' "$LOG"; then
  echo "gen-art: Godot reported errors" >&2
  exit 1
fi
exit "$status"
