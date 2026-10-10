#!/usr/bin/env bash
# SessionStart hook: make sure the Godot toolchain exists and tell Claude what is available.
# Everything printed on stdout is added to Claude's context.
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && ! command -v godot >/dev/null 2>&1; then
  bash scripts/cloud/setup.sh >/dev/null 2>&1 || true
fi
if command -v godot >/dev/null 2>&1; then
  if command -v gdlint >/dev/null 2>&1; then LINT="ok"; else LINT="MISSING"; fi
  echo "Toolchain: Godot $(godot --version 2>/dev/null | head -n 1), gdtoolkit ${LINT}."
  echo "Verify with: bash scripts/verify.sh"
else
  echo "Godot is NOT available in this session. Write the code, push the branch and verify through CI (gh run watch)."
fi
exit 0
