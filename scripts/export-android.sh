#!/usr/bin/env bash
# Export the Android debug APK (no Gradle, arm64 only, ADR 0005) and check the result. Godot exits
# 0 after export configuration errors, so the log is scanned and the APK is inspected.
# Usage: bash scripts/export-android.sh [--release] [--out DIR]
#   --release  the perf APK of the gate instead (P51r, ADR 0012 section 4): preset "Android perf" (custom
#              feature dev_menu), --export-release, the release template and the release keystore variables,
#              the library entry android.release.arm64 and build/android/rts-mobile-perf-release.apk. Three
#              more checks: aapt2 dump badging shows no application-debuggable, the pack holds the dev_menu
#              feature and the engine library is the release template's. Nothing else changes.
#   --out DIR  output directory (default: build/android), relative to the repository root and
#              build/ or below.
# Env:   GODOT=<binary> (default: godot). Must be version 4.7.2.stable.
#        JAVA_HOME (JDK 17) and ANDROID_HOME (SDK with platform-tools and build-tools 36.x).
#        GODOT_ANDROID_KEYSTORE_DEBUG_{PATH,USER,PASSWORD}: the debug keystore, all three
#        (with --release: GODOT_ANDROID_KEYSTORE_RELEASE_{PATH,USER,PASSWORD}, a key generated for the run).
# Needs: version.txt and android_debug.apk (--release: android_release.apk) in the Godot
#        export_templates/4.7.2.stable folder (scripts/ci/install-godot.sh --android, or --android-release),
#        the Android library of the export mode (entry android.debug.arm64 of native/sim_kernels.gdextension,
#        android.release.arm64 with --release; scripts/build-native.sh --platform android --arch arm64
#        --target template_debug (template_release) builds it), docs/licenses/godot-<version>/
#        {LICENSE,COPYRIGHT}.txt, docs/licenses/llvm-libc++/LICENSE.TXT and the godot-cpp licence that
#        scripts/ci/godot-cpp-notice.sh prints (the licence notices written next to the APK;
#        export-web.sh writes the same notice text, ADR 0005 section 5), and readelf and nm (binutils,
#        or the NDK's llvm tools) for scripts/ci/check-android-elf.sh.
# Exit:  0 ok
#        1 export failed, an error in this run's log, a check of the APK failed (the packed library
#          is not the bytes CI built, libc++_shared.so is missing, the ELF or libc++ symbol checks
#          fail), or a licence notice source is missing or empty
#        2 usage error, or --out not under build/
#        3 Godot missing or not 4.7.2.stable
#        4 export template, Android library, JDK 17 or Android SDK piece missing (the message names each)
#        5 keystore variables of the export mode incomplete or the keystore file missing
# Success prints "export-android: OK <dir>/rts-mobile-debug.apk" (rts-mobile-perf-release.apk with --release).
# A cloud session has no Android SDK and ends with exit 4 until scripts/cloud/install-android.sh has run (it
# prints the environment and the command to use).
# CI (the android-debug-apk job) is the test bed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$(pwd -P)"

GODOT="${GODOT:-godot}"
GODOT_VERSION="4.7.2.stable"
# --export-debug packs the android.debug.arm64 entry of the generated .gdextension (ADR 0013 section 10);
# --release (P51r) exports the preset "Android perf" with --export-release and packs android.release.arm64.
EXPORT_MODE="debug"
PRESET="Android"
BUILD_LABEL="debug"
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
    --release)
      EXPORT_MODE="release"
      PRESET="Android perf"
      BUILD_LABEL="perf (release template)"
      APK_NAME="rts-mobile-perf-release.apk"
      shift
      ;;
    --out)
      [ $# -ge 2 ] && [ -n "$2" ] || die 2 "--out needs a directory"
      out="${2%/}"
      shift 2
      ;;
    *) die 2 "unknown argument '$1' (usage: bash scripts/export-android.sh [--release] [--out DIR])" ;;
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
for name in version.txt "android_${EXPORT_MODE}.apk"; do
  [ -s "$template_dir/$name" ] || missing="$missing; template $template_dir/$name"
done
native_entry="$(sed -n "s|^android\.${EXPORT_MODE}\.arm64 = \"res://\(.*\)\"\$|\1|p" native/sim_kernels.gdextension 2>/dev/null || true)"
[ -s "${native_entry:-/nonexistent}" ] ||
  missing="$missing; the Android ${EXPORT_MODE} library (${native_entry:-no android.${EXPORT_MODE}.arm64 entry in native/sim_kernels.gdextension}): bash scripts/build-native.sh --platform android --arch arm64 --target template_${EXPORT_MODE}"
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

# (3) The keystore of the export mode (all three variables, and the file). The values are never printed.
keystore_var="GODOT_ANDROID_KEYSTORE_$(tr '[:lower:]' '[:upper:]' <<<"$EXPORT_MODE")"
for name in "${keystore_var}_PATH" "${keystore_var}_USER" "${keystore_var}_PASSWORD"; do
  [ -n "${!name:-}" ] || die 5 "$name is not set (path, user and password must all be set)"
done
keystore_file="${keystore_var}_PATH"
[ -s "${!keystore_file}" ] || die 5 "the $EXPORT_MODE keystore file is missing or empty"

# (4) Fresh output folder. build/.gdignore keeps the next import away from the exported files.
apk="$out_abs/$APK_NAME"
mkdir -p "$out_abs"
: >"$ROOT/build/.gdignore"
rm -f "$apk" "$apk.idsig" "$out_abs/$NOTICE_NAME"

# (5) Import (a fresh checkout has no .godot/) and export, after seeding the extension list (ADR 0013
# section 9). The log of this run only is scanned.
bash scripts/seed-extension-list.sh
log="$(mktemp -t export-android.XXXXXX)"
set +e
{ "$GODOT" --headless --path . --import && "$GODOT" --headless --path . "--export-$EXPORT_MODE" "$PRESET" "$apk"; } 2>&1 | tee "$log"
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
rts-mobile Android ${BUILD_LABEL} build: third-party licences
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
  bash scripts/ci/godot-cpp-notice.sh # the same section export-web.sh appends (ADR 0013 section 11)
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

# (8) The kernels library (ADR 0013 section 10). The APK entry of the export mode holds the bytes CI built,
# the APK ships libc++_shared.so, and the packed copy passes the ELF and libc++ symbol checks. The template's
# own libraries are described with no verdict (ADR 0013 Context). Nothing here is faked: a missing piece fails.
abi_dir="lib/arm64-v8a"
native_packed="$abi_dir/$(basename "$native_entry")"
for name in "$native_packed" "$abi_dir/libc++_shared.so"; do
  grep -Fxq -- "$name" <<<"$listing" || die 1 "the APK lacks $name (its lib/ entries: $(grep '^lib/' <<<"$listing" | tr '\n' ' '))"
done
work="$(mktemp -d -t export-android-native.XXXXXX)"
trap 'rm -rf "$work"' EXIT
unzip -q "$apk" "$native_packed" "$abi_dir/libc++_shared.so" "$abi_dir/libgodot_android.so" -d "$work"
cmp -s "$work/$native_packed" "$native_entry" ||
  die 1 "the APK's $native_packed is not the library CI built ($native_entry): sha256 $(sha256sum <"$work/$native_packed" | cut -d' ' -f1), built $(sha256sum <"$native_entry" | cut -d' ' -f1)"
bash scripts/ci/check-android-elf.sh describe "$work/$abi_dir/libgodot_android.so" "$work/$abi_dir/libc++_shared.so" || true
bash scripts/ci/check-android-elf.sh check "$work/$native_packed" "$work/$abi_dir/libc++_shared.so" ||
  die 1 "the packed $(basename "$native_entry") fails the ELF checks above"
echo "export-android: $native_packed is the library CI built, sha256 $(sha256sum <"$native_entry" | cut -d' ' -f1)"

# (9) --release only (P51r): the APK is what the gate measures. aapt2 dump badging lists application-debuggable for a
# debuggable manifest (its package line proves that the output is the APK's and not empty), and the manifest dump
# of (7) shows debuggable=true for one, so a change in either output format cannot hide it. The pack must hold the
# dev_menu custom feature, which opens the dev menu where OS.is_debug_build() is false: a plain grep for dev_menu would
# match file paths, so as in export-web.sh the feature list is read behind the _custom_features key of project.binary,
# the project settings as the APK packs them. The engine library must be the release template's, byte for byte.
if [ "$EXPORT_MODE" = release ]; then
  badging="$("$(dirname "$signer")/aapt2" dump badging "$apk")" || die 1 "aapt2 dump badging failed on the APK"
  grep -q "name='$PACKAGE'" <<<"$badging" || die 1 "aapt2 dump badging does not show the package $PACKAGE"
  ! grep -q 'application-debuggable' <<<"$badging" || die 1 "the APK is debuggable (aapt2 dump badging shows application-debuggable)"
  ! grep -Eq 'debuggable\(0x0101000f\)=.*(true|0xffffffff)' <<<"$manifest" || die 1 "the manifest is debuggable (aapt2 dump xmltree)"
  grep -qx 'assets/project.binary' <<<"$listing" || die 1 "the APK lacks assets/project.binary"
  features="$(unzip -p "$apk" assets/project.binary | strings | grep -A1 -x _custom_features || true)"
  grep -qx dev_menu <<<"$features" || die 1 "the APK lacks the dev_menu custom feature (preset 'Android perf', custom_features)"
  unzip -p "$template_dir/android_release.apk" "$abi_dir/libgodot_android.so" | cmp -s - "$work/$abi_dir/libgodot_android.so" ||
    die 1 "the APK's libgodot_android.so is not the one of the release template ($template_dir/android_release.apk)"
  echo "export-android: release template confirmed: not debuggable, dev_menu packed, engine library is the template's"
fi

rm -f "$log"
echo "export-android: OK $out/$APK_NAME"
