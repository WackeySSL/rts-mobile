#!/usr/bin/env bash
# Full verification for rts-mobile: format, lint, import, unit tests, headless AI-vs-AI smoke.
# Prints a VERIFY SUMMARY block and exits 0 only when everything is GREEN.
# Godot can exit 0 after runtime script errors, so the combined log is scanned as well.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2

if ! command -v godot >/dev/null 2>&1; then
  echo "GODOT MISSING: no 'godot' on PATH in this session."
  echo "Push the branch and verify through CI instead: gh run watch"
  exit 3
fi

LOG="$(mktemp -t verify.XXXXXX)"
FAILED=()

run_step() {
  local name="$1"
  shift
  echo "::: ${name}"
  if ! "$@" 2>&1 | tee -a "$LOG"; then
    FAILED+=("$name")
  fi
}

GD_DIRS=()
for d in game tests scenes; do
  if [ -d "$d" ]; then GD_DIRS+=("$d"); fi
done

if [ ${#GD_DIRS[@]} -gt 0 ]; then
  if command -v gdformat >/dev/null 2>&1 && command -v gdlint >/dev/null 2>&1; then
    run_step "format (gdformat --check)" gdformat --check "${GD_DIRS[@]}"
    run_step "lint (gdlint)" gdlint "${GD_DIRS[@]}"
  else
    echo "gdtoolkit missing: pip install 'gdtoolkit==4.5.0'"
    FAILED+=("gdtoolkit missing")
  fi
fi

run_step "import" godot --headless --path . --import

if [ -f scripts/run-tests.sh ]; then
  run_step "unit tests (gdUnit4)" env RUN_TESTS_SKIP_IMPORT=1 bash scripts/run-tests.sh
else
  echo "scripts/run-tests.sh is missing (created in Phase 0)"
  FAILED+=("run-tests.sh missing")
fi

if [ -f scripts/run-sim-smoke.sh ]; then
  run_step "sim smoke (3 seeded AI-vs-AI matches)" bash scripts/run-sim-smoke.sh --matches 3
else
  echo "::: sim smoke skipped (scripts/run-sim-smoke.sh not created yet)"
fi

# Godot errors that did not change any exit code.
PATTERN='SCRIPT ERROR|^ERROR:|Parse Error'
ALLOW="$(mktemp -t allow.XXXXXX)"
if [ -f scripts/verify-allowlist.txt ]; then
  grep -v -E '^[[:space:]]*(#|$)' scripts/verify-allowlist.txt > "$ALLOW" || true
fi
ALLOW_VALID=1
if [ -s "$ALLOW" ]; then
  # An invalid extended regex makes grep -f exit 2 with no output, which would hide every error
  # below. Compile the entries once against empty input: 0 or 1 is fine, anything else is not.
  ALLOW_RC=0
  grep -E -f "$ALLOW" /dev/null >/dev/null || ALLOW_RC=$?
  if [ "$ALLOW_RC" -gt 1 ]; then
    ALLOW_VALID=0
    echo "scripts/verify-allowlist.txt contains an invalid extended regex (grep exit $ALLOW_RC)"
    FAILED+=("invalid regex in scripts/verify-allowlist.txt")
  elif printf '\n' | grep -q -E -f "$ALLOW"; then
    # An entry that matches the empty string (a*, x?, .*, or foo| in GNU grep) matches every line.
    ALLOW_VALID=0
    echo "scripts/verify-allowlist.txt has an entry that matches an empty line and would hide every error"
    FAILED+=("allowlist entry matches everything in scripts/verify-allowlist.txt")
  fi
fi
if [ -s "$ALLOW" ] && [ "$ALLOW_VALID" -eq 1 ]; then
  ERRORS="$(grep -E "$PATTERN" "$LOG" | grep -v -E -f "$ALLOW" || true)"
else
  ERRORS="$(grep -E "$PATTERN" "$LOG" || true)"
fi
rm -f "$ALLOW"
if [ -n "$ERRORS" ]; then
  FAILED+=("godot errors in log")
  echo "$ERRORS" | head -n 20
fi

echo "===== VERIFY SUMMARY ====="
echo "godot:  $(godot --version 2>/dev/null | head -n 1)"
DIRTY=""
if ! git diff --quiet 2>/dev/null; then DIRTY=" (+ uncommitted changes)"; fi
echo "commit: $(git rev-parse --short HEAD 2>/dev/null)${DIRTY}"
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "RESULT: GREEN"
  rm -f "$LOG"
  exit 0
fi
for f in "${FAILED[@]}"; do echo "FAILED: $f"; done
echo "full log: $LOG"
exit 1
