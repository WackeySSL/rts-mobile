#!/usr/bin/env bash
# PROBE ONLY (spike P26n, never merged): proves from gdUnit4's results.xml that the tests of the C++
# port really ran and passed in this job: the bit-identity suite (tests/perf/test_probe_tick_native.gd)
# and the probe-mode suite (tests/ui/test_perf_probe_native.gd). The tests fail, never skip, when the
# library is missing; this check closes the other way out: a suite that was not found, a case that
# was removed or renamed, or a case that gdUnit4 reports as failed, errored or skipped.
# Usage: bash scripts/ci/check-native-tests.sh [results.xml]   (default: reports/gdunit/report_1/results.xml)
# Run it after scripts/verify.sh (or scripts/run-tests.sh) in the same job. Needs python3.
# Exit:  0 every required suite and case ran and passed
#        1 a required suite or case is missing, or one did not pass
#        2 results.xml is missing or is not XML
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
results="${1:-reports/gdunit/report_1/results.xml}"
[ -s "$results" ] || {
  echo "check-native-tests: $results is missing or empty (did the tests run?)" >&2
  exit 2
}
command -v python3 >/dev/null 2>&1 || {
  echo "check-native-tests: python3 is missing" >&2
  exit 2
}

python3 -I - "$results" <<'PY'
import sys
import xml.etree.ElementTree as ET

REQUIRED = {
    "test_probe_tick_native": [
        "test_900_ticks_and_their_flow_slices_match_bit_for_bit",
        "test_flow_fields_run_to_completion_many_times_with_odd_budgets",
        "test_properties_read_back_what_was_written",
    ],
    "test_perf_probe_native": [
        "test_the_next_mode_button_reaches_the_cpp_mode_from_the_worker_mode_and_leaves_it_joined",
        "test_the_cpp_tick_runs_on_a_worker_thread_with_no_late_ticks_and_the_card_says_so",
        "test_the_view_follows_the_cpp_tick_and_it_plays_the_same_ticks",
        "test_without_the_library_mode_five_says_so_and_measures_nothing",
        "test_every_mode_names_its_tick_implementation",
    ],
}
BAD_CHILDREN = {"failure", "error", "skipped"}

try:
    root = ET.parse(sys.argv[1]).getroot()
except (ET.ParseError, OSError) as exc:
    print("check-native-tests: %s is not readable XML: %s" % (sys.argv[1], exc), file=sys.stderr)
    sys.exit(2)

problems = []
for suite_name, wanted in REQUIRED.items():
    suites = [s for s in root.iter("testsuite") if s.get("name") == suite_name]
    if len(suites) != 1:
        problems.append("suite %s: found %d times, want once" % (suite_name, len(suites)))
        continue
    suite = suites[0]
    cases = {c.get("name"): c for c in suite.iter("testcase")}
    for name in wanted:
        case = cases.get(name)
        if case is None:
            problems.append("%s: case %s did not run" % (suite_name, name))
            continue
        bad = sorted({child.tag for child in case} & BAD_CHILDREN)
        if bad:
            problems.append("%s: case %s reported %s" % (suite_name, name, "/".join(bad)))
    for attr in ("failures", "errors", "skipped"):
        if suite.get(attr, "0") != "0":
            problems.append("%s: %s=%s" % (suite_name, attr, suite.get(attr)))
    print(
        "check-native-tests: %s: %d cases ran (%d required), failures=%s errors=%s skipped=%s, %ss"
        % (
            suite_name,
            len(cases),
            len(wanted),
            suite.get("failures", "0"),
            suite.get("errors", "0"),
            suite.get("skipped", "0"),
            suite.get("time", "?"),
        )
    )
if problems:
    for line in problems:
        print("check-native-tests: FAIL " + line, file=sys.stderr)
    sys.exit(1)
print("check-native-tests: OK")
PY
