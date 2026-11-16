#!/usr/bin/env bash
# The checks of the Play bundle that export-android.sh --aab exports (P410c, ADR 0040 section 4), on file paths only:
# export-android.sh runs it after the export, test-aab.sh runs it on stubs. Every failing check is reported, then the
# exit is 1.
# Usage: bash scripts/ci/check-aab.sh BUNDLE.aab NATIVE_LIBRARY
#   NATIVE_LIBRARY is the library CI built (the android.release.arm64 entry of native/sim_kernels.gdextension): the
#   bundle must pack exactly its bytes. The manifest is read with bundletool 1.18.3 (the bundle's is proto format),
#   fetched by version and checked against a SHA-256, also when it is already in place. The permissions the plugins
#   merge are printed, not judged (to confirm in the first CI run). The App ID must be Google's test ID (ADR 0039
#   section 9), and no ca-app-pub ID of another publisher may be in the manifest or the asset entries (P420's rule).
# Env:   BUNDLETOOL_DIR (default ~/.cache/rts-mobile), BUNDLETOOL_BASE_URL (default the GitHub release; a file:// URL
#        for the offline test), JAVA_HOME (else java and jarsigner on PATH), READELF and NM as for check-android-elf.sh.
# Exit:  0 ok, 1 a check failed or bundletool could not be fetched or verified, 2 usage error, 3 tool missing.
# Success prints "check-aab: OK <bundle>".
set -euo pipefail

die() {
  local code="$1"
  shift
  echo "check-aab: $*" >&2
  exit "$code"
}

[ $# -eq 2 ] || die 2 "usage: bash scripts/ci/check-aab.sh BUNDLE.aab NATIVE_LIBRARY"
# Paths are resolved before the cd, so a relative path means what the caller meant.
aab="$(readlink -f -- "$1")"
native="$(readlink -f -- "$2")"
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

BT_VERSION="1.18.3"
BT_SHA256="a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29"
BT_URL="${BUNDLETOOL_BASE_URL:-https://github.com/google/bundletool/releases/download/${BT_VERSION}}/bundletool-all-${BT_VERSION}.jar"
BT_JAR="${BUNDLETOOL_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/rts-mobile}/bundletool-all-${BT_VERSION}.jar"
PACKAGE="dk.appcode.rts"
TEST_APP_ID="ca-app-pub-3940256099942544~3347511713"
TEST_PUBLISHER="3940256099942544"
ABI_DIR="base/lib/arm64-v8a"

bin_dir="${JAVA_HOME:+$JAVA_HOME/bin/}"
for tool in unzip sha256sum "${READELF:-readelf}" "${bin_dir}java" "${bin_dir}jarsigner"; do
  command -v "$tool" >/dev/null 2>&1 || die 3 "$(basename "$tool") is missing (JAVA_HOME='${JAVA_HOME:-}')"
done
[ -s "$aab" ] || die 1 "$aab is missing or empty"
[ -s "$native" ] || die 1 "the library CI built ($native) is missing or empty"

tmp=""
trap 'rm -rf "${tmp:-}"' EXIT
tmp="$(mktemp -d)"

jar_ok() { [ -s "$BT_JAR" ] && [ "$(sha256sum <"$BT_JAR" | cut -d' ' -f1)" = "$BT_SHA256" ]; }
if ! jar_ok; then
  command -v curl >/dev/null 2>&1 || die 3 "curl is missing (bundletool has to be downloaded)"
  mkdir -p "$(dirname "$BT_JAR")"
  curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/bt.jar" "$BT_URL" || die 1 "download of $BT_URL failed"
  actual="$(sha256sum <"$tmp/bt.jar" | cut -d' ' -f1)"
  [ "$actual" = "$BT_SHA256" ] || die 1 "SHA-256 mismatch for bundletool $BT_VERSION (pinned $BT_SHA256, got $actual)"
  mv "$tmp/bt.jar" "$BT_JAR"
fi

problems=""
problem() { problems="${problems}check-aab: FAIL $1"$'\n'; }

# jarsigner exits 0 for an unverifiable bundle too, with a warning, so the verdict line is required as well.
verify="$("${bin_dir}jarsigner" -verify "$aab" 2>&1)" || problem "jarsigner -verify failed: $(tail -n 1 <<<"$verify")"
grep -q 'jar verified' <<<"$verify" || problem "jarsigner -verify does not say 'jar verified': $(tail -n 1 <<<"$verify")"

listing="$(unzip -Z1 "$aab")" || die 1 "$aab is not a zip file"
# Godot 4.7.2's Gradle AAB puts the project files in the install-time asset pack, assetPackInstallTime/assets/
# (seen in PR #481's android-aab run); base/assets/ is accepted too. Any pack's assets/ folder counts for the
# "no tests" and "no ad ID" scans, and the run prints the first entries.
assets="$(grep -E '^[^/]+/assets/' <<<"$listing" || true)"
echo "check-aab: asset entries ($(grep -c . <<<"$assets" || true)), first ones:"
head -n 8 <<<"$assets"
[ -n "$assets" ] || problem "the bundle has no */assets/ entry (the checks of the project files would prove nothing)"
native_name="$(basename "$native")"
for name in "$ABI_DIR/libgodot_android.so" "$ABI_DIR/$native_name" "$ABI_DIR/libc++_shared.so"; do
  grep -Fxq -- "$name" <<<"$listing" || problem "the bundle lacks $name (its lib/ entries: $(grep '^base/lib/' <<<"$listing" | tr '\n' ' '))"
done
grep -Eq '^(base|assetPackInstallTime)/assets/scenes/main\.tscn\.remap$' <<<"$listing" || problem "the bundle lacks assets/scenes/main.tscn.remap in base/ or assetPackInstallTime/"
other_abis="$(grep '^base/lib/' <<<"$listing" | grep -v "^$ABI_DIR/" || true)"
[ -z "$other_abis" ] || problem "the bundle holds libraries for other ABIs (arm64-v8a only): $(head -n 3 <<<"$other_abis" | tr '\n' ' ')"
test_files="$(grep -E '^[^/]+/assets/(tests|addons/gdUnit4)/' <<<"$listing" || true)"
[ -z "$test_files" ] || problem "the bundle holds test files: $(head -n 3 <<<"$test_files" | tr '\n' ' ')"
# The OFL.txt of every font folder travels in the bundle (the preset's include_filter, P118b).
fonts_list="$(bash scripts/ci/font-notice.sh --list)" || die 1 "a font licence text is missing (scripts/ci/font-notice.sh says which)"
while IFS= read -r ofl; do
  grep -Fxq -e "base/assets/$ofl" -e "assetPackInstallTime/assets/$ofl" <<<"$listing" || problem "the bundle lacks the font licence assets/$ofl"
done <<<"$fonts_list"

mkdir -p "$tmp/lib"
unzip -q "$aab" "$ABI_DIR/*" -d "$tmp/lib" 2>/dev/null || true
if [ -s "$tmp/lib/$ABI_DIR/$native_name" ]; then
  # Gradle strips debug symbols from the packed copy (stripDebugSymbols), so the bytes differ from the build; the
  # code does not. Compare the .text section (GNU readelf reads an aarch64 ELF on any host).
  text_sha() { "${READELF:-readelf}" -W -x .text "$1" 2>/dev/null | sha256sum | cut -d' ' -f1; }
  packed_text="$(text_sha "$tmp/lib/$ABI_DIR/$native_name")"
  built_text="$(text_sha "$native")"
  [ "$packed_text" = "$built_text" ] ||
    problem "the bundle's $native_name is not the library CI built ($native): .text sha256 $packed_text, built $built_text"
  if [ -s "$tmp/lib/$ABI_DIR/libc++_shared.so" ]; then
    bash scripts/ci/check-android-elf.sh check "$tmp/lib/$ABI_DIR/$native_name" "$tmp/lib/$ABI_DIR/libc++_shared.so" ||
      problem "the packed $native_name fails the ELF checks above"
  fi
fi
libs=()
while IFS= read -r lib; do libs+=("$lib"); done < <(find "$tmp/lib/$ABI_DIR" -name '*.so' 2>/dev/null | LC_ALL=C sort)
if [ "${#libs[@]}" -gt 0 ]; then
  bash scripts/ci/check-android-elf.sh align "${libs[@]}" || problem "a library of the bundle is not 16 KB aligned (see above)"
fi

manifest="$("${bin_dir}java" -jar "$BT_JAR" dump manifest --bundle="$aab" 2>&1)" || {
  head -n 20 <<<"$manifest" >&2
  die 1 "bundletool dump manifest failed"
}
# One line, so that the attribute order and the line breaks of bundletool's output do not matter.
flat="$(tr '\n' ' ' <<<"$manifest" | tr -s ' ')"
grep -Eq "<manifest[^>]* package=\"${PACKAGE//./\\.}\"" <<<"$flat" || problem "the manifest package is not $PACKAGE"
! grep -Eq 'android:debuggable="true"' <<<"$flat" || problem "the manifest is debuggable"
for permission in VIBRATE INTERNET; do
  grep -Eq "<uses-permission[^>]* android:name=\"android\.permission\.${permission}\"" <<<"$flat" || problem "the manifest lacks the $permission permission"
done
grep -Eq 'android:screenOrientation="(fullUser|13)"' <<<"$flat" ||
  problem "the manifest screenOrientation is not fullUser (13): $(grep -Eo 'android:screenOrientation="[^"]*"' <<<"$flat" | head -n 1)"
app_id_tag="$(grep -Eo '<meta-data[^>]*com\.google\.android\.gms\.ads\.APPLICATION_ID[^>]*>' <<<"$flat" | head -n 1 || true)"
grep -Fq "android:value=\"$TEST_APP_ID\"" <<<"$app_id_tag" ||
  problem "the manifest meta-data com.google.android.gms.ads.APPLICATION_ID is not Google's test App ID (found: ${app_id_tag:-none})"
echo "check-aab: manifest permissions: $(grep -Eo '<uses-permission[^>]*android:name="[^"]*"' <<<"$flat" | sed 's/.*android:name="//; s/"$//' | tr '\n' ' ')"

# No ad ID of a real publisher: the manifest and every asset entry are searched (a pack entry may be compressed, so
# unzip -p reads it). Google's test publisher is the only one allowed (ADR 0040 section 4; real IDs are Phase 7's).
ids="$({
  printf '%s\n' "$flat"
  unzip -p "$aab" '*/assets/*' 2>/dev/null | grep -a -o 'ca-app-pub-[0-9]\{16\}' || true
} | grep -a -o 'ca-app-pub-[0-9]\{16\}' | sort -u || true)"
other_ids="$(grep -v -x "ca-app-pub-$TEST_PUBLISHER" <<<"$ids" || true)"
[ -z "$other_ids" ] || problem "the bundle holds an ad ID of a publisher other than Google's test one: $(head -n 3 <<<"$other_ids" | tr '\n' ' ')"

if [ -n "$problems" ]; then
  printf '%s' "$problems" >&2
  exit 1
fi
echo "check-aab: OK $aab ($(stat -c %s "$aab") bytes, sha256 $(sha256sum <"$aab" | cut -d' ' -f1), bundletool $BT_VERSION)"
