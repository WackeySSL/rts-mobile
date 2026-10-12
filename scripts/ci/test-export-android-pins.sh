#!/usr/bin/env bash
# PROBE ONLY (spike P26n): offline test that scripts/export-android.sh takes the godot-cpp tag and
# commit it names in the shipped THIRD_PARTY_LICENSES.txt from scripts/build-native.sh, the script
# that owns the pins, and keeps no second copy that could name the wrong commit after a bump. The
# notice itself is written after a full Godot export, which cannot run offline, so this test checks
# the two things that decide it: the export script holds no copy of its own, and it reads the pins
# first, from the build script next to it, and stops with exit 4 when it cannot (a tree copy with a
# changed build-native.sh stands in for the bump). ci.yml runs it in android-debug-apk.
# Usage: bash scripts/ci/test-export-android-pins.sh      Exit: 0 all cases pass, 1 a case failed.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
export_script="$here/../export-android.sh"
build_script="$here/../build-native.sh"
root="$(mktemp -d)"
trap 'rm -rf "${root:?}"' EXIT
failures=0

pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

# tree NAME BUILD_SCRIPT: a copy of the two scripts under $root/NAME/scripts. export-android.sh
# changes into the folder above its own, so it reads the copy of build-native.sh, not the real one.
tree() {
  mkdir -p "$root/$1/scripts"
  cp "$export_script" "$root/$1/scripts/export-android.sh"
  cp "$2" "$root/$1/scripts/build-native.sh"
}

# expect NAME WANT_EXIT WANT_TEXT [ARGUMENT...]: runs the copy in $root/NAME with GODOT=/bin/true
# (which is not Godot 4.7.2, so a script that got past the pins ends with exit 3).
expect() {
  local name="$1" want="$2" text="$3" rc=0 out
  shift 3
  out="$(cd "$root/$name" && env GODOT=/bin/true bash scripts/export-android.sh "$@" 2>&1)" || rc=$?
  if [ "$rc" = "$want" ] && grep -Fq -- "$text" <<<"$out"; then
    pass "$name: exit $rc, '$text'"
  else
    fail "$name: wanted exit $want and '$text', got exit $rc: ${out%%$'\n'*}"
  fi
}

# (1) No second copy of the pins in the export script.
if grep -Eq '[0-9a-f]{40}' "$export_script"; then
  fail "export-android.sh holds a 40-digit commit of its own"
else
  pass "export-android.sh holds no commit of its own"
fi
if grep -Eq 'godot-[0-9]+\.[0-9]+(\.[0-9]+)?-stable' "$export_script"; then
  fail "export-android.sh holds a godot-cpp tag of its own"
else
  pass "export-android.sh holds no godot-cpp tag of its own"
fi

# (2) With the real build script the pins are read, and the run goes on to the next check.
tree real "$build_script"
expect real 3 "needs Godot 4.7.2.stable"

# (3) Without a readable pin the export script stops with exit 4 before it checks anything else,
# and names the pin.
sed '/^GODOT_CPP_SHA=/d' "$build_script" >"$root/no-sha.sh"
tree no-sha "$root/no-sha.sh"
expect no-sha 4 "GODOT_CPP_SHA"

sed '/^GODOT_CPP_TAG=/d' "$build_script" >"$root/no-tag.sh"
tree no-tag "$root/no-tag.sh"
expect no-tag 4 "GODOT_CPP_TAG"

# A short commit is not a pin either.
sed 's/^\(GODOT_CPP_SHA="[0-9a-f]\{39\}\)[0-9a-f]"$/\1"/' "$build_script" >"$root/short-sha.sh"
if cmp -s "$build_script" "$root/short-sha.sh"; then
  fail "short-sha: the sed did not shorten GODOT_CPP_SHA (did its line change shape?)"
else
  tree short-sha "$root/short-sha.sh"
  expect short-sha 4 "GODOT_CPP_SHA"
fi

# (4) A usage error is still exit 2: the pins are read after the arguments.
tree usage "$build_script"
expect usage 2 "unknown argument" --bogus

if [ "$failures" -ne 0 ]; then
  echo "test-export-android-pins: $failures case(s) failed" >&2
  exit 1
fi
echo "test-export-android-pins: all cases passed"
