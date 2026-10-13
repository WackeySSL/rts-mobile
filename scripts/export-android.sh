#!/usr/bin/env bash
# Export the Android debug APK (no Gradle, arm64 only, ADR 0005) and check the result. Godot exits
# 0 after export configuration errors, so the log is scanned and the APK is inspected.
# Usage: bash scripts/export-android.sh [--out DIR]
#   --out DIR  output directory (default: build/android), relative to the repository root and
#              build/ or below.
# Env:   GODOT=<binary> (default: godot). Must be version 4.7.2.stable.
#        JAVA_HOME (JDK 17) and ANDROID_HOME (SDK with platform-tools and build-tools 36.x).
#        GODOT_ANDROID_KEYSTORE_DEBUG_{PATH,USER,PASSWORD}: the debug keystore, all three.
# Needs: version.txt and android_debug.apk in the Godot export_templates/4.7.2.stable folder
#        (scripts/ci/install-godot.sh --android), docs/licenses/godot-<version>/{LICENSE,COPYRIGHT}.txt
#        and docs/licenses/llvm-libc++/LICENSE.TXT (the licence notices written next to the APK;
#        export-web.sh writes the same notice text, ADR 0005 section 5).
# Exit:  0 ok
#        1 export failed, an error in this run's log, a check of the APK failed, or a licence
#          notice source is missing or empty
#        2 usage error, or --out not under build/
#        3 Godot missing or not 4.7.2.stable
#        4 export template, JDK 17 or Android SDK piece missing (the message names each)
#        5 debug keystore variables incomplete or the keystore file missing
# Success prints "export-android: OK <dir>/rts-mobile-debug.apk". Cloud sessions have no Android
# SDK, so a local run ends with exit 4. CI (the android-debug-apk job) is the test bed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$(pwd -P)"

GODOT="${GODOT:-godot}"
GODOT_VERSION="4.7.2.stable"
PATTERN='SCRIPT ERROR|^ERROR:|Parse Error'
PACKAGE="dk.appcode.rts.dev"
APK_NAME="rts-mobile-debug.apk"
NOTICE_NAME="THIRD_PARTY_LICENSES.txt"
LICENSE_DIR="docs/licenses/godot-${GODOT_VERSION%.stable}"
# Every APK ships the template's libc++_shared.so (LLVM libc++, Apache-2.0 WITH LLVM-exception),
# which Godot's COPYRIGHT.txt does not name. Its upstream licence file sits in LIBCXX_DIR, from the
# LLVM tag below (docs/licenses/llvm-libc++/README.md says why that tag). export-web.sh holds the
# same tag and the same notice text.
LIBCXX_DIR="docs/licenses/llvm-libc++"
LIBCXX_TAG="llvmorg-21.1.0"

die() {
  local code="$1"
  shift
  echo "export-android: $*" >&2
  exit "$code"
}

out="build/android"
while [ $# -gt 0 ]; do
  case "$1" in
    --out)
      [ $# -ge 2 ] && [ -n "$2" ] || die 2 "--out needs a directory"
      out="${2%/}"
      shift 2
      ;;
    *) die 2 "unknown argument '$1' (usage: bash scripts/export-android.sh [--out DIR])" ;;
  esac
done
case "$out" in
  *..*) die 2 "--out '$out' contains '..'" ;;
  build | build/*) ;;
  *) die 2 "--out '$out' must be build/ or below, relative to the repository root" ;;
esac
out_abs="$ROOT/$out"

# (1) Godot present and exactly the pinned version.
command -v "$GODOT" >/dev/null 2>&1 || die 3 "GODOT MISSING: '$GODOT' is not on PATH (set GODOT=/path/to/godot)"
version="$("$GODOT" --version 2>/dev/null | head -n 1 | cut -d. -f1-4 || true)"
[ "$version" = "$GODOT_VERSION" ] || die 3 "needs Godot ${GODOT_VERSION}, '$GODOT' reports '${version:-nothing}'"

# (2) Template and toolchain. A runner image change must fail here, loudly, not sign with an
# unexpected tool (ADR 0005 section 3).
template_dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${GODOT_VERSION}"
missing=""
for name in version.txt android_debug.apk; do
  [ -s "$template_dir/$name" ] || missing="$missing; template $template_dir/$name"
done
java_version="$("${JAVA_HOME:-/nonexistent}/bin/java" -version 2>&1 || true)"
grep -q 'version "17\.' <<<"$java_version" || missing="$missing; JDK 17 (JAVA_HOME='${JAVA_HOME:-}')"
[ -x "${ANDROID_HOME:-/nonexistent}/platform-tools/adb" ] || missing="$missing; \$ANDROID_HOME/platform-tools/adb (ANDROID_HOME='${ANDROID_HOME:-}')"
for tool in apksigner aapt2; do
  found=""
  for dir in "${ANDROID_HOME:-/nonexistent}"/build-tools/36.*; do
    if [ -x "$dir/$tool" ]; then found="$dir"; fi
  done
  [ -n "$found" ] || missing="$missing; \$ANDROID_HOME/build-tools/36.*/$tool"
done
[ -z "$missing" ] || die 4 "missing${missing#;}"

# (3) Debug keystore (all three variables, and the file). The values are never printed.
for name in GODOT_ANDROID_KEYSTORE_DEBUG_PATH GODOT_ANDROID_KEYSTORE_DEBUG_USER GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD; do
  [ -n "${!name:-}" ] || die 5 "$name is not set (path, user and password must all be set)"
done
[ -s "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH" ] || die 5 "the debug keystore file is missing or empty"

# (4) Fresh output folder. build/.gdignore keeps the next import away from the exported files.
apk="$out_abs/$APK_NAME"
mkdir -p "$out_abs"
: >"$ROOT/build/.gdignore"
rm -f "$apk" "$apk.idsig" "$out_abs/$NOTICE_NAME"

# (5) Import (a fresh checkout has no .godot/) and export. The log of this run only is scanned.
log="$(mktemp -t export-android.XXXXXX)"
set +e
{ "$GODOT" --headless --path . --import && "$GODOT" --headless --path . --export-debug Android "$apk"; } 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e
[ "$status" -eq 0 ] || die 1 "Godot export failed with exit code ${status} (log: $log)"

errors="$(grep -E "$PATTERN" "$log" || true)"
allow="$(grep -v -E '^[[:space:]]*(#|$)' scripts/verify-allowlist.txt || true)"
if [ -n "$allow" ]; then
  # An invalid regex makes grep -f exit 2 with no output, and an entry that matches the empty
  # string matches every line. Either would hide every error.
  allow_rc=0
  grep -E -f <(echo "$allow") /dev/null >/dev/null || allow_rc=$?
  [ "$allow_rc" -le 1 ] && ! grep -q -E -f <(echo "$allow") <<<"" ||
    die 1 "scripts/verify-allowlist.txt has an invalid entry (bad regex, or it matches an empty line)"
  errors="$(grep -v -E -f <(echo "$allow") <<<"$errors" | grep . || true)"
fi
if [ -n "$errors" ]; then
  echo "$errors" | head -n 20 >&2
  die 1 "Godot logged errors during the export (log: $log)"
fi

# (6) Licence notice: the same content as the web build's, with this build named in the header.
[ -s "$LICENSE_DIR/LICENSE.txt" ] && [ -s "$LICENSE_DIR/COPYRIGHT.txt" ] ||
  die 1 "licence notice sources in $LICENSE_DIR are missing or empty"
[ -s "$LIBCXX_DIR/LICENSE.TXT" ] || die 1 "licence notice source $LIBCXX_DIR/LICENSE.TXT is missing or empty"
godot_tag="${GODOT_VERSION%.stable}-stable"
rule="--------------------------------------------------------------------------------"
{
  cat <<EOF
rts-mobile Android debug build: third-party licences
============================================

rts-mobile's own code is licensed under the MIT licence: see the file LICENSE in the
source repository.

This build runs on the Godot Engine ${godot_tag} (https://godotengine.org). Godot is
licensed under the MIT licence and bundles third-party components under their own
licences. Godot's LICENSE.txt and COPYRIGHT.txt for tag ${godot_tag} follow unchanged.

This build also contains LLVM libc++, the C++ standard library that the Godot export
template links (on Android it is the file libc++_shared.so). libc++ is licensed under
the Apache License v2.0 with LLVM Exceptions. Its libcxx/LICENSE.TXT for tag
${LIBCXX_TAG} follows unchanged.
EOF
  for source in LICENSE.txt COPYRIGHT.txt; do
    printf '\n%s\nGodot Engine %s: %s\n%s\n' "$rule" "$godot_tag" "$source" "$rule"
    cat "$LICENSE_DIR/$source"
  done
  printf '\n%s\nLLVM libc++ %s: LICENSE.TXT\n%s\n' "$rule" "$LIBCXX_TAG" "$rule"
  cat "$LIBCXX_DIR/LICENSE.TXT"
} >"$out_abs/$NOTICE_NAME"

# (7) The APK. Godot picks the build-tools version (the one that equals the target SDK, 36.0.0 on
# the ubuntu-24.04 image). Its log names the apksigner it ran, and the checks use the same tools.
[ -s "$apk" ] || die 1 "$out/$APK_NAME is missing or empty (log: $log)"
signer="$(grep -m1 -E '^/.*/apksigner sign ' "$log" | cut -d' ' -f1 || true)"
case "$signer" in
  "$ANDROID_HOME"/build-tools/36.*/apksigner) ;;
  *) die 1 "Godot did not sign with an apksigner of \$ANDROID_HOME/build-tools/36.* (log says '${signer:-nothing}')" ;;
esac
listing="$(unzip -Z1 "$apk")"
grep -qx 'lib/arm64-v8a/libgodot_android.so' <<<"$listing" || die 1 "the APK lacks lib/arm64-v8a/libgodot_android.so"
other_abis="$(grep '^lib/' <<<"$listing" | grep -v '^lib/arm64-v8a/' || true)"
[ -z "$other_abis" ] || die 1 "the APK holds libraries for other ABIs (arm64-v8a only): $(head -n 3 <<<"$other_abis")"
# Project files sit under assets/. Without the boot scene there the next check proves nothing.
grep -qx 'assets/scenes/main.tscn.remap' <<<"$listing" || die 1 "the APK lacks assets/scenes/main.tscn.remap"
test_files="$(grep -E '^assets/(tests|addons/gdUnit4)/' <<<"$listing" || true)"
[ -z "$test_files" ] || die 1 "the APK holds test files: $(head -n 3 <<<"$test_files")"
"$signer" verify --print-certs "$apk" || die 1 "apksigner verify failed"
manifest="$("$(dirname "$signer")/aapt2" dump xmltree --file AndroidManifest.xml "$apk")"
grep -q "package=\"$PACKAGE\"" <<<"$manifest" || die 1 "the manifest package is not $PACKAGE"
# Godot 4.7.2 maps the project's sensor landscape to userLandscape (11), not sensorLandscape (6).
grep -Eq 'screenOrientation\(0x0101001e\)=11$' <<<"$manifest" || die 1 "the manifest screenOrientation is not 11 (userLandscape)"
grep -q 'android.permission.VIBRATE' <<<"$manifest" || die 1 "the manifest lacks the VIBRATE permission"

rm -f "$log"
echo "export-android: OK $out/$APK_NAME"
