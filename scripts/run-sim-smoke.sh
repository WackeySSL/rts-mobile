#!/usr/bin/env bash
# Headless AI-vs-AI smoke run with fixed seeds. Phase 0 has no simulation yet, so this is a stub
# with the final interface: Phase 4 replaces the body and keeps the flags and the report schema.
# Usage: bash scripts/run-sim-smoke.sh [--matches N] [--report PATH]
#   --matches N    number of matches, a positive integer (default 3)
#   --report PATH  also write a JSON report to PATH (parent directories are created).
#                  A relative PATH is relative to the repository root.
# Output: the single line "no sim yet" on stdout.
# Exit:   0 ok; 2 bad or unknown flag, or a --matches value that is not a positive integer.
# Needs no Godot while there is no simulation.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$(pwd -P)"

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
  printf '{"schema":1,"status":"no_sim","matches_requested":%s,"matches":[]}\n' "$matches" >"$report"
fi

echo "no sim yet"
