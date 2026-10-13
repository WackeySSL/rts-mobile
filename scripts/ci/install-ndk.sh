#!/usr/bin/env bash
# Installs the Android NDK that scripts/build-native.sh pins (ADR 0013 section 8) into the Android SDK
# through sdkmanager, as <sdk>/ndk/<version>: the folder build-native.sh requires and that godot-cpp's
# tools/android.py reads as $ANDROID_HOME/ndk/<version>. The version is read from the NDK_VERSION line
# of build-native.sh, so the pin lives in that one place. Idempotent: an NDK that is installed already,
# and passes the checks build-native.sh makes, is left alone and sdkmanager is not needed. The NDK is
# never cached (ci.yml caches godot-cpp and the SCons objects only): the download is the install.
# Usage: bash scripts/ci/install-ndk.sh
# Env:   ANDROID_HOME=<Android SDK folder> (else ANDROID_SDK_ROOT; the runner image sets it),
#        SDKMANAGER=<binary> (default: <sdk>/cmdline-tools/latest/bin/sdkmanager, else sdkmanager on PATH),
#        GITHUB_ENV (CI: ANDROID_NDK_ROOT=<ndk folder> is appended for the later steps of the job).
# Needs: network access to dl.google.com (first run only), a JDK for sdkmanager, and the SDK licence
#        accepted in <sdk>/licenses (the runner image has it; this script never accepts a licence).
# Exit:  0 ok
#        2 an argument was given, or build-native.sh has no single NDK_VERSION="<major>.<minor>.<build>" line
#        3 tool missing: no SDK folder, or no sdkmanager
#        4 sdkmanager failed, or what it left is not the pinned NDK (wrong revision or an incomplete toolchain)
# Success prints "install-ndk: OK <ndk folder>". Bash 3.2 compatible.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

die() {
  local code="$1"
  shift
  echo "install-ndk: $*" >&2
  exit "$code"
}

[ $# -eq 0 ] || die 2 "takes no arguments, got '$1' (usage: bash scripts/ci/install-ndk.sh)"
pin_file="$ROOT/scripts/build-native.sh"
pin_lines="$(grep -c '^NDK_VERSION=' "$pin_file" || true)"
version="$(sed -n 's/^NDK_VERSION="\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)"$/\1/p' "$pin_file")"
[ "$pin_lines" = 1 ] && [ -n "$version" ] ||
  die 2 "scripts/build-native.sh needs exactly one NDK_VERSION=\"<major>.<minor>.<build>\" line (it has $pin_lines)"

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
sdk="${sdk%/}"
[ -n "$sdk" ] || die 3 "ANDROID_HOME is not set (the Android SDK folder; the runner image sets it)"
[ -d "$sdk" ] || die 3 "the Android SDK folder '$sdk' does not exist"
ndk="$sdk/ndk/$version"
toolchain="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"

# What build-native.sh checks before an Android build: the revision in source.properties and the tools it runs.
ndk_problem() { # prints why $ndk is not the pinned NDK, nothing when it is
  local revision tool
  revision="$(sed -n 's/^Pkg\.Revision[[:space:]]*=[[:space:]]*\([0-9][0-9.]*\).*$/\1/p' "$ndk/source.properties" 2>/dev/null | head -n 1 || true)"
  [ "$revision" = "$version" ] || { echo "'$ndk' is '${revision:-unknown}'"; return 0; }
  for tool in clang++ llvm-readelf llvm-nm; do
    [ -x "$toolchain/$tool" ] || { echo "no $toolchain/$tool"; return 0; }
  done
}

if [ -z "$(ndk_problem)" ]; then
  echo "install-ndk: Android NDK $version is installed already"
else
  sdkmanager="${SDKMANAGER:-}"
  if [ -z "$sdkmanager" ]; then
    sdkmanager="$sdk/cmdline-tools/latest/bin/sdkmanager"
    [ -x "$sdkmanager" ] || sdkmanager="sdkmanager"
  fi
  command -v "$sdkmanager" >/dev/null 2>&1 ||
    die 3 "sdkmanager is missing ('$sdkmanager'; set SDKMANAGER, or install the SDK's cmdline-tools into $sdk/cmdline-tools/latest)"
  echo "install-ndk: installing Android NDK $version into $sdk/ndk with $sdkmanager"
  status=0
  "$sdkmanager" "--sdk_root=$sdk" "ndk;$version" </dev/null || status=$?
  [ "$status" -eq 0 ] || die 4 "sdkmanager failed with exit code ${status} (a licence that is not accepted shows in its output)"
  problem="$(ndk_problem)"
  [ -z "$problem" ] || die 4 "sdkmanager did not leave the pinned NDK ${version}: $problem"
fi
if [ -n "${GITHUB_ENV:-}" ]; then echo "ANDROID_NDK_ROOT=$ndk" >>"$GITHUB_ENV"; fi
echo "install-ndk: OK $ndk"
