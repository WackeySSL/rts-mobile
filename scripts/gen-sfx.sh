#!/usr/bin/env bash
# Render the generated sound effects from their parameter files (plan row P507, ADR 0041 section 7).
# Usage: bash scripts/gen-sfx.sh [--params PATH] [--check]
#          no argument            every tools/sfxgen/params/*.tres
#          --params PATH          one parameter file (res://... or a path from the project root)
#          --out DIR              write under DIR instead of res://assets/audio/sfx
#          --check                write nothing; name the WAVs that differ
# Output: assets/audio/sfx/<family>/<id>.wav (mono, 16 bit). Deterministic: a second run writes
#         nothing.
# Note:   the output is byte-identical for the same parameters on one platform and Godot version
#         (the synthesis uses the float sin and pow of the C library). --check is therefore a
#         local tool, not a CI gate.
# Env:    GODOT=<binary> (default: godot).
# Exit:   0 done (--check: nothing differs), 1 invalid parameter file, write failure or Godot
#         script error, 2 wrong argument or missing parameter file, 3 Godot missing, 4 --check found a difference
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "gen-sfx: GODOT MISSING: '$GODOT' is not on PATH (set GODOT=/path/to/godot)." >&2
  exit 3
fi

bash scripts/seed-extension-list.sh
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

LOG="$(mktemp -t gen-sfx.XXXXXX)"
trap 'rm -f "$LOG"' EXIT
status=0
"$GODOT" --headless --path . --script res://tools/sfxgen/gen_sfx.gd -- "$@" 2>&1 | tee "$LOG" || status=$?
if grep -q -E 'SCRIPT ERROR|^ERROR:|Parse Error' "$LOG"; then
  echo "gen-sfx: Godot reported errors" >&2
  exit 1
fi
exit "$status"
