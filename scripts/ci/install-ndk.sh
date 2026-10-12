#!/usr/bin/env bash
# PROBE ONLY (spike P26n, branch claude/p26n-cpp-spike, never merged): makes the Android NDK that
# scripts/build-native.sh needs available on a GitHub-hosted ubuntu-24.04 runner and points
# ANDROID_NDK_ROOT at it for the later steps of the job.
# The version is NDK_VERSION in scripts/build-native.sh (28.1.13356709, r28b): the ndk_version that
# godot-cpp's tools/android.py defaults to at the pinned godot-cpp commit. The runner image ships
# NDK 27.3 (its default), 29 and 30 and none of 28 (image ubuntu24/20261004.327), and an image
# update changes that list, so the script uses the image's copy when it has exactly this version and
# installs it with sdkmanager otherwise.
# Usage: bash scripts/ci/install-ndk.sh
# Env:   ANDROID_HOME   the runner image's SDK: cmdline-tools/latest/bin/sdkmanager and licenses/
#                       (the licences the image already accepted are copied, nothing is accepted here)
#        JAVA_HOME      JDK 17 for sdkmanager (the job selects it first)
#        RUNNER_TEMP    where a fresh SDK root for the NDK is made (default /tmp)
#        GITHUB_ENV     when set, ANDROID_NDK_ROOT=<ndk folder> is appended to it
# The install goes to its own SDK root (--sdk_root), so the image's SDK stays untouched: the Android
# export in scripts/export-android.sh still reads build-tools and platform-tools from ANDROID_HOME.
# Exit:  0 ok
#        3 prerequisite missing: ANDROID_HOME, sdkmanager, or the accepted licences
#        4 sdkmanager failed, or the NDK it left is not exactly the pinned revision / has no clang++
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

die() {
  local code="$1"
  shift
  echo "install-ndk: $*" >&2
  exit "$code"
}

version="$(sed -n 's/^NDK_VERSION="\([0-9][0-9.]*\)"$/\1/p' scripts/build-native.sh | head -n 1 || true)"
[ -n "$version" ] || die 3 "no NDK_VERSION=\"...\" line in scripts/build-native.sh"

# Pkg.Revision of an NDK folder, empty when it is no NDK.
revision_of() {
  sed -n 's/^Pkg\.Revision[[:space:]]*=[[:space:]]*\([0-9][0-9.]*\).*$/\1/p' "$1/source.properties" 2>/dev/null | head -n 1 || true
}

sdk="${ANDROID_HOME:-}"
[ -n "$sdk" ] && [ -d "$sdk" ] || die 3 "ANDROID_HOME is not set or not a folder ('$sdk')"

ndk="$sdk/ndk/$version"
if [ "$(revision_of "$ndk")" = "$version" ]; then
  echo "install-ndk: the runner image ships NDK $version"
else
  sdkmanager="$sdk/cmdline-tools/latest/bin/sdkmanager"
  [ -x "$sdkmanager" ] || die 3 "sdkmanager is missing: no $sdkmanager"
  [ -d "$sdk/licenses" ] && [ -n "$(ls -A "$sdk/licenses")" ] ||
    die 3 "no accepted Android SDK licences to copy: $sdk/licenses is missing or empty"
  root="${RUNNER_TEMP:-/tmp}/android-sdk-ndk"
  mkdir -p "$root/licenses"
  cp -R "$sdk/licenses/." "$root/licenses/"
  echo "install-ndk: the runner image has no NDK $version; sdkmanager installs ndk;$version into $root"
  # No stdin: a licence that is not accepted must fail the install, never wait for an answer.
  "$sdkmanager" "--sdk_root=$root" --install "ndk;$version" </dev/null || die 4 "sdkmanager could not install ndk;$version"
  ndk="$root/ndk/$version"
fi

have="$(revision_of "$ndk")"
[ "$have" = "$version" ] || die 4 "$ndk is NDK '${have:-unknown}', not the pinned $version"
clang="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/clang++"
[ -x "$clang" ] || die 4 "the NDK has no $clang"
clang_version="$("$clang" --version | sed -n 1p)"
echo "install-ndk: NDK $have at $ndk ($clang_version)"

if [ -n "${GITHUB_ENV:-}" ]; then
  echo "ANDROID_NDK_ROOT=$ndk" >>"$GITHUB_ENV"
else
  echo "install-ndk: GITHUB_ENV is not set; export ANDROID_NDK_ROOT=$ndk yourself"
fi
