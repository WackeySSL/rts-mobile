#!/usr/bin/env bash
# The pre-render bake tool's entry (ADR 0053 section 5, plan row P656a): checks the pinned bake
# image BEFORE any render, then renders one model to raw frames with Godot 4.7.2 on Forward+ over
# Vulkan (Mesa lavapipe) under xvfb-run, through tools/prerender/bake_model.gd. It installs
# nothing. Godot's Forward+ renderer is used only here; the game stays on Compatibility.
# Usage: bash scripts/prerender.sh --preflight
#        bash scripts/prerender.sh --model RES --sheet RES [--out DIR] [--dirs all|6,7] [--scale 8]
#                                  [--team #HEX] [--composite] [--no-ssao]
#   --preflight   check the image and stop (exit 0 when it is the pinned one)
#   otherwise     check the image, then bake; --out defaults to ${TMPDIR:-/tmp}/prerender. The
#                 flags after the first one are bake_model.gd's (see its header). The frames are
#                 raw: the post and the manifest are plan row P656b.
# The pins (ADR 0053 section 5): Ubuntu 24.04.5 LTS; mesa-vulkan-drivers, libgl1-mesa-dri,
#   libglx-mesa0, libgbm1 and mesa-libgallium 25.2.8-0ubuntu0.24.04.5; libllvm20
#   1:20.1.2-0ubuntu1~24.04.3; xvfb 2:21.1.12-1ubuntu1.9; Python 3.13 with numpy 2.5.3 and Pillow
#   12.3.0 (the pins of tools/prerender/requirements.txt are P656b's; they live here until then);
#   Godot 4.7.2.
# Env:   GODOT=<binary> (default: godot).
#        PRERENDER_VERSIONS_FILE=FILE  read what is installed from FILE (one "name version" per
#                 line: os, godot, python, numpy, pillow and the package names) instead of from
#                 the machine; for the tests of this script's exit codes.
#        PRERENDER_TOOLS="a b"  the commands that must exist (default: the Godot binary,
#                 xvfb-run, dpkg-query, python3).
#        PRERENDER_SKIP_IMPORT=1  skip the import step when the caller just ran it.
# Exit:  0 ok
#        1 the bake failed: Godot exited with an error or wrote SCRIPT ERROR, ERROR: or Parse
#          Error, or no frame was written
#        2 bad usage (no flags, or a flag the bake entry lacks values for)
#        3 a tool is missing; the message names it and what to install
#        4 the image differs from the pin; one line per package: expected, found
# Bash 3.2 compatible.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

GODOT="${GODOT:-godot}"
ENTRY="res://tools/prerender/bake_model.gd"
PATTERN='SCRIPT ERROR|^ERROR:|Parse Error'
PINS='os|Ubuntu 24.04.5 LTS
godot|4.7.2
python|3.13
numpy|2.5.3
pillow|12.3.0
mesa-vulkan-drivers|25.2.8-0ubuntu0.24.04.5
libgl1-mesa-dri|25.2.8-0ubuntu0.24.04.5
libglx-mesa0|25.2.8-0ubuntu0.24.04.5
libgbm1|25.2.8-0ubuntu0.24.04.5
mesa-libgallium|25.2.8-0ubuntu0.24.04.5
libllvm20|1:20.1.2-0ubuntu1~24.04.3
xvfb|2:21.1.12-1ubuntu1.9'

if [ "$#" -eq 0 ]; then
  sed -n '2,/^# Bash 3.2/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi

# Tools first: a missing one is its own exit code, before any version is read.
for tool in ${PRERENDER_TOOLS:-"$GODOT" xvfb-run dpkg-query python3}; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "prerender: TOOL MISSING: '$tool' is not on PATH (GODOT=/path/to/godot for Godot; xvfb, dpkg and python3 come with the pinned image, see docs/adr/0053)." >&2
    exit 3
  fi
done

# What is installed for one pin name: from the fixture file or from the machine.
found_version() {
  local name="$1" got=""
  if [ -n "${PRERENDER_VERSIONS_FILE:-}" ]; then
    got="$(awk -v k="$name" '$1 == k { sub(/^[^ ]+ +/, ""); print; exit }' "$PRERENDER_VERSIONS_FILE")"
    echo "${got:-(not found)}"
    return
  fi
  case "$name" in
    os) got="$(sed -n 's/^PRETTY_NAME="\(.*\)"$/\1/p' /etc/os-release)" ;;
    godot) got="$("$GODOT" --version 2>/dev/null | head -n 1)" ;;
    python) got="$(python3 -I -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null)" ;;
    numpy) got="$(python3 -I -c 'import numpy; print(numpy.__version__)' 2>/dev/null)" ;;
    pillow) got="$(python3 -I -c 'import PIL; print(PIL.__version__)' 2>/dev/null)" ;;
    *) got="$(dpkg-query -W -f='${Version}' "$name" 2>/dev/null)" ;;
  esac
  echo "${got:-(not installed)}"
}

mismatches=0
while IFS='|' read -r name want; do
  have="$(found_version "$name")"
  ok=0
  if [ "$name" = godot ]; then
    case "$have" in "$want".*) ok=1 ;; esac
  elif [ "$have" = "$want" ]; then
    ok=1
  fi
  if [ "$ok" -eq 0 ]; then
    echo "prerender: MISMATCH $name: expected $want, found $have" >&2
    mismatches=$((mismatches + 1))
  fi
done <<<"$PINS"
if [ "$mismatches" -gt 0 ]; then
  echo "prerender: the image is not the pinned one ($mismatches differ). Nothing was rendered and nothing was installed (ADR 0053 section 5)." >&2
  exit 4
fi
echo "prerender: preflight OK (the pinned image)"
if [ "$1" = "--preflight" ]; then
  exit 0
fi

args=("$@")
has_out=0
for arg in "${args[@]}"; do
  if [ "$arg" = "--out" ]; then has_out=1; fi
done
if [ "$has_out" -eq 0 ]; then args+=(--out "${TMPDIR:-/tmp}/prerender"); fi

if [ "${PRERENDER_SKIP_IMPORT:-0}" != 1 ]; then
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi
log="$(mktemp -t prerender.XXXXXX)"
status=0
xvfb-run -a "$GODOT" --path . --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy \
  --script "$ENTRY" -- "${args[@]}" >"$log" 2>&1 || status=$?
cat "$log"
if [ "$status" -ne 0 ] || grep -Eq "$PATTERN" "$log" || ! grep -q '^bake_model: .*frames in' "$log"; then
  echo "prerender: FAILED (Godot exit $status)" >&2
  rm -f "$log"
  exit 1
fi
rm -f "$log"
