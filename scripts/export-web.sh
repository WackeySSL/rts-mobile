#!/usr/bin/env bash
# Export the Web build (no threads, so GitHub Pages can host it without COOP/COEP headers) and
# check the result. Godot exits 0 after export configuration errors, so the log is scanned and
# the artifacts are verified.
# Usage: bash scripts/export-web.sh [--debug] [--out DIR]
#   --debug    export with the debug template (default: release)
#   --out DIR  output directory (default: build/web). A relative DIR is relative to the
#              repository root. Inside the project it must be build/ or below.
# Env:   GODOT=<binary> (default: godot). Must be version 4.7.2.stable.
# Needs: the web export templates (version.txt, web_nothreads_debug.zip, web_nothreads_release.zip)
#        in the Godot export_templates/4.7.2.stable folder of the platform.
#        docs/licenses/godot-<version>/{LICENSE,COPYRIGHT}.txt, the engine's licence notices,
#        and docs/licenses/llvm-libc++/LICENSE.TXT, the LLVM libc++ notice, which the script
#        writes to <dir>/THIRD_PARTY_LICENSES.txt next to the build. export-android.sh writes
#        the same notice text, so the two stay identical (ADR 0005 section 5).
# Exit:  0 ok
#        1 export failed, an error in this run's log, an artifact missing or empty, wasm of
#          50 MiB or more, threads on, the dev_menu custom feature missing from the pack, or
#          a licence notice source (Godot's or libc++'s) or <dir>/THIRD_PARTY_LICENSES.txt
#          missing or empty
#        2 usage error, or --out inside the project but not under build/
#        3 Godot missing or not 4.7.2.stable (also: the strings tool is missing)
#        4 export templates missing (the message names the folder and files)
# Success prints "export-web: OK <dir>". Bash 3.2 compatible.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$(pwd -P)"

GODOT="${GODOT:-godot}"
GODOT_VERSION="4.7.2.stable"
PATTERN='SCRIPT ERROR|^ERROR:|Parse Error'
WASM_LIMIT=52428800 # 50 MiB, GitHub warns about pushed files from here on
TEMPLATE_FILES="version.txt web_nothreads_debug.zip web_nothreads_release.zip"
# The build ships the Godot engine, whose MIT licence and the licences of its bundled components
# require their notices to travel with the binary. The upstream files of the pinned tag are
# committed here and written next to the build.
LICENSE_DIR="docs/licenses/godot-${GODOT_VERSION%.stable}"
# The export template's C++ standard library is LLVM libc++ (Apache-2.0 WITH LLVM-exception), which
# Godot's COPYRIGHT.txt does not name. Its upstream licence file sits in LIBCXX_DIR, from the LLVM
# tag below (docs/licenses/llvm-libc++/README.md says why that tag). export-android.sh holds the
# same tag and the same notice text.
LIBCXX_DIR="docs/licenses/llvm-libc++"
LIBCXX_TAG="llvmorg-19.1.0"
NOTICE_NAME="THIRD_PARTY_LICENSES.txt"

die() {
  local code="$1"
  shift
  echo "export-web: $*" >&2
  exit "$code"
}

usage() {
  echo "usage: bash scripts/export-web.sh [--debug] [--out DIR]" >&2
}

mode="release"
out="build/web"
while [ $# -gt 0 ]; do
  case "$1" in
    --debug)
      mode="debug"
      shift
      ;;
    --out)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        usage
        die 2 "--out needs a directory"
      fi
      out="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      die 2 "unknown argument '$1'"
      ;;
  esac
done

# Absolute path of $1 whose existing part is symlink-resolved. The part that does not exist yet
# is appended as written, and a ".." in it is refused because it cannot be resolved here.
resolve_path() {
  local path="$1" tail=""
  case "$path" in
    /*) ;;
    *) path="$PWD/$path" ;;
  esac
  while [ ! -d "$path" ]; do
    tail="/$(basename "$path")$tail"
    path="$(dirname "$path")"
  done
  case "$tail" in
    */.. | */../*) return 1 ;;
  esac
  printf '%s%s\n' "$(cd "$path" && pwd -P)" "$tail"
}

out_abs="$(resolve_path "$out")" || die 2 "--out '$out' contains '..' below a directory that does not exist"
out_abs="${out_abs%/}"
case "$out_abs" in
  "$ROOT/build" | "$ROOT/build"/*) ;;
  "$ROOT" | "$ROOT"/*) die 2 "--out '$out' is inside the project but not under build/" ;;
esac

# (1) Godot present and exactly the pinned version.
if ! command -v "$GODOT" >/dev/null 2>&1; then
  die 3 "GODOT MISSING: '$GODOT' is not on PATH (set GODOT=/path/to/godot)"
fi
version="$("$GODOT" --version 2>/dev/null | head -n 1 | cut -d. -f1-4 || true)"
if [ "$version" != "$GODOT_VERSION" ]; then
  die 3 "needs Godot ${GODOT_VERSION}, '$GODOT' reports '${version:-nothing}'"
fi

# The dev_menu check below reads the pack with strings (binutils, preinstalled on macOS and on
# the Ubuntu runners). Stop early instead of reporting a missing feature that is not missing.
if ! command -v strings >/dev/null 2>&1; then
  die 3 "'strings' is missing (install binutils)"
fi

# (2) Export templates.
if [ "$(uname -s)" = "Darwin" ]; then
  template_dir="$HOME/Library/Application Support/Godot/export_templates/${GODOT_VERSION}"
else
  template_dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${GODOT_VERSION}"
fi
missing=""
for name in $TEMPLATE_FILES; do
  if [ ! -s "$template_dir/$name" ]; then missing="$missing $name"; fi
done
if [ -n "$missing" ]; then
  die 4 "export templates missing in '$template_dir': expected${missing}"
fi

# (3) Fresh output folder. build/.gdignore keeps the next import away from the exported
# files. Stale artifacts are removed so that an old build cannot pass the checks below.
mkdir -p "$out_abs" "$ROOT/build"
: >"$ROOT/build/.gdignore"
rm -f "$out_abs"/index.* "$out_abs"/build.txt "$out_abs/$NOTICE_NAME"

# (4) Export. The log of this run only is scanned afterwards.
log="$(mktemp -t export-web.XXXXXX)"
set +e
"$GODOT" --headless --path . "--export-${mode}" Web "$out_abs/index.html" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e
if [ "$status" -ne 0 ]; then
  die 1 "Godot export failed with exit code ${status} (log: $log)"
fi

allow="$(mktemp -t export-web-allow.XXXXXX)"
if [ -f scripts/verify-allowlist.txt ]; then
  grep -v -E '^[[:space:]]*(#|$)' scripts/verify-allowlist.txt >"$allow" || true
fi
if [ -s "$allow" ]; then
  # An invalid extended regex makes grep -f exit 2 with no output, which would hide every error
  # below. Compile the entries once against empty input: 0 or 1 is fine, anything else is not.
  allow_rc=0
  grep -E -f "$allow" /dev/null >/dev/null || allow_rc=$?
  if [ "$allow_rc" -gt 1 ]; then
    rm -f "$allow"
    die 1 "scripts/verify-allowlist.txt contains an invalid extended regex (grep exit $allow_rc)"
  fi
  # An entry that matches the empty string (a*, x?, .*, or foo| in GNU grep) matches every line.
  if printf '\n' | grep -q -E -f "$allow"; then
    rm -f "$allow"
    die 1 "scripts/verify-allowlist.txt has an entry that matches an empty line and would hide every error"
  fi
  errors="$(grep -E "$PATTERN" "$log" | grep -v -E -f "$allow" || true)"
else
  errors="$(grep -E "$PATTERN" "$log" || true)"
fi
rm -f "$allow"
if [ -n "$errors" ]; then
  echo "$errors" | head -n 20 >&2
  die 1 "Godot logged errors during the export (log: $log)"
fi

# (4b) Licence notice: a short header, then Godot's LICENSE.txt and COPYRIGHT.txt and LLVM's
# libc++ LICENSE.TXT, each unchanged. COPYRIGHT.txt lists the bundled components (FreeType,
# HarfBuzz, Open Sans, ...) and the CC BY 4.0 notice for the Godot logo that the default boot
# splash shows.
for source in LICENSE.txt COPYRIGHT.txt; do
  if [ ! -s "$LICENSE_DIR/$source" ]; then
    die 1 "licence notice source $LICENSE_DIR/$source is missing or empty"
  fi
done
if [ ! -s "$LIBCXX_DIR/LICENSE.TXT" ]; then
  die 1 "licence notice source $LIBCXX_DIR/LICENSE.TXT is missing or empty"
fi
godot_tag="${GODOT_VERSION%.stable}-stable"
{
  printf '%s\n' "rts-mobile web build: third-party licences"
  printf '%s\n' "============================================"
  printf '\n'
  printf '%s\n' "rts-mobile's own code is licensed under the MIT licence: see the file LICENSE in the"
  printf '%s\n' "source repository."
  printf '\n'
  printf '%s\n' "This build runs on the Godot Engine ${godot_tag} (https://godotengine.org). Godot is"
  printf '%s\n' "licensed under the MIT licence and bundles third-party components under their own"
  printf '%s\n' "licences. Godot's LICENSE.txt and COPYRIGHT.txt for tag ${godot_tag} follow unchanged."
  printf '\n'
  printf '%s\n' "This build also contains LLVM libc++, the C++ standard library that the Godot export"
  printf '%s\n' "template links (on Android it is the file libc++_shared.so). libc++ is licensed under"
  printf '%s\n' "the Apache License v2.0 with LLVM Exceptions. Its libcxx/LICENSE.TXT for tag"
  printf '%s\n' "${LIBCXX_TAG} follows unchanged."
  printf '\n'
  printf '%s\n' "--------------------------------------------------------------------------------"
  printf '%s\n' "Godot Engine ${godot_tag}: LICENSE.txt"
  printf '%s\n' "--------------------------------------------------------------------------------"
  cat "$LICENSE_DIR/LICENSE.txt"
  printf '\n'
  printf '%s\n' "--------------------------------------------------------------------------------"
  printf '%s\n' "Godot Engine ${godot_tag}: COPYRIGHT.txt"
  printf '%s\n' "--------------------------------------------------------------------------------"
  cat "$LICENSE_DIR/COPYRIGHT.txt"
  printf '\n'
  printf '%s\n' "--------------------------------------------------------------------------------"
  printf '%s\n' "LLVM libc++ ${LIBCXX_TAG}: LICENSE.TXT"
  printf '%s\n' "--------------------------------------------------------------------------------"
  cat "$LIBCXX_DIR/LICENSE.TXT"
} >"$out_abs/$NOTICE_NAME"

# (5) Artifacts.
for name in index.html index.js index.wasm index.pck "$NOTICE_NAME"; do
  if [ ! -s "$out_abs/$name" ]; then
    die 1 "$out/$name is missing or empty (log: $log)"
  fi
done
wasm_bytes="$(wc -c <"$out_abs/index.wasm" | tr -d ' ')"
if [ "$wasm_bytes" -ge "$WASM_LIMIT" ]; then
  die 1 "$out/index.wasm is ${wasm_bytes} bytes, the limit is below ${WASM_LIMIT}"
fi
if ! grep -q 'const GODOT_THREADS_ENABLED = false;' "$out_abs/index.html"; then
  die 1 "the web build has thread support on, which needs COOP/COEP headers that Pages cannot send"
fi
# A plain grep for dev_menu would match file paths. The feature list sits behind the
# _custom_features key in the pack's project settings. A here-string avoids a SIGPIPE under
# pipefail when grep -q stops reading early.
features="$(strings "$out_abs/index.pck" | grep -A1 -x _custom_features || true)"
if ! grep -qx dev_menu <<<"$features"; then
  die 1 "the pack lacks the dev_menu custom feature (preset custom_features, ADR 0002 section 6)"
fi

rm -f "$log"
echo "export-web: OK $out"
