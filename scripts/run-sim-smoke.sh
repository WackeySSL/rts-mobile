#!/usr/bin/env bash
# Headless AI-vs-AI smoke run with fixed seeds (plan rows P95 and P186, ADR 0020 question 2 and
# ADR 0031 sections 1 to 3): N full matches (default 3) on Kestrel Flats, each player a computer
# opponent (AiFactory: the faction's OpponentDef at a difficulty, or its dummy), seeds S to S+N-1.
# A match ends at its end or after --ticks ticks (default 13,500 = 15 minutes of game); a match
# still running then is a "timeout", which is not a failure. The loop is tests/smoke/smoke_run.gd
# (AiDriver.lagged_tick, then MatchLoop.step, as MatchRunner does: the AI's Commands land one tick
# after its view, ADR 0038), entered through
# tests/smoke/run_sim_smoke.gd. The implementation is AUTO: native when the library loads, else the
# GDScript reference; the run prints it and the report stores it. Balance runs (many matches) run
# only in GitHub Actions.
# Usage: bash scripts/run-sim-smoke.sh [--matches N] [--report PATH] [--seed-start S]
#          [--levels A,B] [--scenarios KIND] [--ticks T]
#   --matches N     number of matches, a positive integer (default 3)
#   --report PATH   also write a JSON report (schema 2, ADR 0031 section 3) to PATH (parent
#                   directories are created). A relative PATH is relative to the repository root.
#   --seed-start S  the first seed, a positive integer (default 1); matches play S .. S+N-1
#   --levels A,B    the controller of player 1 and 2, each easy, normal, hard or dummy (default
#                   normal,normal)
#   --scenarios K   cross (default: odd seeds on skirmish_kestrel_flats, even seeds on its mirrored
#                   twin, so each faction holds each seat in half the matches), derrick, lumen,
#                   fossil-mirror or renew-mirror
#   --ticks T       the cap per match, a positive integer (default 13500)
#   Numbers have at most 9 digits and no leading zero.
# Env:   GODOT=<binary> (default: godot); GITHUB_SHA is stored in the report as `commit` (else
#        "local"). RUN_SIM_SMOKE_SKIP_IMPORT=1 skips the import step when the caller just ran it.
# Output: on stdout one line "run-sim-smoke: impl ..." then "run-sim-smoke: match K of N: seed ..."
#        per match, then the summary line "run-sim-smoke: OK, N matches of at most T ticks, impl I,
#        K timeouts, stale drops within the bound" (or "run-sim-smoke: FAILED, <what>"). Godot's own output
#        goes to a log that is shown only when the run fails.
# Exit:  0 ok
#        1 a match failed (more stale drops than 1 percent of its Commands; expired drops, whose
#          unit or target died in the lag tick, do not count, ADR 0038 section 6), Godot exited
#          with an error
#          or wrote SCRIPT ERROR, ERROR: or Parse Error, or the OK line is missing
#        2 bad or unknown flag, or a value that is not valid
#        3 Godot missing (the message names the binary and GODOT=, as export-web.sh does)
# Bash 3.2 compatible.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$(pwd -P)"

GODOT="${GODOT:-godot}"
ENTRY="res://tests/smoke/run_sim_smoke.gd"
PATTERN='SCRIPT ERROR|^ERROR:|Parse Error'

usage() {
  echo "usage: bash scripts/run-sim-smoke.sh [--matches N] [--report PATH] [--seed-start S]" \
    "[--levels A,B] [--scenarios KIND] [--ticks T]" >&2
}

matches=3
report=""
seed_start=""
levels=""
scenarios=""
ticks=""
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
    --seed-start | --levels | --scenarios | --ticks)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        echo "run-sim-smoke: $1 needs a value" >&2
        usage
        exit 2
      fi
      case "$1" in
        --seed-start) seed_start="$2" ;;
        --levels) levels="$2" ;;
        --scenarios) scenarios="$2" ;;
        --ticks) ticks="$2" ;;
      esac
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

# A positive integer of at most 9 digits (no sign, no leading zero), so the sim's int never wraps.
check_count() {
  case "$2" in
    '' | *[!0-9]* | 0* | ??????????*)
      echo "run-sim-smoke: $1 must be a positive integer of at most 9 digits, got '$2'" >&2
      exit 2
      ;;
  esac
}
check_count --matches "$matches"
[ -z "$seed_start" ] || check_count --seed-start "$seed_start"
[ -z "$ticks" ] || check_count --ticks "$ticks"
if [ -n "$levels" ]; then
  case "$levels" in
    easy,easy | easy,normal | easy,hard | easy,dummy | normal,easy | normal,normal | normal,hard | \
      normal,dummy | hard,easy | hard,normal | hard,hard | hard,dummy | dummy,easy | dummy,normal | \
      dummy,hard | dummy,dummy) ;;
    *)
      echo "run-sim-smoke: --levels must be two of easy, normal, hard, dummy, like normal,hard," \
        "got '${levels}'" >&2
      exit 2
      ;;
  esac
fi
case "$scenarios" in
  '' | cross | derrick | lumen | fossil-mirror | renew-mirror) ;;
  *)
    echo "run-sim-smoke: --scenarios must be cross, derrick, lumen, fossil-mirror or" \
      "renew-mirror, got '${scenarios}'" >&2
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

[ -z "$seed_start" ] || args+=(--seed-start "$seed_start")
[ -z "$levels" ] || args+=(--levels "$levels")
[ -z "$scenarios" ] || args+=(--scenarios "$scenarios")
[ -z "$ticks" ] || args+=(--ticks "$ticks")

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
