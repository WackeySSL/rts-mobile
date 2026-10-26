#!/usr/bin/env bash
# Regenerate the isometric SVG frames from the 3D models (ADR 0023 section 5, plan row P99).
# Usage: bash scripts/gen-art.sh --all | --model PATH [--model PATH ...] [--check]
#   --all          every model under assets/art/models
#   --model PATH   one model, project-relative (assets/art/models/fossil/heavy_tank.tres)
#   --check        write nothing; exit 1 when a frame or its .import is missing or differs
# Output: assets/art/iso/<faction>/<category>/<type_id>_<part>_d<NN>.svg and a "Keep File" .import
#         next to each. The output is deterministic: a second run writes nothing.
# Env:    GODOT=<binary> (default: godot).
# Exit:   0 done, also when nothing changed
#         1 a model is invalid, --check found a difference, or Godot printed a script error
#           (Godot itself exits 0 after those, so the log is scanned)
#         2 usage error
#         3 Godot missing
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
