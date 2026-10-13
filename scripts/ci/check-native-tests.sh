#!/usr/bin/env bash
# Proves from gdUnit4's results.xml that the native suites ran and passed (ADR 0013 section 10). It holds
# no list: every tests/sim/native/**/test_*.gd outside sanitizer/ is required, exactly once in results.xml
# under its base name, with a case and no failure, error or skip. --require <suite> adds a suite elsewhere
# (test_golden_hashes). The floor: once native/sim_kernels/src/bind/kernel_list.h exists (P54), zero
# suites fails; before it, zero suites and no --require print "no native suites yet (before P54)" and
# pass, with no results.xml needed.
# Usage: bash scripts/ci/check-native-tests.sh [--require <suite>]... [--list] [results.xml]
#   results.xml defaults to reports/gdunit/report_1/results.xml; --list prints the discovered suite files.
# Env:   PYTHON=<binary> (default: python3). Run it after run-tests.sh, never inside verify.sh.
# Exit:  0 ok  1 a suite is missing, empty or not passed, or the floor failed  2 bad argument
#        3 python3 missing  4 results.xml missing, empty or not XML
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

NATIVE_TESTS="tests/sim/native"
KERNEL_LIST="native/sim_kernels/src/bind/kernel_list.h"
PYTHON="${PYTHON:-python3}"

die() { echo "check-native-tests: ${*:2}" >&2; exit "$1"; }

results="reports/gdunit/report_1/results.xml"
required=()
list_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --require)
      case "${2:-}" in "" | *[!A-Za-z0-9_]*) die 2 "--require needs a suite name such as test_golden_hashes, got '${2:-}'" ;; esac
      required+=("$2")
      shift 2
      ;;
    --list) list_only=1; shift ;;
    -*) die 2 "unknown argument '$1' (usage: bash scripts/ci/check-native-tests.sh [--require <suite>]... [--list] [results.xml])" ;;
    *) results="$1"; shift ;;
  esac
done

files=()
if [ -d "$NATIVE_TESTS" ]; then
  while IFS= read -r file; do files+=("$file"); done < <(
    find "$NATIVE_TESTS" -path "$NATIVE_TESTS/sanitizer" -prune -o -type f -name 'test_*.gd' -print | LC_ALL=C sort
  )
fi
if [ "$list_only" = 1 ]; then
  [ ${#files[@]} -eq 0 ] || printf '%s\n' "${files[@]}"
  exit 0
fi
if [ ${#files[@]} -eq 0 ]; then
  [ ! -e "$KERNEL_LIST" ] || die 1 "FAIL $KERNEL_LIST exists but $NATIVE_TESTS holds no test_*.gd suite (the floor)"
  if [ ${#required[@]} -eq 0 ]; then
    echo "check-native-tests: no native suites yet (before P54)"
    exit 0
  fi
fi

command -v "$PYTHON" >/dev/null 2>&1 || die 3 "$PYTHON is missing"
[ -s "$results" ] || die 4 "$results is missing or empty (did the tests run?)"
names=()
for file in ${files[@]+"${files[@]}"}; do names+=("$(basename "$file" .gd)"); done
dups="$(printf '%s\n' ${names[@]+"${names[@]}"} | LC_ALL=C sort | uniq -d)"
[ -z "$dups" ] || die 1 "FAIL two suite files share the base name $dups, which names the suite in results.xml"
"$PYTHON" -I - "$results" ${names[@]+"${names[@]}"} ${required[@]+"${required[@]}"} <<'PY'
import sys
import xml.etree.ElementTree as ET

try:
    root = ET.parse(sys.argv[1]).getroot()
except (ET.ParseError, OSError) as exc:
    print("check-native-tests: %s is not readable XML: %s" % (sys.argv[1], exc), file=sys.stderr)
    sys.exit(4)
problems = []
names = list(dict.fromkeys(sys.argv[2:]))
for name in names:
    found = [s for s in root.iter("testsuite") if s.get("name") == name]
    if len(found) != 1:
        problems.append("%s: found %d times in results.xml, want once" % (name, len(found)))
        continue
    cases = list(found[0].iter("testcase"))
    counts = {a: found[0].get(a, "0") for a in ("failures", "errors", "skipped")}
    print("check-native-tests: %s: %d cases, %s" % (name, len(cases), " ".join("%s=%s" % kv for kv in counts.items())))
    if not cases:
        problems.append("%s: no cases ran" % name)
    for case in cases:
        if {"failure", "error", "skipped"} & {child.tag for child in case}:
            problems.append("%s: case %s failed, errored or was skipped" % (name, case.get("name")))
    problems += ["%s: %s=%s" % (name, a, v) for a, v in counts.items() if v != "0"]
for line in problems:
    print("check-native-tests: FAIL " + line, file=sys.stderr)
if problems:
    sys.exit(1)
print("check-native-tests: OK %d suites" % len(names))
PY
