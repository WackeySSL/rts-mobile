#!/usr/bin/env bash
# Headless dummy-vs-dummy smoke run with fixed seeds (plan row P95, ADR 0020 question 2): N matches
# (default 3) of 1,800 ticks on Kestrel Flats, the Derrick League (player 1, data/ai/dummy_fossil.tres)
# against the Lumen Accord (player 2, data/ai/dummy_renew.tres), seeds 1 to N. The loop is
# tests/smoke/smoke_run.gd (AiDriver.think_all, then MatchLoop.step, as MatchRunner does), entered
# through tests/smoke/run_sim_smoke.gd. Phase 4 swaps in the real AI and the longer matches and keeps
# the flags and the report schema. Balance runs (many matches) run only in GitHub Actions.
# Usage: bash scripts/run-sim-smoke.sh [--matches N] [--report PATH]
#   --matches N    number of matches, a positive integer (default 3)
#   --report PATH  also write a JSON report to PATH (parent directories are created). A relative PATH
#                  is relative to the repository root. The report has schema, status ("ok" or
#                  "failed"), scenario, ticks_per_match, matches_requested and one entry per match:
#                  seed, ticks, winner (the player, 0 for none), match_end_tick, state_hash (16 hex
#                  digits), dropped_commands, spawn_refused and per player the counts that
#                  tests/smoke/smoke_run.gd lists. All of it is counted from the World, never timed.
# Env:   GODOT=<binary> (default: godot)
#        RUN_SIM_SMOKE_SKIP_IMPORT=1 skips the import step when the caller just ran it.
# Output: on stdout one line "run-sim-smoke: match K of N: seed ..." per match, then the summary line
#        "run-sim-smoke: OK, N matches of 1800 ticks, no dropped commands" (or "run-sim-smoke: FAILED,
#        <what>"). Godot's own output goes to a log that is shown only when the run fails.
# Exit:  0 ok
#        1 a match failed (a dropped Command: a dummy never sends one), Godot exited with an error or
#          wrote SCRIPT ERROR, ERROR: or Parse Error, or the OK line is missing
#        2 bad or unknown flag, or a --matches value that is not a positive integer
#        3 Godot missing (the message names the binary and GODOT=, as export-web.sh does)
# The matches run on the GDScript sim, which is the reference, so no native library is needed.
# Bash 3.2 compatible.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$(pwd -P)"

GODOT="${GODOT:-godot}"
ENTRY="res://tests/smoke/run_sim_smoke.gd"
PATTERN='SCRIPT ERROR|^ERROR:|Parse Error'

usage() {
  echo "usage: bash scripts/run-sim-smoke.sh [--matches N] [--report PATH]" >&2
}

matches=3
report=""
while [ $# -gt 0 ]; do
  case "$1" in
    --matches)
      if [ $# -lt 2 ]; then
        echo "run-sim-smoke: --matches needs a value" >&2
        usage
        exit 2
      fi
      matches="$2"
      shift 2
      ;;
    --report)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        echo "run-sim-smoke: --report needs a path" >&2
        usage
        exit 2
      fi
      report="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "run-sim-smoke: unknown argument '$1'" >&2
      usage
      exit 2
      ;;
  esac
done

case "$matches" in
  '' | *[!0-9]* | 0*)
    echo "run-sim-smoke: --matches must be a positive integer, got '${matches}'" >&2
    exit 2
    ;;
esac

if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "run-sim-smoke: GODOT MISSING: '$GODOT' is not on PATH (set GODOT=/path/to/godot)" >&2
  exit 3
fi

args=(--matches "$matches")
if [ -n "$report" ]; then
  report_dir="$(dirname "$report")"
  mkdir -p "$report_dir"
  # Godot would import files under the project's build/ and reports/ folders as resources.
  report_dir_abs="$(cd "$report_dir" && pwd -P)"
  case "$report_dir_abs" in
    "$ROOT/build" | "$ROOT/build"/*)
      mkdir -p "$ROOT/build"
      : >"$ROOT/build/.gdignore"
      ;;
    "$ROOT/reports" | "$ROOT/reports"/*)
      mkdir -p "$ROOT/reports"
      : >"$ROOT/reports/.gdignore"
      ;;
  esac
  # A failed run must not leave the report of an older one behind.
  rm -f "$report_dir_abs/$(basename "$report")"
  args+=(--report "$report_dir_abs/$(basename "$report")")
fi

log="$(mktemp -t sim-smoke.XXXXXX)"
trap 'rm -f "$log"' EXIT

# The class cache that the entry script resolves class_name through is made by an import: a fresh
# clone has none, and Godot would then exit 0 after a Parse Error.
if [ "${RUN_SIM_SMOKE_SKIP_IMPORT:-0}" != "1" ]; then
  bash scripts/seed-extension-list.sh
  if ! "$GODOT" --headless --path . --import >"$log" 2>&1; then
    tail -n 20 "$log" >&2
    echo "run-sim-smoke: the import failed" >&2
    exit 1
  fi
fi

# Godot's output goes to the log and the lines of the run to stdout as they come. PIPESTATUS holds
# Godot's own exit code, because the last stage (grep) exits 1 when no line matched.
set +e
"$GODOT" --headless --path . -s "$ENTRY" -- "${args[@]}" 2>&1 | tee "$log" | grep --line-buffered '^run-sim-smoke: '
codes=("${PIPESTATUS[@]}")
set -e
godot_code="${codes[0]}"

fail() {
  tail -n 20 "$log" >&2
  echo "run-sim-smoke: $1" >&2
  exit 1
}

if [ "$godot_code" -ne 0 ]; then
  fail "Godot exited with code $godot_code"
fi
if grep -E "$PATTERN" "$log" >&2; then
  fail "Godot wrote errors (above)"
fi
if ! grep -q '^run-sim-smoke: OK, ' "$log"; then
  fail "the OK line is missing: the run did not finish"
fi
