#!/usr/bin/env bash
# Prints the godot-cpp section of THIRD_PARTY_LICENSES.txt (ADR 0013 section 11, ADR 0005 section 5): a
# titled block that names the tag and commit pinned in scripts/build-native.sh, a short note, and
# docs/licenses/godot-cpp-<tag>/LICENSE.md unchanged. export-android.sh and export-web.sh append this
# output to their notices, so the two stay identical, as they did for the libc++ licence (P26l).
# Usage: bash scripts/ci/godot-cpp-notice.sh      Exit: 0 ok, 1 a pin or the licence file is missing or empty.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

pin() { sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p" scripts/build-native.sh; }
tag="$(pin GODOT_CPP_TAG)"
sha="$(pin GODOT_CPP_SHA)"
if [ -z "$tag" ] || [ -z "$sha" ]; then
  echo "godot-cpp-notice: scripts/build-native.sh has no GODOT_CPP_TAG or GODOT_CPP_SHA line" >&2
  exit 1
fi
license="docs/licenses/godot-cpp-${tag#godot-}/LICENSE.md"
if [ ! -s "$license" ]; then
  echo "godot-cpp-notice: licence notice source $license is missing or empty" >&2
  exit 1
fi
rule="--------------------------------------------------------------------------------"
printf '\n%s\ngodot-cpp %s (commit %s): LICENSE.md\n%s\n' "$rule" "$tag" "$sha" "$rule"
cat <<EOF
rts-mobile's native sim kernels, which the Android builds pack, are built against godot-cpp
(https://github.com/godotengine/godot-cpp), the C++ bindings of the Godot Engine, licensed under
the MIT licence. Its LICENSE.md for the tag and commit above follows unchanged. The web build packs
no native library and names godot-cpp too, so that the notices of both builds stay identical.

EOF
cat "$license"
