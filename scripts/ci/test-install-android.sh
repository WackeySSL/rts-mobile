#!/usr/bin/env bash
# Offline test of scripts/cloud/install-android.sh (P55b): the licence gate (nothing is accepted without
# --accept-android-sdk-licenses, and no automatic path holds the flag), the SHA-256 pin, JDK 17 and JAVA_HOME, the second
# run that downloads nothing, the one NDK pin (the real install-ndk.sh runs), the keystore and the closing lines. Needs no
# network, SDK, JDK or root: curl, apt-get, java, keytool, sdkmanager and install-godot.sh are stubs, in a scrubbed
# environment. ci.yml runs it in the verify job.
# Usage: bash scripts/ci/test-install-android.sh      Exit: 0 all cases pass, 1 a case failed.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
root="$(mktemp -d)"
trap 'rm -rf "${root:?}"' EXIT
failures=0
script="$repo/scripts/cloud/install-android.sh"
ndk_pin="$(sed -n 's/^NDK_VERSION="\(.*\)"$/\1/p' "$repo/scripts/build-native.sh")"
accept=--accept-android-sdk-licenses

check() { # name, wanted exit code, wanted text in the output (may be empty); uses rc and out
  if [ "$rc" = "$2" ] && { [ -z "$3" ] || grep -Fq -- "$3" <<<"$out"; }; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (wanted exit $2 and '$3', got exit $rc: $(tail -n 1 <<<"$out"))" >&2
    failures=$((failures + 1))
  fi
}
assert() { if "${@:2}"; then echo "ok: $1"; else echo "FAIL: $1" >&2; failures=$((failures + 1)); fi; } # name, command...
calls() { grep -Ec "^$1" "$root/log" || true; }                                                           # how many calls of a stub the log holds

# Stubs; each call goes to $STUB_LOG. The sdkmanager in the zip acts like the one of cmdline-tools 23.0 (it never asks,
# and records the licence itself on an install) and makes the packages it is given, as install-ndk.sh checks them. apt-get
# copies a prepared JDK.
mkdir -p "$root/bin" "$root/tools" "$root/tmp" "$root/home" "$root/fixture/cmdline-tools/bin"
cat >"$root/fixture/cmdline-tools/bin/sdkmanager" <<'STUB'
#!/usr/bin/env bash
echo "sdkmanager $* | JAVA_HOME=${JAVA_HOME:-}" >>"$STUB_LOG"
for a in "$@"; do case "$a" in --sdk_root=*) dir="${a#*=}" ;; esac; done
[ "${STUB_SDKM:-}" != fail ] || exit 1
mkdir -p "$dir/licenses" && echo accepted >"$dir/licenses/android-sdk-license"
make() { mkdir -p "$(dirname "$1")" && printf '#!/bin/sh\n' >"$1" && chmod +x "$1"; }
for a in "$@"; do case "$a" in
  platform-tools) make "$dir/platform-tools/adb" ;;
  build-tools\;*) for t in apksigner aapt2; do make "$dir/build-tools/${a#*;}/$t"; done; echo "Pkg.Revision=${a#*;}" >"$dir/build-tools/${a#*;}/source.properties" ;;
  ndk\;*) for t in clang++ llvm-readelf llvm-nm; do make "$dir/ndk/${a#*;}/toolchains/llvm/prebuilt/linux-x86_64/bin/$t"; done; echo "Pkg.Revision = ${a#*;}" >"$dir/ndk/${a#*;}/source.properties" ;;
esac; done
STUB
echo "Pkg.Revision=23.0" >"$root/fixture/cmdline-tools/source.properties"
chmod +x "$root/fixture/cmdline-tools/bin/sdkmanager"
(cd "$root/fixture" && python3 -I -m zipfile -c "$root/fixture.zip" cmdline-tools)
fixture_sha="$(sha256sum "$root/fixture.zip" | cut -d' ' -f1)"
cat >"$root/bin/curl" <<'STUB'
#!/usr/bin/env bash
echo "curl $*" >>"$STUB_LOG"
[ "${STUB_CURL:-}" != fail ] || exit 22
while [ $# -gt 0 ]; do case "$1" in -o) file="$2"; shift ;; esac; shift; done
if [ "${STUB_CURL:-}" = corrupt ]; then echo corrupt >"$file"; else cp "$STUB_ZIP" "$file"; fi
STUB
cat >"$root/bin/apt-get" <<'STUB'
#!/usr/bin/env bash
echo "apt-get $*" >>"$STUB_LOG"
[ "$1" != update ] || { touch "$STUB_LOG.updated"; exit 0; }
[ "${STUB_APT:-}" != fail ] || exit 100
[ "${STUB_APT:-}" != needs-update ] || [ -e "$STUB_LOG.updated" ] || exit 100
rm -rf "$STUB_JDK" && cp -r "$STUB_APT_FROM" "$STUB_JDK"
STUB
mkjdk() { # dir, java version: a stub JDK (java, javac, keytool); the keytool makes a keystore file and lists it
  mkdir -p "$1/bin"
  printf '#!/usr/bin/env bash\necho "Picked up JAVA_TOOL_OPTIONS: x" >&2\necho "openjdk version \\"%s\\" 2026-01-20" >&2\n' "$2" >"$1/bin/java"
  printf '#!/bin/sh\n' >"$1/bin/javac"
  cat >"$1/bin/keytool" <<'STUB'
#!/usr/bin/env bash
echo "keytool $* | $0" >>"$STUB_LOG"
while [ $# -gt 0 ]; do case "$1" in -keystore) ks="$2"; shift ;; -genkeypair) gen=1 ;; esac; shift; done
if [ -n "${gen:-}" ]; then echo debug-ks >"$ks"; else grep -q debug-ks "$ks"; fi
STUB
  chmod +x "$1"/bin/*
}
mkjdk "$root/jdk17" 17.0.20
mkjdk "$root/jdk21" 21.0.4
for tool in bash env sed grep head dirname mkdir rm mv cat cp chmod mktemp sha256sum unzip cut touch; do ln -s "$(command -v "$tool")" "$root/tools/$tool"; done
chmod +x "$root"/bin/*

# tree NAME [SHA]: the script (its pinned SHA-256 replaced by the fixture's, or by SHA), the real install-ndk.sh and
# build-native.sh, and a stub install-godot.sh. fresh NAME [JAVA]: new SDK, JDK (17.0.20 unless JAVA, or none) and
# keystore paths, an empty log. go [ENV...]: one run in the tree t (or $tname) with the flags in $flags.
tree() {
  mkdir -p "$root/$1/scripts/ci" "$root/$1/scripts/cloud"
  sed "s/^CMDLINE_TOOLS_SHA256=.*/CMDLINE_TOOLS_SHA256=\"${2:-$fixture_sha}\"/" "$script" >"$root/$1/scripts/cloud/install-android.sh"
  cp "$repo/scripts/build-native.sh" "$root/$1/scripts/"
  cp "$repo/scripts/ci/install-ndk.sh" "$root/$1/scripts/ci/"
  printf '#!/usr/bin/env bash\necho "install-godot $* GODOT_BIN_DIR=${GODOT_BIN_DIR:-}" >>"$STUB_LOG"\n' >"$root/$1/scripts/ci/install-godot.sh"
}
fresh() {
  sdk="$root/$1"
  jdk="$root/$1-jdk"
  ks="$root/$1-debug.keystore"
  : >"$root/log"
  rm -f "$root/log.updated"
  if [ "${2:-17.0.20}" != none ]; then mkjdk "$jdk" "${2:-17.0.20}"; fi
}
go() {
  rc=0
  out="$(cd "$root/${tname:-t}" && env -i PATH="$root/bin:$root/tools" HOME="$root/home" TMPDIR="$root/tmp" STUB_LOG="$root/log" STUB_ZIP="$root/fixture.zip" \
    ANDROID_HOME="$sdk" JDK17_HOME="$jdk" DEBUG_KEYSTORE="$ks" STUB_JDK="$jdk" STUB_APT_FROM="$root/jdk17" "$@" bash scripts/cloud/install-android.sh $flags 2>&1 </dev/null)" || rc=$?
}
tree t

# (1) usage and the licence gate: nothing is downloaded, installed or accepted without the flag.
fresh a
flags=--bogus go
check "install: an unknown argument" 2 "unknown argument '--bogus'"
flags="" go ANDROID_HOME=relative/sdk
check "install: the SDK folder must be absolute" 2 "must be an absolute path"
flags="" go
check "install: no flag and no earlier acceptance: stops and names the flag" 5 "$accept"
assert "install: the gate comes before any download, install or licence" test ! -s "$root/log" -a ! -e "$sdk/licenses"
fresh a2
mkdir -p "$sdk/licenses" "$sdk/cmdline-tools"
flags="" go
check "install: an SDK folder without the licence file is no acceptance either" 5 "$accept"
flags="$accept" go PATH="$root/tools"
check "install: curl missing" 3 "curl is missing"

# (2) the first run, with the flag: the pins, JDK 17 for every tool, the NDK by install-ndk.sh, the closing lines.
flags="$accept" go
check "install: first run" 0 "install-android: OK"
assert "install: the cmdline-tools zip is downloaded once, from the pinned URL" test "$(calls curl)" = 1 -a "$(grep -c 'curl .* https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip$' "$root/log")" = 1
assert "install: sdkmanager got platform-tools and build-tools 36.1.0, then the NDK of build-native.sh" test "$(sed -n 's/^sdkmanager \(.*\) | .*$/\1/p' "$root/log")" = "--sdk_root=$sdk platform-tools build-tools;36.1.0
--sdk_root=$sdk ndk;$ndk_pin"
assert "install: every sdkmanager call ran with the JAVA_HOME of JDK 17" test "$(grep -c "| JAVA_HOME=$jdk$" "$root/log")" = 2
assert "install: no apt-get call when JDK 17 is there" test "$(calls apt-get)" = 0
assert "install: the Godot template script gets --android and a bin folder of its own" grep -Fq "install-godot --android GODOT_BIN_DIR=$root/home/.local/opt/godot-android-bin" "$root/log"
assert "install: the keystore is made at the given path, by the keytool of JDK 17" grep -Fq "keytool -genkeypair -keystore $ks -alias androiddebugkey -keyalg RSA " "$root/log"
assert "install: ... and it exists" test -s "$ks" -a "$(grep -c "| $jdk/bin/keytool$" "$root/log")" = 1
missing=""
for line in "export JAVA_HOME=$jdk" "export ANDROID_HOME=$sdk" "export ANDROID_SDK_ROOT=$sdk" "export ANDROID_NDK_ROOT=$sdk/ndk/$ndk_pin" \
  "export GODOT_ANDROID_KEYSTORE_DEBUG_PATH=$ks" "export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey" "export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android" \
  "XDG_CONFIG_HOME=$sdk/.godot-config bash scripts/export-android.sh" "&& bash scripts/build-native.sh --platform android --arch arm64 --target template_debug"; do
  grep -Fq -- "$line" <<<"$out" || missing="$missing [$line]"
done
assert "install: the closing lines hold the environment and the two commands${missing:+, not:$missing}" test -z "$missing"
assert "install: no work folder is left in the SDK" test -z "$(ls -A "$sdk" | grep '^\.install-android' || true)"

# (3) the second run, without the flag: everything is checked and nothing is downloaded, installed or made again.
: >"$root/log"
flags="" go
check "install: second run" 0 "install-android: OK"
assert "install: the second run calls no curl, apt-get, sdkmanager or keytool -genkeypair" test "$(calls '(curl|apt-get|sdkmanager|keytool -genkeypair) ')" = 0
rm -r "$sdk/platform-tools"
flags="" go
check "install: no flag, licence accepted earlier: a missing package is installed" 0 "install-android: OK"
assert "install: ... by one sdkmanager call for that package only" test "$(sed -n 's/^sdkmanager \(.*\) | .*$/\1/p' "$root/log")" = "--sdk_root=$sdk platform-tools"

# (4) the SHA-256 pin, the download and the unpack.
tname=bad
tree bad 0000000000000000000000000000000000000000000000000000000000000000
fresh b
flags="$accept" go
check "install: a zip that is not the pinned one" 4 "SHA-256 mismatch"
assert "install: ... leaves no cmdline-tools and calls no sdkmanager" test ! -e "$sdk/cmdline-tools" -a "$(calls sdkmanager)" = 0
tname=t
fresh b2
flags="$accept" go STUB_CURL=corrupt
check "install: a corrupt download is no pinned zip" 4 "SHA-256 mismatch"
fresh b3
flags="$accept" go STUB_CURL=fail
check "install: the download fails" 4 "download of https://dl.google.com/"
assert "install: the real script pins a 64 digit SHA-256" grep -Eq '^CMDLINE_TOOLS_SHA256="[0-9a-f]{64}"$' "$script"

# (5) JDK 17: installed with apt-get when it is missing or is another version, and checked after.
fresh c none
flags="$accept" go
check "install: no JDK 17: apt-get installs it" 0 "installing openjdk-17-jdk-headless"
assert "install: ... with apt-get install -y" grep -Fxq "apt-get install -y openjdk-17-jdk-headless" "$root/log"
assert "install: ... and JAVA_HOME is that JDK for sdkmanager" test "$(grep -c "| JAVA_HOME=$jdk$" "$root/log")" = 2
fresh c2 21.0.4
flags="$accept" go STUB_APT_FROM="$root/jdk21"
check "install: apt-get leaves another java than 17" 4 "apt-get left no JDK 17"
fresh c3 none
flags="$accept" go STUB_APT=fail
check "install: apt-get fails" 4 "apt-get install openjdk-17-jdk-headless failed"
fresh c4 none
flags="$accept" go STUB_APT=needs-update
check "install: apt-get needs an update first" 0 "install-android: OK"
assert "install: ... install, update, install" test "$(calls apt-get)" = 3

# (6) sdkmanager and the debug keystore.
fresh d
flags="$accept" go STUB_SDKM=fail
check "install: sdkmanager fails" 4 "sdkmanager failed"
fresh d2
echo other >"$ks"
flags="$accept" go
check "install: an existing keystore that is no debug keystore" 6 "is no Android debug keystore"
assert "install: ... is left as it was" test "$(cat "$ks")" = other
echo debug-ks >"$ks"
flags="$accept" go
check "install: an existing debug keystore is kept" 0 "debug keystore is in place already"
assert "install: ... and keytool makes no other" test "$(calls 'keytool -genkeypair ')" = 0

# (7) the script file: one NDK pin, one download, and the flag only where a person types it.
assert "install: no NDK version in the script (the pin stays in build-native.sh)" test -z "$(grep -E '[0-9]+\.[0-9]+\.[0-9]{6,}|ndk;|NDK_VERSION=' "$script" || true)"
assert "install: it reaches dl.google.com only (and names the terms on developer.android.com)" test "$(grep -o 'https\?://[^/" ]*' "$script" | sort -u)" = "https://developer.android.com
https://dl.google.com"
assert "install: no automatic path names the script or the flag" test -z "$(grep -rlE -e "$accept|cloud/install-android" -- "$repo/scripts/cloud/setup.sh" "$repo/scripts/hooks" "$repo/.github" || true)"

if [ "$failures" -ne 0 ]; then
  echo "test-install-android: $failures case(s) failed" >&2
  exit 1
fi
echo "test-install-android: all cases passed"
