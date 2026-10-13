#!/usr/bin/env bash
# Writes .godot/extension_list.cfg before a headless editor start (ADR 0013 section 9). Godot 4.7.2
# aborts at the end of a fresh `godot --headless --import` (exit 134) when its first scan finds a
# GDExtension that registers a class; with the list in place it loads the extension at startup, as
# on every later run. The list holds every *.gdextension the first scan would see (folders with a
# .gdignore or a dot name are skipped: godot-cpp's example.gdextension stays out). The file is
# replaced, so a run is idempotent and drops a stale entry; no extension, no file.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

list=".godot/extension_list.cfg"
found="$(find . -mindepth 1 -type d \( -name '.*' -o -exec test -e '{}/.gdignore' ';' \) -prune -o \
  -type f -name '*.gdextension' -print | sed 's|^\./|res://|' | LC_ALL=C sort)"
if [ -z "$found" ]; then
  rm -f "$list"
elif [ ! -f "$list" ] || [ "$(cat "$list")" != "$found" ]; then
  mkdir -p .godot
  printf '%s\n' "$found" >"$list"
fi
