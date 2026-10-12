#!/usr/bin/env bash
# PROBE ONLY (spike P26n): offline test of install-ndk.sh. It runs the real script against a fake
# ANDROID_HOME with a stub sdkmanager, so nothing is downloaded and no licence is touched. ci.yml
# runs it in android-debug-apk, before the script does the real install.
# Usage: bash scripts/ci/test-install-ndk.sh      Exit: 0 all cases pass, 1 a case failed.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/install-ndk.sh"
version="$(sed -n 's/^NDK_VERSION="\([0-9][0-9.]*\)"$/\1/p' "$here/../build-native.sh")"
[ -n "$version" ] || {
  echo "test-install-ndk: no NDK_VERSION in scripts/build-native.sh"
  exit 1
}
root="$(mktemp -d)"
trap 'rm -rf "${root:?}"' EXIT

# make_ndk DIR REVISION: a folder that looks like an NDK with a clang++ stub.
make_ndk() {
  mkdir -p "$1/toolchains/llvm/prebuilt/linux-x86_64/bin"
  printf 'Pkg.Desc = Android NDK\nPkg.Revision = %s\n' "$2" >"$1/source.properties"
  printf '#!/usr/bin/env bash\necho "stub clang version 0 (NDK %s)"\n' "$2" >"$1/toolchains/llvm/prebuilt/linux-x86_64/bin/clang++"
  chmod +x "$1/toolchains/llvm/prebuilt/linux-x86_64/bin/clang++"
}

# make_sdk NAME [no-sdkmanager] [no-licences]: a fake ANDROID_HOME under $root/NAME.
make_sdk() {
  local sdk="$root/$1"
  mkdir -p "$sdk"
  if [ "${2:-}" != no-sdkmanager ]; then
    mkdir -p "$sdk/cmdline-tools/latest/bin"
    cat >"$sdk/cmdline-tools/latest/bin/sdkmanager" <<'STUB'
#!/usr/bin/env bash
# Stub: logs its arguments, then "installs" the NDK that STUB_REVISION names into --sdk_root.
echo "sdkmanager $*" >>"$STUB_LOG"
[ -z "${STUB_FAIL:-}" ] || exit 1
for arg in "$@"; do
  case "$arg" in --sdk_root=*) sdk_root="${arg#--sdk_root=}" ;; ndk\;*) version="${arg#ndk;}" ;; esac
done
[ -s "$sdk_root/licenses/android-sdk-license" ] || { echo "licence not accepted" >&2; exit 1; }
dir="$sdk_root/ndk/$version"
mkdir -p "$dir/toolchains/llvm/prebuilt/linux-x86_64/bin"
printf 'Pkg.Revision = %s\n' "${STUB_REVISION:-$version}" >"$dir/source.properties"
printf '#!/usr/bin/env bash\necho "stub clang"\n' >"$dir/toolchains/llvm/prebuilt/linux-x86_64/bin/clang++"
chmod +x "$dir/toolchains/llvm/prebuilt/linux-x86_64/bin/clang++"
STUB
    chmod +x "$sdk/cmdline-tools/latest/bin/sdkmanager"
  fi
  if [ "${3:-}" != no-licences ]; then
    mkdir -p "$sdk/licenses"
    printf '24333f8a63b6825ea9c5514f83c2829b004d1fee\n' >"$sdk/licenses/android-sdk-license"
  fi
}

failures=0
# run_case NAME WANT_RC LOG_REGEX SDK [VAR=value ...]: runs the script, then the caller checks.
run_case() {
  local name="$1" want="$2" regex="$3" sdk="$4" rc=0 out
  shift 4
  : >"$root/log"
  : >"$root/github-env"
  rm -rf "$root/tmp"
  mkdir -p "$root/tmp"
  out="$(env -u ANDROID_HOME STUB_LOG="$root/log" GITHUB_ENV="$root/github-env" RUNNER_TEMP="$root/tmp" \
    "$@" ${sdk:+ANDROID_HOME="$root/$sdk"} bash "$script" 2>&1)" || rc=$?
  if [ "$rc" != "$want" ] || ! grep -Eq "$regex" <<<"$out"; then
    echo "FAIL $name: exit $rc (want $want), output:"
    echo "$out"
    failures=$((failures + 1))
    return
  fi
  if [ "$want" != 0 ] && [ -s "$root/github-env" ]; then
    echo "FAIL $name: a failed run wrote ANDROID_NDK_ROOT to GITHUB_ENV"
    failures=$((failures + 1))
    return
  fi
  echo "ok   $name: exit $rc"
}
expect_file() { # NAME FILE REGEX
  if ! grep -Eq "$3" "$2"; then
    echo "FAIL $1: $2 lacks '$3':"
    cat "$2"
    failures=$((failures + 1))
  fi
}

# 1. The image ships the exact version: used as is, sdkmanager is not called.
make_sdk image
make_ndk "$root/image/ndk/$version" "$version"
run_case "image ships the pinned NDK" 0 "image ships NDK $version" image
expect_file "image ships the pinned NDK" "$root/github-env" "^ANDROID_NDK_ROOT=$root/image/ndk/$version\$"
[ ! -s "$root/log" ] || {
  echo "FAIL image ships the pinned NDK: sdkmanager was called"
  failures=$((failures + 1))
}

# 2. The image has other NDKs only: installed into its own SDK root with the image's licences.
make_sdk other
make_ndk "$root/other/ndk/27.3.13750724" "27.3.13750724"
run_case "install when the image lacks it" 0 "installs ndk;$version" other
expect_file "install when the image lacks it" "$root/github-env" "^ANDROID_NDK_ROOT=$root/tmp/android-sdk-ndk/ndk/$version\$"
expect_file "install when the image lacks it" "$root/log" "^sdkmanager --sdk_root=$root/tmp/android-sdk-ndk --install ndk;$version\$"
[ ! -e "$root/other/ndk/$version" ] || {
  echo "FAIL install when the image lacks it: the image's SDK was changed"
  failures=$((failures + 1))
}

# 3. A folder named like the pinned version but holding another revision is not used.
make_sdk renamed
make_ndk "$root/renamed/ndk/$version" "27.3.13750724"
run_case "wrong revision in the pinned folder falls back to the install" 0 "installs ndk;$version" renamed
expect_file "wrong revision in the pinned folder" "$root/github-env" "^ANDROID_NDK_ROOT=$root/tmp/android-sdk-ndk/"

# 4. Failures keep their exit codes.
make_sdk badrev
run_case "installed NDK has another revision" 4 "not the pinned $version" badrev STUB_REVISION=29.0.14206865
make_sdk failing
run_case "sdkmanager fails" 4 "could not install ndk;$version" failing STUB_FAIL=1
make_sdk nomanager no-sdkmanager
run_case "sdkmanager missing" 3 "sdkmanager is missing" nomanager
make_sdk nolicence "" no-licences
run_case "licences missing" 3 "no accepted Android SDK licences" nolicence
run_case "ANDROID_HOME unset" 3 "ANDROID_HOME is not set" ""

if [ "$failures" -ne 0 ]; then
  echo "test-install-ndk: $failures case(s) failed"
  exit 1
fi
echo "test-install-ndk: all cases pass"
