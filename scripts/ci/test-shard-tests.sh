#!/usr/bin/env bash
# Offline test of scripts/ci/shard-tests.py (CI follow-up #87), on a fixture tree and on the real one:
# the shards are disjoint and their union is the suite list, a new suite lands in a shard by itself,
# the native suites stay in one shard, the split is stable, hidden and .gdignore entries are skipped,
# and bad arguments exit 2.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

SHARD="python3 -I scripts/ci/shard-tests.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "test-shard-tests: FAIL $*" >&2; exit 1; }

mk() { mkdir -p "$tmp/$(dirname "$1")"; printf 'extends GdUnitTestSuite\n%s' "$2" >"$tmp/$1"; }
cases() { local n="$1" out="" i; for ((i = 0; i < n; i++)); do out+="func test_c${i}() -> void:"$'\n\tpass\n'; done; printf '%s' "$out"; }

mk tests/a/test_big.gd "$(cases 40)"
mk tests/a/test_small.gd "$(cases 1)"
for i in 1 2 3 4 5 6; do mk "tests/b/test_b${i}.gd" "$(cases 5)"; done
for i in 1 2 3; do mk "tests/sim/native/test_n${i}.gd" "$(cases 4)"; done
mk tests/sim/native/sanitizer/dump_states.gd "$(cases 1)"
mk tests/.hidden/test_hidden.gd "$(cases 3)"
mk tests/skipme/test_ignored.gd "$(cases 3)"
: >"$tmp/tests/skipme/.gdignore"
printf 'not a gd file\n' >"$tmp/tests/a/notes.txt"

list="$($SHARD --list --root "$tmp")"
[ "$(printf '%s\n' "$list" | wc -l)" -eq 12 ] || fail "expected 12 suite files, got: $list"
case "$list" in *hidden* | *ignored* | *notes*) fail "a hidden, .gdignore or non-gd file was listed" ;; esac

for n in 1 2 3 4 5; do
  $SHARD --check "$n" --root "$tmp" >/dev/null || fail "--check $n on the fixture"
  all=""
  for ((i = 1; i <= n; i++)); do all+="$($SHARD --shard "$i/$n" --root "$tmp")"$'\n'; done
  [ "$(printf '%s' "$all" | grep -c .)" -eq 12 ] || fail "N=$n: shards hold the wrong number of files"
  [ "$(printf '%s' "$all" | grep . | LC_ALL=C sort)" = "$list" ] || fail "N=$n: union differs from the list"
  homes="$(for ((i = 1; i <= n; i++)); do if $SHARD --shard "$i/$n" --root "$tmp" | grep -q 'tests/sim/native/'; then echo "$i"; fi; done | wc -l)"
  [ "$homes" -eq 1 ] || fail "N=$n: the native suites are in $homes shards"
done

# Stable: the same tree gives the same shards.
[ "$($SHARD --shard 2/3 --root "$tmp")" = "$($SHARD --shard 2/3 --root "$tmp")" ] || fail "split is not stable"

# A new suite lands in some shard with no list to edit.
mk tests/c/test_new_suite.gd "$(cases 2)"
found=0
for i in 1 2 3; do
  if $SHARD --shard "$i/3" --root "$tmp" | grep -q 'tests/c/test_new_suite.gd'; then found=$((found + 1)); fi
done
[ "$found" -eq 1 ] || fail "a new suite is in $found shards, expected 1"
$SHARD --check 3 --root "$tmp" >/dev/null || fail "--check 3 after adding a suite"

# A heavy hint moves the balance: the 900 s suite is alone against the rest.
printf 'tests/a/test_big.gd 900\n' >"$tmp/weights.txt"
heavy="$($SHARD --shard 1/2 --root "$tmp" --weights "$tmp/weights.txt")"
[ "$heavy" = "tests/a/test_big.gd" ] || fail "the heavy hint did not isolate test_big.gd: $heavy"

# Usage errors.
for bad in "--shard 0/3" "--shard 4/3" "--shard 2" "--shard x/3" "--check 0" "--bogus" ""; do
  rc=0
  # shellcheck disable=SC2086
  $SHARD $bad --root "$tmp" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || fail "'$bad' exited $rc, expected 2"
done

# The real tree: every N from 1 to 6 splits it cleanly.
for n in 1 2 3 4 5 6; do $SHARD --check "$n" >/dev/null || fail "--check $n on the repository"; done

echo "test-shard-tests: all checks passed"
