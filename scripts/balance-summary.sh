#!/usr/bin/env bash
# Merges the report JSONs of one balance set and writes the summary (plan row P187, ADR 0031
# section 4): the merged JSON with a `summary` block, and PATH.md next to it. The work is
# tests/smoke/balance_summary.gd, run by headless Godot; the same GDScript the suites test.
# Usage: bash scripts/balance-summary.sh --out PATH [--gate] REPORT...
#   --out PATH  the merged JSON (parent directories are created); the markdown goes to PATH.md.
#               A relative PATH is relative to the repository root.
#   --gate      also write the gate block (ADR 0031 section 6; the gate run's seeds 1001-1100)
#   REPORT...   one or more schema 2 reports of run-sim-smoke.sh (`--report`), at least one. They
#               must agree on commit, impl, ticks_per_match, scenarios and the level pair (as an
#               unordered pair, so easy,normal and normal,easy merge); a refusal names the field.
# Env:   GODOT=<binary> (default: godot). BALANCE_SUMMARY_SKIP_IMPORT=1 skips the import step.
# Output: on stdout "balance-summary: OK, N matches from K reports, F flags[, gate V]" or
#        "balance-summary: FAILED, <what>". Godot's own output goes to a log shown on a crash.
# Exit:  0 ok
#        1 a report cannot be read or merged (a refusal), Godot exited with an error or wrote
#          SCRIPT ERROR, ERROR: or Parse Error, or the OK line is missing
#        2 bad or unknown flag, a missing --out or REPORT, or a REPORT file that does not exist
#        3 Godot missing
# Bash 3.2 compatible.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$(pwd -P)"

GODOT="${GODOT:-godot}"
ENTRY="res://tests/smoke/balance_summary.gd"
PATTERN='SCRIPT ERROR|^ERROR:|Parse Error'

usage() {
  echo "usage: bash scripts/balance-summary.sh --out PATH [--gate] REPORT..." >&2
}

out=""
gate=0
reports=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        echo "balance-summary: --out needs a path" >&2
        usage
        exit 2
      fi
      out="$2"
      shift 2
      ;;
    --gate)
      gate=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "balance-summary: unknown argument '$1'" >&2
      usage
      exit 2
      ;;
    *)
      if [ -z "$1" ] || [ ! -f "$1" ]; then
        echo "balance-summary: report '$1' is not a file" >&2
        usage
        exit 2
      fi
      reports+=("$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")")
      shift
      ;;
  esac
done
if [ -z "$out" ] || [ "${#reports[@]}" -eq 0 ]; then
  echo "balance-summary: --out PATH and at least one REPORT are required" >&2
  usage
  exit 2
fi

if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "balance-summary: GODOT MISSING: '$GODOT' is not on PATH (set GODOT=/path/to/godot)" >&2
  exit 3
fi

out_dir="$(dirname "$out")"
mkdir -p "$out_dir"
out_dir_abs="$(cd "$out_dir" && pwd -P)"
# Godot would import files under the project's build/ and reports/ folders as resources.
case "$out_dir_abs" in
  "$ROOT/build" | "$ROOT/build"/*)
    mkdir -p "$ROOT/build"
    : >"$ROOT/build/.gdignore"
    ;;
  "$ROOT/reports" | "$ROOT/reports"/*)
    mkdir -p "$ROOT/reports"
    : >"$ROOT/reports/.gdignore"
    ;;
esac
out_abs="$out_dir_abs/$(basename "$out")"
# A failed run must not leave the files of an older one behind.
rm -f "$out_abs" "$out_abs.md"

args=(--out "$out_abs")
[ "$gate" -eq 0 ] || args+=(--gate)
args+=("${reports[@]}")

log="$(mktemp -t balance-summary.XXXXXX)"
trap 'rm -f "$log"' EXIT

if [ "${BALANCE_SUMMARY_SKIP_IMPORT:-0}" != "1" ]; then
  bash scripts/seed-extension-list.sh
  if ! "$GODOT" --headless --path . --import >"$log" 2>&1; then
    tail -n 20 "$log" >&2
    echo "balance-summary: the import failed" >&2
    exit 1
  fi
fi

set +e
"$GODOT" --headless --path . -s "$ENTRY" -- "${args[@]}" 2>&1 | tee "$log" | grep --line-buffered '^balance-summary: '
codes=("${PIPESTATUS[@]}")
set -e
godot_code="${codes[0]}"

fail() {
  tail -n 20 "$log" >&2
  echo "balance-summary: $1" >&2
  exit 1
}

# A refusal or an unreadable report is the script's own FAILED line, already shown.
if grep -q '^balance-summary: FAILED, ' "$log"; then
  exit 1
fi
if [ "$godot_code" -ne 0 ]; then
  fail "Godot exited with code $godot_code"
fi
if grep -E "$PATTERN" "$log" >&2; then
  fail "Godot wrote errors (above)"
fi
if ! grep -q '^balance-summary: OK, ' "$log"; then
  fail "the OK line is missing: the run did not finish"
fi
