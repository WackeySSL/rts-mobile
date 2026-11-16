#!/usr/bin/env bash
# Regenerate the intro art (plan row P520, ADR 0043): the icon foreground's layer SVGs under
# assets/art/svg/intro/ and the boot splash PNG assets/art/splash/boot_splash.png, from the
# committed icon and brand SVGs (never edited).
# Usage: bash scripts/gen-intro.sh [--check]   (--check writes nothing and exits 4 on a difference)
# Env:   GODOT=<binary> (default: godot).
# Exit:  0 done, 1 Godot printed a script error, 2 a wrong argument, 3 Godot missing, 4 --check
#        found a difference
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "gen-intro: GODOT MISSING: '$GODOT' is not on PATH (set GODOT=/path/to/godot)." >&2
  exit 3
fi

bash scripts/seed-extension-list.sh
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

LOG="$(mktemp -t gen-intro.XXXXXX)"
trap 'rm -f "$LOG"' EXIT
status=0
"$GODOT" --headless --path . --script res://tools/artgen/gen_intro.gd -- "$@" 2>&1 | tee "$LOG" || status=$?
if grep -q -E 'SCRIPT ERROR|^ERROR:|Parse Error' "$LOG"; then
  echo "gen-intro: Godot reported errors" >&2
  exit 1
fi
exit "$status"
