#!/usr/bin/env bash
# PostToolUse hook: format and lint the GDScript file Claude just wrote or edited.
# Exit code 2 sends the lint output back to Claude so it fixes the problem right away.
INPUT="$(cat)"
if command -v jq >/dev/null 2>&1; then
  FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
else
  FILE="$(printf '%s' "$INPUT" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("tool_input", {}).get("file_path", ""))' 2>/dev/null)"
fi
case "$FILE" in
  *.gd) ;;
  *) exit 0 ;;
esac
[ -f "$FILE" ] || exit 0
case "$FILE" in
  */addons/*) exit 0 ;; # never touch third-party addons
esac
if command -v gdformat >/dev/null 2>&1; then
  gdformat "$FILE" >/dev/null 2>&1 || true
fi
if command -v gdlint >/dev/null 2>&1; then
  if ! OUT="$(gdlint "$FILE" 2>&1)"; then
    printf 'gdlint found problems in %s:\n%s\n' "$FILE" "$OUT" >&2
    exit 2
  fi
fi
exit 0
