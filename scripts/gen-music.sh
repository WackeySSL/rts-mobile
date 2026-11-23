#!/usr/bin/env bash
# Render the generated music from its parameter files (plan row P506, ADR 0041 section 5).
# Usage: bash scripts/gen-music.sh [--params PATH] [--out DIR] [--ffmpeg PATH]
# Output: assets/audio/music/<id>.ogg (stereo Ogg Vorbis, quality 3) through a temporary WAV and
#         ffmpeg with libvorbis. Deterministic for the same parameters on one platform.
# Env:    GODOT=<binary> (default: godot), MUSGEN_FFMPEG=<binary> (default: ffmpeg).
# Exit:   0 done, 1 invalid parameter file, encoder failure or Godot script error, 2 wrong argument
#         or missing parameter file, 3 Godot missing, 4 ffmpeg or its libvorbis encoder missing
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "gen-music: GODOT MISSING: '$GODOT' is not on PATH (set GODOT=/path/to/godot)." >&2
  exit 3
fi

bash scripts/seed-extension-list.sh
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

LOG="$(mktemp -t gen-music.XXXXXX)"
trap 'rm -f "$LOG"' EXIT
status=0
"$GODOT" --headless --path . --script res://tools/musgen/gen_music.gd -- "$@" 2>&1 | tee "$LOG" || status=$?
if grep -q -E 'SCRIPT ERROR|^ERROR:|Parse Error' "$LOG"; then
  echo "gen-music: Godot reported errors" >&2
  exit 1
fi
exit "$status"
