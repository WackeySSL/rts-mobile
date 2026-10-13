#!/usr/bin/env bash
# Installs the Android toolchain in a cloud session, on demand (P55b), so that build-native.sh --platform android and
# export-android.sh work there (else exit 3 or 4). About 1.2 GB, so it is NOT part of scripts/cloud/setup.sh, the
# session-start hook or CI (a CI runner has the SDK). Idempotent: a piece in place is checked and left alone, so a
# second run downloads nothing and takes seconds. Installs:
#   JDK 17         apt-get install openjdk-17-jdk-headless, used through JAVA_HOME only (the default java stays)
#   cmdline-tools  23.0 from dl.google.com as <sdk>/cmdline-tools/latest, URL and SHA-256 pinned below
#   SDK packages   platform-tools (no versioned id) and build-tools 36.1.0 by sdkmanager, which checks its own checksums
#   NDK            scripts/ci/install-ndk.sh (the one NDK pin stays in build-native.sh)
#   Godot          the Android export template by scripts/ci/install-godot.sh --android (its pins)
#   keystore       a throwaway debug keystore (the public convention: alias androiddebugkey, password android)
# SDK licences: accepting them is a legal act for whoever runs this (AppCode ApS; the terms are at
# https://developer.android.com/studio/terms), so only a person passes --accept-android-sdk-licenses, and no automatic
# path (setup.sh, a hook, CI) ever does. The sdkmanager of cmdline-tools 23.0 is a shim for the Android CLI: it never
# asks, its --licenses does nothing, and it records <sdk>/licenses/android-sdk-license itself when it installs a
# package. So this gate is the only one, and it comes first: without the flag the script stops with exit 5 before any
# download or sdkmanager call, unless that file exists from an earlier acceptance.
# Editor settings: Godot copies JAVA_HOME and ANDROID_HOME into its settings only when it creates them, and a session
# that ran Godot before (verify.sh) has settings that name JDK 21 and no SDK. So the closing lines give a fresh
# XDG_CONFIG_HOME inside the SDK folder for the one export command, as on a CI runner: no settings file is edited, and
# it is no export line because XDG_CONFIG_HOME moves the config of git and gh too.
# Usage: bash scripts/cloud/install-android.sh [--accept-android-sdk-licenses]
# Env (all optional): ANDROID_HOME (else ANDROID_SDK_ROOT, else ~/Android/Sdk): the SDK folder, made if missing,
#        JDK17_HOME (default /usr/lib/jvm/java-17-openjdk-amd64), DEBUG_KEYSTORE (default ~/.android/debug.keystore,
#        never overwritten), GODOT_HOME and GODOT_BIN_DIR (install-godot.sh's; the editor copy it makes is no
#        godot on PATH by default, so the session's godot is not relinked), XDG_DATA_HOME (the template folder).
# Needs: root for apt-get (only when JDK 17 is missing), curl, unzip, sha256sum, and network access to
#        dl.google.com, archive.ubuntu.com and github.com with its release assets.
# Exit:  0 ok
#        2 an unknown argument, or the SDK folder is not an absolute path
#        3 tool missing (curl, unzip, sha256sum, or apt-get when JDK 17 is missing)
#        4 an install step failed (apt-get, download, SHA-256, unzip, sdkmanager), or what it left is not the pin
#        5 the SDK licences are not accepted and --accept-android-sdk-licenses was not given
#        6 the debug keystore: keytool failed, or the existing file is not an Android debug keystore
#        install-ndk.sh and install-godot.sh end the script with their own exit codes and messages.
# Success prints the environment lines and the commands to run. Bash 3.2 compatible.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

CMDLINE_TOOLS_REVISION="23.0"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip"
# SHA-256 of that file (181 052 239 bytes), computed on 2026-10-13; its SHA-1 equals the one in Google's repository2-3.xml.
CMDLINE_TOOLS_SHA256="0877a1d048fe4a24efe2eff536ca4223f7adeb58648bb81909d33c446918cfa8"
BUILD_TOOLS_VERSION="36.1.0"

die() {
  local code="$1"
  shift
  echo "install-android: $*" >&2
  exit "$code"
}
say() { echo "install-android: $*"; }
revision() { sed -n 's/^Pkg\.Revision[[:space:]]*=[[:space:]]*\([0-9][0-9.]*\).*$/\1/p' "$1" 2>/dev/null | head -n 1 || true; }

accept=0
for arg in "$@"; do
  case "$arg" in
    --accept-android-sdk-licenses) accept=1 ;;
    *) die 2 "unknown argument '$arg' (usage: bash scripts/cloud/install-android.sh [--accept-android-sdk-licenses])" ;;
  esac
done
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
sdk="${sdk%/}"
case "$sdk" in /*) ;; *) die 2 "the SDK folder '$sdk' must be an absolute path (ANDROID_HOME)" ;; esac
for tool in curl unzip sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || die 3 "$tool is missing (install it first)"
done
if [ "$accept" != 1 ] && [ ! -s "$sdk/licenses/android-sdk-license" ]; then
  die 5 "the Android SDK licences are not accepted in $sdk/licenses. Accepting them is a legal act on behalf of whoever runs this (terms: https://developer.android.com/studio/terms), and sdkmanager 23.0 records the acceptance itself when it installs, without asking. Rerun with --accept-android-sdk-licenses to accept them. Nothing was downloaded or installed."
fi

# (1) JDK 17, for keytool and the export (sdkmanager 23.0 needs no java). The system's default java is never changed.
jdk="${JDK17_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
has_jdk17() {
  [ -x "$jdk/bin/java" ] && [ -x "$jdk/bin/javac" ] && [ -x "$jdk/bin/keytool" ] && [[ "$("$jdk/bin/java" -version 2>&1)" == *'version "17.'* ]]
}
if has_jdk17; then
  say "JDK 17 is installed already ($jdk)"
else
  command -v apt-get >/dev/null 2>&1 || die 3 "JDK 17 is missing in $jdk and apt-get is not available (set JDK17_HOME)"
  say "installing openjdk-17-jdk-headless with apt-get"
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y openjdk-17-jdk-headless </dev/null || { apt-get update </dev/null && apt-get install -y openjdk-17-jdk-headless </dev/null; } ||
    die 4 "apt-get install openjdk-17-jdk-headless failed (it needs root and archive.ubuntu.com)"
  has_jdk17 || die 4 "apt-get left no JDK 17 in $jdk (set JDK17_HOME if it is elsewhere)"
fi
export JAVA_HOME="$jdk" ANDROID_HOME="$sdk" ANDROID_SDK_ROOT="$sdk"

# (2) cmdline-tools: the pinned zip, checked before it is unpacked, replaces <sdk>/cmdline-tools/latest.
mkdir -p "$sdk"
work="$(mktemp -d "$sdk/.install-android.XXXXXX")"
trap 'rm -rf "$work"' EXIT
sdkmanager="$sdk/cmdline-tools/latest/bin/sdkmanager"
if [ -x "$sdkmanager" ] && [ "$(revision "$sdk/cmdline-tools/latest/source.properties")" = "$CMDLINE_TOOLS_REVISION" ]; then
  say "cmdline-tools $CMDLINE_TOOLS_REVISION are installed already"
else
  say "downloading $CMDLINE_TOOLS_URL"
  curl -fsSL --retry 3 --retry-delay 2 -o "$work/cmdline-tools.zip" "$CMDLINE_TOOLS_URL" || die 4 "download of $CMDLINE_TOOLS_URL failed"
  actual="$(sha256sum "$work/cmdline-tools.zip" | cut -d' ' -f1)"
  [ "$actual" = "$CMDLINE_TOOLS_SHA256" ] ||
    die 4 "SHA-256 mismatch for the cmdline-tools zip: pinned $CMDLINE_TOOLS_SHA256, actual $actual"
  unzip -q "$work/cmdline-tools.zip" -d "$work/unzipped" || die 4 "unzip of the cmdline-tools zip failed"
  mkdir -p "$sdk/cmdline-tools"
  rm -rf "$sdk/cmdline-tools/latest"
  mv "$work/unzipped/cmdline-tools" "$sdk/cmdline-tools/latest"
fi

# (3) platform-tools and build-tools through sdkmanager, which records the SDK licence (the gate above let it).
build_tools="$sdk/build-tools/$BUILD_TOOLS_VERSION"
packages=()
[ -x "$sdk/platform-tools/adb" ] || packages+=("platform-tools")
{ [ "$(revision "$build_tools/source.properties")" = "$BUILD_TOOLS_VERSION" ] && [ -x "$build_tools/apksigner" ] && [ -x "$build_tools/aapt2" ]; } ||
  packages+=("build-tools;$BUILD_TOOLS_VERSION")
if [ "${#packages[@]}" -eq 0 ]; then
  say "platform-tools and build-tools $BUILD_TOOLS_VERSION are installed already"
else
  say "installing ${packages[*]} with sdkmanager, which records the Android SDK licence in $sdk/licenses"
  status=0
  "$sdkmanager" "--sdk_root=$sdk" "${packages[@]}" </dev/null || status=$?
  [ "$status" -eq 0 ] || die 4 "sdkmanager failed with exit code ${status}"
  [ -x "$sdk/platform-tools/adb" ] && [ -x "$build_tools/apksigner" ] && [ -x "$build_tools/aapt2" ] ||
    die 4 "sdkmanager did not leave platform-tools and build-tools $BUILD_TOOLS_VERSION in $sdk"
fi

# (4) NDK and Godot's Android template, each by its own script and pins. install-ndk.sh reports the NDK folder
# through GITHUB_ENV, so the version is read in that one place only. install-godot.sh would link `godot` into
# GODOT_BIN_DIR (default ~/.local/bin): a folder of its own keeps the session's godot as it is.
ndk_env="$work/ndk.env"
: >"$ndk_env"
GITHUB_ENV="$ndk_env" bash "$ROOT/scripts/ci/install-ndk.sh"
ndk="$(sed -n 's/^ANDROID_NDK_ROOT=//p' "$ndk_env")"
[ -n "$ndk" ] || die 4 "install-ndk.sh reported no NDK folder"
GODOT_BIN_DIR="${GODOT_BIN_DIR:-$HOME/.local/opt/godot-android-bin}" bash "$ROOT/scripts/ci/install-godot.sh" --android

# (5) The debug keystore, at the standard place. An existing file is checked and never overwritten.
keystore="${DEBUG_KEYSTORE:-$HOME/.android/debug.keystore}"
if [ -e "$keystore" ]; then
  "$jdk/bin/keytool" -list -keystore "$keystore" -alias androiddebugkey -storepass android >/dev/null 2>&1 ||
    die 6 "$keystore exists but is no Android debug keystore (alias androiddebugkey, password android): it is left as it is, set DEBUG_KEYSTORE to another path"
  say "debug keystore is in place already ($keystore)"
else
  mkdir -p "$(dirname "$keystore")"
  "$jdk/bin/keytool" -genkeypair -keystore "$keystore" -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass android -keypass android -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1 ||
    die 6 "keytool could not make the debug keystore $keystore"
  say "made the throwaway debug keystore $keystore (public debug convention; never commit it)"
fi

cat <<EOF
install-android: OK. For this session, set (keep XDG_CONFIG_HOME out of your shell: it moves git and gh config too):
export JAVA_HOME=$jdk
export ANDROID_HOME=$sdk
export ANDROID_SDK_ROOT=$sdk
export ANDROID_NDK_ROOT=$ndk
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH=$keystore
export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android
Then, from the repository root:
bash scripts/build-native.sh && bash scripts/build-native.sh --platform android --arch arm64 --target template_debug
XDG_CONFIG_HOME=$sdk/.godot-config bash scripts/export-android.sh
EOF
