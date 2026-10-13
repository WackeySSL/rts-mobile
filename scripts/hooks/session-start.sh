#!/usr/bin/env bash
# SessionStart hook: make sure the Godot toolchain exists and tell Claude what is available.
# Everything printed on stdout is added to Claude's context.
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
# The native build's tools (ADR 0013 section 8), pinned like scripts/cloud/setup.sh pins them. They
# are checked on their own, apart from Godot: a cached environment that has Godot but not them
# would never run the setup, and verify.sh would be RED in every session.
SCONS_VERSION="4.9.1"
CLANG_FORMAT_VERSION="20.1.8"
has_tool() { # command, exact version
  command -v "$1" >/dev/null 2>&1 && "$1" --version 2>/dev/null | grep -qF "$2"
}
if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  if ! command -v godot >/dev/null 2>&1 || ! has_tool scons "$SCONS_VERSION" || ! has_tool clang-format "$CLANG_FORMAT_VERSION"; then
    bash scripts/cloud/setup.sh >/dev/null 2>&1 || true
  fi
fi
if command -v godot >/dev/null 2>&1; then
  if command -v gdlint >/dev/null 2>&1; then LINT="ok"; else LINT="MISSING"; fi
  echo "Toolchain: Godot $(godot --version 2>/dev/null | head -n 1), gdtoolkit ${LINT}."
  echo "Verify with: bash scripts/verify.sh"
else
  echo "Godot is NOT available in this session. Write the code, push the branch and verify through CI (gh run watch)."
fi
NATIVE=""
has_tool scons "$SCONS_VERSION" || NATIVE="${NATIVE} SCons ${SCONS_VERSION}"
has_tool clang-format "$CLANG_FORMAT_VERSION" || NATIVE="${NATIVE} clang-format ${CLANG_FORMAT_VERSION}"
command -v g++ >/dev/null 2>&1 || NATIVE="${NATIVE} g++"
command -v readelf >/dev/null 2>&1 || NATIVE="${NATIVE} binutils"
if [ -z "$NATIVE" ]; then
  echo "Native build: SCons ${SCONS_VERSION}, clang-format ${CLANG_FORMAT_VERSION}, g++ and binutils are available."
else
  echo "Native build: MISSING${NATIVE}. verify.sh is RED without them (see scripts/cloud/setup.sh)."
fi
exit 0
