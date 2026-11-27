#!/usr/bin/env bash
# The report-only lines of a verify.sh log, for a job's step summary and its job log (ci.yml).
# Usage: bash scripts/ci/job-summary.sh --summary [--perf] <verify.log>   markdown for $GITHUB_STEP_SUMMARY
#        bash scripts/ci/job-summary.sh --groups  [--perf] <verify.log>   ::group:: blocks for the job log
# The VERIFY SUMMARY block is always shown. --perf adds the PERF sim, PERF bases, PERF air, PERF restore
# and WATCH ai lines (tests/perf, report only: nothing gates on them); a section whose lines the log does
# not hold says so, since in a sharded run only the shard that holds the suite prints them. Never fails.
set -u

mode=""
perf=0
log=""
while [ $# -gt 0 ]; do
  case "$1" in
    --summary | --groups) mode="$1" ;;
    --perf) perf=1 ;;
    *) log="$1" ;;
  esac
  shift
done
[ -n "$mode" ] && [ -n "$log" ] || { echo "usage: job-summary.sh --summary|--groups [--perf] <verify.log>" >&2; exit 0; }

# name ~ grep pattern ~ heading ~ text when there is no line
sections=(
  "PERF sim~^PERF sim (units=|impl=native)~~no PERF sim line in this log (the perf suite is in another shard)"
  "PERF bases~^PERF bases (units=|impl=native units=)~PERF bases (the base arena, report only)~no PERF bases line in this log"
  "PERF air~^PERF air (units=|impl=native units=)~PERF air (the air arena, report only)~no PERF air line in this log"
  "PERF restore~^PERF restore ~PERF restore (the resume restore, report only)~no PERF restore line in this log"
  "WATCH ai~^WATCH ai ~WATCH ai (the opponent AI, report-only lines)~no WATCH ai line in this log"
)

has_summary() { [ -f "$log" ] && grep -q -x '===== VERIFY SUMMARY =====' "$log"; }
print_summary() {
  if has_summary; then
    sed -n '/^===== VERIFY SUMMARY =====$/,$p' "$log"
  else
    echo "no VERIFY SUMMARY block (verify.sh did not finish)"
  fi
}
lines_of() { grep -a -E "$1" "$log" 2>/dev/null || true; }

if [ "$mode" = "--summary" ]; then
  echo '```'
  print_summary
  echo '```'
  if [ "$perf" -eq 1 ]; then
    for s in "${sections[@]}"; do
      IFS='~' read -r _name pattern heading none <<<"$s"
      echo
      [ -z "$heading" ] || { echo "### ${heading}"; echo; }
      echo '```'
      found="$(lines_of "$pattern")"
      if [ -n "$found" ]; then echo "$found"; else echo "$none"; fi
      echo '```'
    done
  fi
else
  echo "::group::VERIFY SUMMARY"
  print_summary
  echo "::endgroup::"
  if [ "$perf" -eq 1 ]; then
    for s in "${sections[@]}"; do
      IFS='~' read -r name pattern _heading none <<<"$s"
      echo "::group::${name}"
      found="$(lines_of "$pattern")"
      if [ -n "$found" ]; then echo "$found"; else echo "$none"; fi
      echo "::endgroup::"
    done
  fi
fi
exit 0
