#!/usr/bin/env bash
# Installs the Android part of the Poing Studios godot-admob plugin (P410, ADR 0040 section 2) into
# addons/admob/android/bin/, by pin: the release asset android-template-v4.7.2.zip of tag v5.1.0
# (commit 615974e9f66921a54e3c71c33db0856bdbf19d13 of https://github.com/poingstudios/godot-admob-plugin),
# checked against a SHA-256 before anything is extracted. The editor part sits in addons/admob/ (vendored,
# addons/THIRD_PARTY.md); the Android part is a Godot "v2" plugin: one EditorExportPlugin script plus AARs per
# library. Only package.gd and ads/ are extracted (the mediation adapters are not used). Nothing is committed
# (/addons/admob/android/ is git-ignored). The AARs pull the Google Mobile Ads SDK 1.4.0 from Google's Maven
# in the Gradle build, so the build runs in CI, never in a cloud session.
# The editor plugin downloads missing platform binaries by itself, without a pin, when a headless editor starts
# with the plugin enabled (internal/services/network/binary_installer.gd): its Android and its iOS part. The Android
# part is in place after this script. The iOS part is not used before Phase 7, so this script writes the marker
# addons/admob/ios/bin/package.gd (version only, no binaries) that tells the plugin it is installed.
# Usage: bash scripts/ci/install-android-plugins.sh [--check]
#   --check  installs nothing: exit 0 when the pinned libraries are in place, exit 1 when not.
# Env:   ANDROID_PLUGINS_BASE_URL (default: the release download URL of the tag; a file:// URL for the offline test).
# Exit:  0 ok; 1 download or SHA-256 mismatch, or (--check) not installed; 2 usage error; 3 tool missing.
# Success prints "install-android-plugins: OK <version>".
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

PLUGIN_VERSION="5.1.0"
PLUGIN_TAG="v${PLUGIN_VERSION}"
PLUGIN_COMMIT="615974e9f66921a54e3c71c33db0856bdbf19d13"
GODOT_VERSION="4.7.2"
ZIP="android-template-v${GODOT_VERSION}.zip"
ZIP_SHA256="f7fdf644d50c0e231d8f02ae044057e489d0bcafcf50e908a4858477e7ee05ee"
BASE_URL="${ANDROID_PLUGINS_BASE_URL:-https://github.com/poingstudios/godot-admob-plugin/releases/download/${PLUGIN_TAG}}"
DEST="addons/admob/android/bin"
IOS_MARKER="addons/admob/ios/bin/package.gd"

die() {
  local code="$1"
  shift
  echo "install-android-plugins: $*" >&2
  exit "$code"
}

check_only=0
case "${1:-}" in
  "") ;;
  --check) check_only=1 ;;
  *) die 2 "unknown argument '$1' (usage: bash scripts/ci/install-android-plugins.sh [--check])" ;;
esac
[ $# -le 1 ] || die 2 "too many arguments"

installed() {
  [ "$(sed -n 's/^const VERSION := "\(.*\)"$/\1/p' "$DEST/package.gd" 2>/dev/null || true)" = "$PLUGIN_VERSION" ] || return 1
  for f in ads/poing_godot_admob_ads.gd ads/libs/poing-godot-admob-ads-debug.aar ads/libs/poing-godot-admob-ads-release.aar \
    ads/libs/poing-godot-admob-core-debug.aar ads/libs/poing-godot-admob-core-release.aar; do
    [ -s "$DEST/$f" ] || return 1
  done
  [ -s "$IOS_MARKER" ]
}

if installed; then
  echo "install-android-plugins: OK $PLUGIN_VERSION (already installed)"
  exit 0
fi
[ "$check_only" = 0 ] || die 1 "the Android part of the AdMob plugin $PLUGIN_VERSION is not installed in $DEST"

for tool in curl unzip sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || die 3 "$tool is missing"
done
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/$ZIP" "$BASE_URL/$ZIP" || die 1 "download of $BASE_URL/$ZIP failed"
actual="$(sha256sum <"$tmp/$ZIP" | cut -d' ' -f1)"
[ "$actual" = "$ZIP_SHA256" ] || die 1 "SHA-256 mismatch for $ZIP (pinned $ZIP_SHA256, got $actual; plugin $PLUGIN_TAG, commit $PLUGIN_COMMIT)"

rm -rf "$DEST"
mkdir -p "$DEST"
unzip -q "$tmp/$ZIP" 'package.gd' 'ads/*' -d "$DEST" || true # a missing member is caught by installed below
mkdir -p "$(dirname "$IOS_MARKER")"
printf '%s\n' '# Written by scripts/ci/install-android-plugins.sh: no iOS binaries. It only stops the editor plugin' \
  '# from downloading them without a pin when a headless editor starts. iOS is Phase 7.' \
  "const VERSION := \"$PLUGIN_VERSION\"" >"$IOS_MARKER"
installed || die 1 "the archive did not hold the expected files (ads/ libraries or package.gd)"
echo "install-android-plugins: OK $PLUGIN_VERSION"
