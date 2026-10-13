#!/usr/bin/env bash
# Run the gdUnit4 test suites headless. Works from any cwd, locally and in CI.
# Usage: bash scripts/run-tests.sh [gdUnit4 args]   (default: -a res://tests)
# Env:   GODOT=<binary> (default: godot)
#        RUN_TESTS_SKIP_IMPORT=1 skips the import step when the caller just ran it.
# Exit:  0 only if at least one test ran and none failed, errored or leaked orphans.
#        1 no tests ran or results.xml is missing
#        3 Godot, the gdUnit4 addon or the native library is missing (this script does not build)
#        otherwise gdUnit4's own code (100 failures, 101 orphans, 105 script errors)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

GODOT="${GODOT:-godot}"
REPORT_DIR="reports/gdunit" # must be relative: gdUnit4 maps "/abs" to res://abs
RESULTS="${REPORT_DIR}/report_1/results.xml"

if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "GODOT MISSING: '$GODOT' is not on PATH (set GODOT=/path/to/godot)." >&2
  exit 3
fi
if [ ! -f addons/gdUnit4/bin/GdUnitCmdTool.gd ]; then
  echo "gdUnit4 missing: addons/gdUnit4 is not vendored." >&2
  exit 3
fi

# The native suites never skip (ADR 0013 section 9): the generated .gdextension and its host library
# must exist. verify.sh builds first.
case "$(uname -m)" in aarch64 | arm64) host_arch="arm64" ;; *) host_arch="x86_64" ;; esac
native_lib="$(sed -n "s|^linux\\.debug\\.${host_arch}[[:space:]]*=[[:space:]]*\"res://\\(.*\\)\"[[:space:]]*\$|\\1|p" native/sim_kernels.gdextension 2>/dev/null | head -n 1 || true)"
if [ -z "$native_lib" ] || [ ! -s "$native_lib" ]; then
  echo "NATIVE LIBRARY MISSING: run bash scripts/build-native.sh first" >&2
  exit 3
fi

# The CLI resolves class_name via .godot/global_script_class_cache.cfg. On a fresh
# clone (no .godot/) or after adding a class_name, it fails with "Parse Error" and
# Godot still exits 0, so always refresh the cache first. The extension list is seeded first.
if [ "${RUN_TESTS_SKIP_IMPORT:-0}" != "1" ]; then
  bash scripts/seed-extension-list.sh
  "$GODOT" --headless --path . --import
fi

# Fresh report dir each run; .gdignore keeps Godot from importing report assets.
rm -rf "$REPORT_DIR"
mkdir -p "$REPORT_DIR"
: >reports/.gdignore

ARGS=("$@")
if [ ${#ARGS[@]} -eq 0 ]; then ARGS=(-a res://tests); fi

set +e
"$GODOT" --headless --path . \
  -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --ignoreHeadlessMode -c -rd "$REPORT_DIR" -rc 1 "${ARGS[@]}" 2>&1 |
  sed -e $'s/\x1b\\[2J//g' -e $'s/\x1b\\[H//g' # drop gdUnit4's clear-screen codes
status=${PIPESTATUS[0]}
set -e

if [ "$status" -ne 0 ]; then
  echo "run-tests: gdUnit4 exited with ${status} (100 failures/errors, 101 orphans, 105 script errors)" >&2
  exit "$status"
fi
# Exit 0 is also returned when the runner script fails to load or finds no tests.
tests=""
if [ -f "$RESULTS" ]; then
  tests="$(sed -n 's/.*<testsuites [^>]*tests="\([0-9]*\)".*/\1/p' "$RESULTS" | head -n 1)"
fi
if [ -z "$tests" ] || [ "$tests" -eq 0 ]; then
  echo "run-tests: no test cases ran (missing ${RESULTS} or tests=0)" >&2
  exit 1
fi
echo "run-tests: ${tests} test cases passed"
