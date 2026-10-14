#!/usr/bin/env bash
# The AddressSanitizer half of the sanitizer job (ADR 0013 section 10, P57): dumps the states of the seed-42 arena
# with tests/sim/native/sanitizer/dump_states.gd in headless Godot, builds the harness native/sim_kernels/sanitizer/
# with g++ -fsanitize=address,undefined (core/ with no Godot header, no -fwrapv, every report fatal) and runs it
# over the dumps and its crafted cases. Then it checks that the harness refuses a dump of a World.STATE_FORMAT it
# does not know, by patching the number in a copy of the first dump.
# Usage: bash scripts/ci/run-sanitizer-harness.sh <work dir>
#   <work dir> receives states/ (the dumps), harness (the binary) and dump.log. Never the repository: use
#   $RUNNER_TEMP in CI, or reports/ (git-ignored) locally. The folder is created, and old dumps in it are removed.
#   The harness is built with the library's compile flags where they matter (C++17, the include path src/, -Wall -Wextra
#   -Werror) and the sanitizers' own; the dump step and the harness each get SANITIZER_TIMEOUT seconds, because a loop
#   in core/ that does not end gives no report and the Finding guards of the harness cannot see it.
# Env:   GODOT=<binary> (default: godot), SANITIZER_TIMEOUT=<seconds> (default 600; the dump step and the run take a
#        few seconds each)
# Exit:  0 ok
#        1 the harness reported a finding or a sanitizer aborted (its report is above), or it took a dump of a format
#          it does not know, or it ran out of time
#        2 bad argument
#        3 Godot, g++, timeout or g++'s libasan or libubsan is missing
#        4 the dump step failed (an exit code, out of time, a Godot error line, no "wrote N dumps" line or no file), or
#          the harness did not build
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

GODOT="${GODOT:-godot}"
die() {
  local code="$1"
  shift
  echo "run-sanitizer-harness: $*" >&2
  exit "$code"
}

[ $# -eq 1 ] && [ -n "$1" ] || die 2 "usage: bash scripts/ci/run-sanitizer-harness.sh <work dir>"
limit="${SANITIZER_TIMEOUT:-600}"
case "$limit" in "" | *[!0-9]* | 0) die 2 "SANITIZER_TIMEOUT must be a number of seconds above 0, got '$limit'" ;; esac
mkdir -p "$1"
work="$(cd "$1" && pwd -P)"
states="$work/states"
command -v "$GODOT" >/dev/null 2>&1 || die 3 "Godot is missing ('$GODOT'; set GODOT=/path/to/godot)"
command -v g++ >/dev/null 2>&1 || die 3 "g++ is missing"
command -v timeout >/dev/null 2>&1 || die 3 "timeout is missing (install coreutils)"
for runtime in libasan.so libubsan.so; do
  [ "$(g++ -print-file-name="$runtime" 2>/dev/null)" != "$runtime" ] || die 3 "g++ has no $runtime (install gcc's sanitizer runtimes)"
done

# (1) The dump step. Godot can exit 0 after a script error, so its log is read as well. The extension list is seeded
# before every headless editor start (ADR 0013 section 9), and a fresh checkout is imported first for the class names.
bash scripts/seed-extension-list.sh
[ -f .godot/global_script_class_cache.cfg ] || "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
rm -rf "$states"
mkdir -p "$states"
status=0
timeout -k 10 "$limit" "$GODOT" --headless --path . -s res://tests/sim/native/sanitizer/dump_states.gd -- "$states" >"$work/dump.log" 2>&1 || status=$?
cat "$work/dump.log"
# timeout ends with 124 when it stopped the command, and with 137 when it had to kill it.
[ "$status" -ne 124 ] && [ "$status" -ne 137 ] || die 4 "the dump step ran longer than ${limit} s and was stopped"
[ "$status" -eq 0 ] || die 4 "the dump step exited with $status"
grep -Eq '^dump_states: wrote [1-9][0-9]* dumps' "$work/dump.log" || die 4 "the dump step did not report 'wrote N dumps'"
! grep -Eq 'SCRIPT ERROR|^ERROR:' "$work/dump.log" || die 4 "Godot logged an error while dumping"
first="$(find "$states" -name 'state_*.bin' -size +0 | LC_ALL=C sort | sed -n '1p')"
[ -n "$first" ] || die 4 "the dump step wrote no state_*.bin file"

# (2) The harness: core/ and the harness sources only, so that a Godot header in core/ fails to compile. -I src/core
# serves the harness's own includes ("flow.h"), -I src the spelling that bind/ uses for a core/ header ("core/flow.h").
g++ -std=c++17 -O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined -fno-sanitize-recover=all -Wall -Wextra -Werror \
  -I native/sim_kernels/src -I native/sim_kernels/src/core native/sim_kernels/sanitizer/*.cpp native/sim_kernels/src/core/*.cpp -o "$work/harness" ||
  die 4 "the harness did not build"
export ASAN_OPTIONS="halt_on_error=1:detect_leaks=1:strict_string_checks=1:detect_stack_use_after_return=1"
export UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1"
status=0
timeout -k 10 "$limit" "$work/harness" "$states" || status=$?
[ "$status" -ne 124 ] && [ "$status" -ne 137 ] || die 1 "the harness ran longer than ${limit} s and was stopped (a loop in core/ that does not end?)"
[ "$status" -eq 0 ] || die 1 "the harness failed with exit code $status (a sanitizer report or a finding is above)"

# (3) It must refuse a format it does not know (the number is the u32 after the 4-byte magic).
mkdir -p "$work/unknown-format"
cp "$first" "$work/unknown-format/state_00000.bin"
printf '\377\377\377\377' | dd of="$work/unknown-format/state_00000.bin" bs=1 seek=4 count=4 conv=notrunc 2>/dev/null
refused=0
"$work/harness" "$work/unknown-format" >"$work/unknown-format/out.txt" 2>&1 || refused=$?
[ "$refused" -eq 2 ] && grep -Fq 'does not know' "$work/unknown-format/out.txt" ||
  die 1 "the harness took a dump of an unknown World.STATE_FORMAT (exit $refused, wanted 2)"
echo "run-sanitizer-harness: OK"
