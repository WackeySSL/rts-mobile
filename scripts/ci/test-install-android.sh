#!/usr/bin/env bash
# Offline test of scripts/cloud/install-android.sh (P55b). The licence gate: without --accept-android-sdk-licenses the
# script only checks (a missing piece is exit 5 before anything is made, a complete SDK is exit 0 without one sdkmanager
# call, and an earlier licence file changes neither) and no automatic path holds the flag. Also: the SHA-256 pins of the
# two downloads, the pinned Android CLI that the sdkmanager shim runs, JDK 17 and JAVA_HOME, the defaults a session runs
# with, the second run that downloads nothing, the one NDK pin (the real install-ndk.sh runs), the Godot editor that is
# reused, the keystore and the closing lines. Needs no network, SDK, JDK or root: curl, apt-get, java, keytool,
# sdkmanager and install-godot.sh are stubs, in a scrubbed environment. Needs git for the last case (else it uses find).
# ci.yml runs it in the verify job.
# Usage: bash scripts/ci/test-install-android.sh      Exit: 0 all cases pass, 1 a case failed.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
root="$(mktemp -d)"
trap 'rm -rf "${root:?}"' EXIT
failures=0
script="$repo/scripts/cloud/install-android.sh"
ndk_pin="$(sed -n 's/^NDK_VERSION="\(.*\)"$/\1/p' "$repo/scripts/build-native.sh")"
cli_version="$(sed -n 's/^ANDROID_CLI_VERSION="\(.*\)"$/\1/p' "$script")"
accept=--accept-android-sdk-licenses
zip_url=https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip
cli_url="https://dl.google.com/android/cli/$cli_version/linux_x86_64/android-cli"

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
downloads() { grep -Ec "^curl .* $1\$" "$root/log" || true; }                                             # how many downloads of one URL the log holds
sdkm_args() { sed -n 's/^sdkmanager \(.*\) | JAVA_HOME=.*$/\1/p' "$root/log"; }                           # the arguments of each sdkmanager call

# Stubs; each call goes to $STUB_LOG. The sdkmanager in the zip acts like the shim of cmdline-tools 23.0: it needs the
# Android CLI in ANDROID_CLI_BIN (else its launcher would fetch the unpinned latest), never asks, records the licence
# itself on an install and makes the packages it is given, as install-ndk.sh checks them (STUB_SDKM=fail exits 1, noop
# exits 0 and makes nothing, old-ndk makes an NDK of another revision). apt-get copies a prepared JDK.
mkdir -p "$root/bin" "$root/tools" "$root/tmp" "$root/home" "$root/fixture/cmdline-tools/bin" "$root/gbin" "$root/gh"
cat >"$root/fixture/cmdline-tools/bin/sdkmanager" <<'STUB'
#!/usr/bin/env bash
echo "sdkmanager $* | JAVA_HOME=${JAVA_HOME:-} | ANDROID_CLI_BIN=${ANDROID_CLI_BIN:-}" >>"$STUB_LOG"
for a in "$@"; do case "$a" in --sdk_root=*) dir="${a#*=}" ;; esac; done
if [ ! -x "${ANDROID_CLI_BIN:-}" ] || [ "$(cat "$ANDROID_CLI_BIN")" != "$(cat "$STUB_CLI")" ]; then
  echo "stub sdkmanager: no pinned Android CLI in ANDROID_CLI_BIN, its launcher would fetch the latest" >&2
  exit 1
fi
[ "${STUB_SDKM:-}" != fail ] || exit 1
[ "${STUB_SDKM:-}" != noop ] || exit 0
mkdir -p "$dir/licenses" && echo accepted >"$dir/licenses/android-sdk-license"
make() { mkdir -p "$(dirname "$1")" && printf '#!/bin/sh\n' >"$1" && chmod +x "$1"; }
for a in "$@"; do case "$a" in
  platform-tools) make "$dir/platform-tools/adb" ;;
  build-tools\;*) for t in apksigner aapt2; do make "$dir/build-tools/${a#*;}/$t"; done; echo "Pkg.Revision=${a#*;}" >"$dir/build-tools/${a#*;}/source.properties" ;;
  ndk\;*)
    rev="${a#*;}"
    [ "${STUB_SDKM:-}" != old-ndk ] || rev=28.1.13356709
    for t in clang++ llvm-readelf llvm-nm; do make "$dir/ndk/${a#*;}/toolchains/llvm/prebuilt/linux-x86_64/bin/$t"; done
    echo "Pkg.Revision = $rev" >"$dir/ndk/${a#*;}/source.properties"
    ;;
esac; done
STUB
echo "Pkg.Revision=23.0" >"$root/fixture/cmdline-tools/source.properties"
chmod +x "$root/fixture/cmdline-tools/bin/sdkmanager"
(cd "$root/fixture" && python3 -I -m zipfile -c "$root/fixture.zip" cmdline-tools)
fixture_sha="$(sha256sum "$root/fixture.zip" | cut -d' ' -f1)"
printf '#!/bin/sh\necho android-cli stub\n' >"$root/fixture-cli"
cli_sha="$(sha256sum "$root/fixture-cli" | cut -d' ' -f1)"
echo corrupt >"$root/corrupt"
cat >"$root/bin/curl" <<'STUB'
#!/usr/bin/env bash
echo "curl $*" >>"$STUB_LOG"
[ "${STUB_CURL:-}" != fail ] || exit 22
while [ $# -gt 0 ]; do case "$1" in -o) file="$2"; shift ;; esac; url="$1"; shift; done
case "$url" in
  */android-cli) src="$STUB_CLI"; [ "${STUB_CURL:-}" != corrupt-cli ] || src="$STUB_BAD" ;;
  *) src="$STUB_ZIP"; [ "${STUB_CURL:-}" != corrupt ] || src="$STUB_BAD" ;;
esac
cp "$src" "$file"
STUB
cat >"$root/bin/apt-get" <<'STUB'
#!/usr/bin/env bash
echo "apt-get $*" >>"$STUB_LOG"
[ "$1" != update ] || { touch "$STUB_LOG.updated"; exit 0; }
[ "${STUB_APT:-}" != fail ] || exit 100
[ "${STUB_APT:-}" != needs-update ] || [ -e "$STUB_LOG.updated" ] || exit 100
rm -rf "$STUB_JDK" && cp -r "$STUB_APT_FROM" "$STUB_JDK"
STUB
mkjdk() { # dir, java version: a stub JDK (java, javac, keytool). The keytool keeps the alias and the store password it
  # was given in the keystore file, and lists only with the same ones (as the real one does); a different key
  # password is an error, since Godot is given one password for both.
  mkdir -p "$1/bin"
  printf '#!/usr/bin/env bash\necho "Picked up JAVA_TOOL_OPTIONS: x" >&2\necho "openjdk version \\"%s\\" 2026-01-20" >&2\n' "$2" >"$1/bin/java"
  printf '#!/bin/sh\n' >"$1/bin/javac"
  cat >"$1/bin/keytool" <<'STUB'
#!/usr/bin/env bash
echo "keytool $* | $0" >>"$STUB_LOG"
while [ $# -gt 0 ]; do case "$1" in -keystore) ks="$2"; shift ;; -alias) alias="$2"; shift ;; -storepass) pass="$2"; shift ;; -keypass) keypass="$2"; shift ;; -genkeypair) gen=1 ;; esac; shift; done
if [ -n "${gen:-}" ]; then
  [ "${keypass:-}" = "${pass:-}" ] || exit 1
  echo "debug-ks alias=${alias:-} storepass=${pass:-}" >"$ks"
else
  grep -qx "debug-ks alias=${alias:-} storepass=${pass:-}" "$ks"
fi
STUB
  chmod +x "$1"/bin/*
}
mkjdk "$root/jdk17" 17.0.20
mkjdk "$root/jdk21" 21.0.4
for tool in bash env sed grep head dirname mkdir rm mv cat cp chmod mktemp sha256sum unzip cut touch readlink; do ln -s "$(command -v "$tool")" "$root/tools/$tool"; done
chmod +x "$root"/bin/*
# The session's godot: a symlink to the very file that install-godot.sh pins (the stub's pin is 9.9.9), and a copy named for another version.
printf '#!/bin/sh\n' >"$root/gh/Godot_v9.9.9-stable_linux.x86_64"
cp "$root/gh/Godot_v9.9.9-stable_linux.x86_64" "$root/gh/Godot_v1.0-stable_linux.x86_64"
chmod +x "$root"/gh/*
ln -s "$root/gh/Godot_v9.9.9-stable_linux.x86_64" "$root/gbin/godot"
mkdir -p "$root/gbin-other"
ln -s "$root/gh/Godot_v1.0-stable_linux.x86_64" "$root/gbin-other/godot"

# tree NAME [ZIP-SHA [CLI-SHA [GODOT-PIN]]]: the script (its pinned SHA-256s replaced by the fixtures', or by the ones given), the
# real install-ndk.sh and build-native.sh, and a stub install-godot.sh (pin 9.9.9, or GODOT-PIN; STUB_GODOT_RC makes it fail).
# fresh NAME [JAVA]: new SDK, JDK (17.0.20 unless JAVA, or none) and keystore paths, an empty log.
# go [ENV...]: one run in the tree t (or $tname) with the flags in $flags; a later ENV beats an earlier one.
tree() {
  mkdir -p "$root/$1/scripts/ci" "$root/$1/scripts/cloud"
  sed -e "s/^CMDLINE_TOOLS_SHA256=.*/CMDLINE_TOOLS_SHA256=\"${2:-$fixture_sha}\"/" -e "s/^ANDROID_CLI_SHA256=.*/ANDROID_CLI_SHA256=\"${3:-$cli_sha}\"/" \
    "$script" >"$root/$1/scripts/cloud/install-android.sh"
  cp "$repo/scripts/build-native.sh" "$root/$1/scripts/"
  cp "$repo/scripts/ci/install-ndk.sh" "$root/$1/scripts/ci/"
  cat >"$root/$1/scripts/ci/install-godot.sh" <<'STUB'
#!/usr/bin/env bash
PINNED_VERSION="9.9.9"
echo "install-godot $* GODOT_BIN_DIR=${GODOT_BIN_DIR:-} GODOT_HOME=${GODOT_HOME:-}" >>"$STUB_LOG"
exit "${STUB_GODOT_RC:-0}"
STUB
  sed -i "s/^PINNED_VERSION=.*/PINNED_VERSION=\"${4:-9.9.9}\"/" "$root/$1/scripts/ci/install-godot.sh"
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
    STUB_CLI="$root/fixture-cli" STUB_BAD="$root/corrupt" ANDROID_HOME="$sdk" JDK17_HOME="$jdk" DEBUG_KEYSTORE="$ks" STUB_JDK="$jdk" STUB_APT_FROM="$root/jdk17" \
    "$@" bash scripts/cloud/install-android.sh $flags 2>&1 </dev/null)" || rc=$?
}
listing() { find "$1" 2>/dev/null | sort; } # everything below a folder, to see that a run changed nothing
tree t

# (1) usage and the licence gate: without the flag nothing is downloaded, installed, made or accepted. The fixture has no
# JDK, so an apt-get before the gate would show in the log, and the SDK folder must not even exist afterwards.
fresh a none
flags=--bogus go
check "install: an unknown argument" 2 "unknown argument '--bogus'"
flags="" go ANDROID_HOME=relative/sdk
check "install: the SDK folder must be absolute" 2 "must be an absolute path"
flags="" go
check "install: no flag, nothing installed: stops and names the flag" 5 "$accept"
assert "install: ... before any download, install or licence (no call, no SDK folder, no JDK, no keystore)" test ! -s "$root/log" -a ! -e "$sdk" -a ! -e "$jdk" -a ! -e "$ks"
fresh a2 none
mkdir -p "$sdk/licenses" "$sdk/cmdline-tools"
echo accepted >"$sdk/licenses/android-sdk-license"
flags="" go
check "install: a licence file of an earlier run is no consent for a new install" 5 "$accept"
assert "install: ... and the SDK folder is as it was" test ! -s "$root/log" -a "$(listing "$sdk")" = "$sdk
$sdk/cmdline-tools
$sdk/licenses
$sdk/licenses/android-sdk-license"
flags="$accept" go PATH="$root/tools"
check "install: curl missing" 3 "curl is missing"

# (2) the first run, with the flag: the pins, the Android CLI for every sdkmanager call, JDK 17 for every tool, the NDK by
# install-ndk.sh, the closing lines.
fresh a
flags="$accept" go
check "install: first run" 0 "install-android: OK"
assert "install: the zip and the Android CLI are downloaded once each, from their pinned URLs" test "$(calls curl)" = 2 -a "$(downloads "$zip_url")" = 1 -a "$(downloads "$cli_url")" = 1
assert "install: sdkmanager got platform-tools and build-tools 36.1.0, then the NDK of build-native.sh" test "$(sdkm_args)" = "--sdk_root=$sdk platform-tools build-tools;36.1.0
--sdk_root=$sdk ndk;$ndk_pin"
assert "install: every sdkmanager call ran with the JAVA_HOME of JDK 17" test "$(grep -c "| JAVA_HOME=$jdk | " "$root/log")" = 2
assert "install: ... and with the pinned Android CLI of the SDK folder as ANDROID_CLI_BIN (install-ndk.sh's too)" test "$(grep -c "| ANDROID_CLI_BIN=$sdk/.android-cli/$cli_version/android-cli$" "$root/log")" = 2 -a -x "$sdk/.android-cli/$cli_version/android-cli"
assert "install: no apt-get call when JDK 17 is there" test "$(calls apt-get)" = 0
assert "install: the Godot template script gets --android and a bin folder of its own" grep -Fq "install-godot --android GODOT_BIN_DIR=$root/home/.local/opt/godot-android-bin" "$root/log"
assert "install: the keystore is made at the given path, by the keytool of JDK 17" grep -Fq "keytool -genkeypair -keystore $ks -alias androiddebugkey -keyalg RSA " "$root/log"
assert "install: ... and it exists" test -s "$ks" -a "$(grep -c "| $jdk/bin/keytool$" "$root/log")" = 1
user="$(sed -n 's/^export GODOT_ANDROID_KEYSTORE_DEBUG_USER=//p' <<<"$out")"
pass="$(sed -n 's/^export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=//p' <<<"$out")"
assert "install: the alias and password it printed are the ones the keystore was made with (and the key has the same password)" test "$(cat "$ks")" = "debug-ks alias=$user storepass=$pass" -a "$user" = androiddebugkey -a "$pass" = android
missing=""
for line in "export JAVA_HOME=$jdk" "export ANDROID_HOME=$sdk" "export ANDROID_SDK_ROOT=$sdk" "export ANDROID_NDK_ROOT=$sdk/ndk/$ndk_pin" \
  "export GODOT_ANDROID_KEYSTORE_DEBUG_PATH=$ks" "export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey" "export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android" \
  "XDG_CONFIG_HOME=$sdk/.godot-config bash scripts/export-android.sh" "&& bash scripts/build-native.sh --platform android --arch arm64 --target template_debug"; do
  grep -Fq -- "$line" <<<"$out" || missing="$missing [$line]"
done
assert "install: the closing lines hold the environment and the two commands${missing:+, not:$missing}" test -z "$missing"
assert "install: no work folder is left in the SDK" test -z "$(ls -A "$sdk" | grep '^\.install-android' || true)"

# (3) the second run, with and without the flag: everything is checked and nothing is downloaded, installed or made again.
# The Android CLI is not even needed when no package is, so it may be gone.
: >"$root/log"
flags="" go
check "install: second run, no flag" 0 "install-android: OK"
assert "install: ... calls no curl, apt-get, sdkmanager or keytool -genkeypair" test "$(calls '(curl|apt-get|sdkmanager|keytool -genkeypair) ')" = 0
rm -r "$sdk/.android-cli"
flags="$accept" go
check "install: second run, with the flag, and no Android CLI" 0 "install-android: OK"
assert "install: ... calls no curl, apt-get, sdkmanager or keytool -genkeypair" test "$(calls '(curl|apt-get|sdkmanager|keytool -genkeypair) ')" = 0
mkdir -p "$sdk/.install-android-work" && : >"$sdk/.install-android-work/stale.zip"
flags="" go
check "install: a work folder that a killed run left behind" 0 "install-android: OK"
assert "install: ... is cleared" test ! -e "$sdk/.install-android-work"

# A missing piece: without the flag it is exit 5, no sdkmanager call and no change, with the flag one sdkmanager call.
# The licence file of the first run is there all along.
assert "install: the first run recorded the licence (the file stays for the cases below)" test -s "$sdk/licenses/android-sdk-license"
rm -r "$sdk/platform-tools"
before="$(listing "$sdk")"
: >"$root/log"
flags="" go
check "install: no flag, platform-tools missing, licence recorded earlier" 5 "$accept"
assert "install: ... names the piece, calls nothing and changes nothing" test "$(grep -c 'platform-tools' <<<"$out")" -ge 1 -a ! -s "$root/log" -a "$(listing "$sdk")" = "$before"
flags="$accept" go
check "install: with the flag, platform-tools missing" 0 "install-android: OK"
assert "install: ... one sdkmanager call for that package only, and the pinned Android CLI is fetched again (it was removed)" test "$(sdkm_args)" = "--sdk_root=$sdk platform-tools" -a "$(calls curl)" = 1 -a "$(downloads "$cli_url")" = 1
rm -r "$sdk/build-tools"
: >"$root/log"
flags="" go
check "install: no flag, build-tools missing" 5 "build-tools 36.1.0"
assert "install: ... calls nothing" test ! -s "$root/log"
mkdir -p "$sdk/build-tools/36.1.0" && echo "Pkg.Revision=35.0.0" >"$sdk/build-tools/36.1.0/source.properties"
printf '#!/bin/sh\n' | tee "$sdk/build-tools/36.1.0/apksigner" >"$sdk/build-tools/36.1.0/aapt2" && chmod +x "$sdk/build-tools/36.1.0/apksigner" "$sdk/build-tools/36.1.0/aapt2"
flags="" go
check "install: no flag, build-tools of the pinned name but another revision" 5 "build-tools 36.1.0"
flags="$accept" go
check "install: with the flag, ... it is installed over" 0 "install-android: OK"
assert "install: ... by one sdkmanager call, the Android CLI in place already" test "$(sdkm_args)" = "--sdk_root=$sdk build-tools;36.1.0" -a "$(calls curl)" = 0 -a "$(downloads "$cli_url")" = 0
rm -r "$sdk/ndk"
: >"$root/log"
flags="" go
check "install: no flag, the NDK missing" 5 "the pinned NDK"
assert "install: ... calls nothing (install-ndk.sh only checks)" test ! -s "$root/log" -a ! -e "$sdk/ndk"
flags="$accept" go
check "install: with the flag, the NDK missing" 0 "install-android: OK"
assert "install: ... installed by install-ndk.sh through one sdkmanager call" test "$(sdkm_args)" = "--sdk_root=$sdk ndk;$ndk_pin" -a "$(calls curl)" = 0
echo "Pkg.Revision = 28.1.13356709" >"$sdk/ndk/$ndk_pin/source.properties"
: >"$root/log"
flags="" go
check "install: no flag, an NDK of the pinned name but another revision" 5 "the pinned NDK"
assert "install: ... calls nothing" test ! -s "$root/log"
flags="$accept" go
check "install: with the flag, ... it is installed over" 0 "install-android: OK"
echo "Pkg.Revision=11.0" >"$sdk/cmdline-tools/latest/source.properties"
rm -rf "$jdk"
: >"$root/log"
flags="" go
check "install: no flag, cmdline-tools of another revision" 5 "cmdline-tools 23.0"
assert "install: ... calls nothing (no apt-get for the JDK that is gone either)" test ! -s "$root/log" -a "$(cat "$sdk/cmdline-tools/latest/source.properties")" = "Pkg.Revision=11.0"
mkdir -p "$sdk/.install-android-work/unzipped/cmdline-tools" && : >"$sdk/.install-android-work/unzipped/cmdline-tools/stale-file"
flags="$accept" go
check "install: with the flag, cmdline-tools of another revision (and an unpack folder that a killed run left)" 0 "install-android: OK"
assert "install: ... the pinned zip replaces them (one download, revision 23.0 after, nothing of the stale folder in them)" test "$(downloads "$zip_url")" = 1 -a "$(downloads "$cli_url")" = 0 -a "$(cat "$sdk/cmdline-tools/latest/source.properties")" = "Pkg.Revision=23.0" -a ! -e "$sdk/cmdline-tools/latest/stale-file"
rm -r "$sdk/platform-tools"
echo tampered >"$sdk/.android-cli/$cli_version/android-cli"
: >"$root/log"
flags="$accept" go
check "install: a pinned Android CLI that does not match its SHA-256 is fetched again" 0 "install-android: OK"
assert "install: ... one download of it, and sdkmanager ran with the good one" test "$(downloads "$cli_url")" = 1 -a "$(calls sdkmanager)" = 1 -a "$(cat "$sdk/.android-cli/$cli_version/android-cli")" = "$(cat "$root/fixture-cli")"

# The defaults a session runs with, when ANDROID_HOME, ANDROID_SDK_ROOT and DEBUG_KEYSTORE are not set: the SDK in
# ~/Android/Sdk, the keystore in ~/.android, and nothing written into the repository (the tree the script runs in).
fresh d
sdk="$root/home/Android/Sdk"
ks="$root/home/.android/debug.keystore"
tree_before="$(listing "$root/t")"
flags="$accept" go ANDROID_HOME= DEBUG_KEYSTORE=
check "install: defaults: no ANDROID_HOME, ANDROID_SDK_ROOT or DEBUG_KEYSTORE" 0 "export ANDROID_HOME=$sdk"
assert "install: ... the SDK is in ~/Android/Sdk and the keystore in ~/.android/debug.keystore" test -x "$sdk/platform-tools/adb" -a -s "$ks" -a "$(grep -c "keytool -genkeypair -keystore $ks " "$root/log")" = 1
assert "install: ... and nothing is written into the tree the script runs in" test "$(listing "$root/t")" = "$tree_before"
fresh e
flags="$accept" go ANDROID_HOME= ANDROID_SDK_ROOT="$sdk"
check "install: defaults: only ANDROID_SDK_ROOT is set" 0 "export ANDROID_HOME=$sdk"
assert "install: ... it is the SDK folder" test -x "$sdk/platform-tools/adb" -a -x "$sdk/build-tools/36.1.0/apksigner"
assert "install: the default JDK 17 is the Ubuntu one, JAVA_HOME is checked to be 17 (the system default java is never changed)" grep -Fq 'JDK17_HOME:-/usr/lib/jvm/java-17-openjdk-amd64' "$script"

# (4) the SHA-256 pins, the downloads and the unpack.
tname=bad
tree bad 0000000000000000000000000000000000000000000000000000000000000000
fresh b
flags="$accept" go
check "install: a zip that is not the pinned one" 4 "SHA-256 mismatch for the cmdline-tools zip"
assert "install: ... leaves no cmdline-tools and calls no sdkmanager" test ! -e "$sdk/cmdline-tools" -a "$(calls sdkmanager)" = 0
tname=bad2
tree bad2 "$fixture_sha" 0000000000000000000000000000000000000000000000000000000000000000
fresh b1
flags="$accept" go
check "install: an Android CLI that is not the pinned one" 4 "SHA-256 mismatch for the Android CLI"
assert "install: ... is not kept, and sdkmanager is not called" test ! -e "$sdk/.android-cli" -a "$(calls sdkmanager)" = 0 -a ! -e "$sdk/.install-android-work"
tname=t
fresh b2
flags="$accept" go STUB_CURL=corrupt
check "install: a corrupt download of the zip is no pinned zip" 4 "SHA-256 mismatch"
fresh b2c
flags="$accept" go STUB_CURL=corrupt-cli
check "install: a corrupt download of the Android CLI is no pinned CLI" 4 "SHA-256 mismatch for the Android CLI"
fresh b3
flags="$accept" go STUB_CURL=fail
check "install: the download fails" 4 "download of https://dl.google.com/"
assert "install: the real script pins two 64 digit SHA-256s" test "$(grep -Ec '^(CMDLINE_TOOLS|ANDROID_CLI)_SHA256="[0-9a-f]{64}"$' "$script")" = 2
assert "install: ... and every download goes through one function that checks it (one curl, one sha256sum of its file)" test "$(grep -c 'curl -f' "$script")" = 1 -a "$(grep -Ec 'sha256sum "\$2"' "$script")" = 1

# (5) JDK 17: installed with apt-get when it is missing or is another version, and checked after.
fresh c none
flags="$accept" go
check "install: no JDK 17: apt-get installs it" 0 "installing openjdk-17-jdk-headless"
assert "install: ... with apt-get install -y" grep -Fxq "apt-get install -y openjdk-17-jdk-headless" "$root/log"
assert "install: ... and JAVA_HOME is that JDK for sdkmanager" test "$(grep -c "| JAVA_HOME=$jdk | " "$root/log")" = 2
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

# (6) sdkmanager, the scripts it hands over to, and the debug keystore.
fresh d1
flags="$accept" go STUB_SDKM=fail
check "install: sdkmanager fails" 4 "sdkmanager failed"
fresh d1b
flags="$accept" go STUB_SDKM=noop
check "install: sdkmanager exits 0 and installs nothing" 4 "sdkmanager did not leave platform-tools and build-tools"
fresh d1c
flags="$accept" go STUB_SDKM=old-ndk
check "install: sdkmanager leaves an NDK of another revision: install-ndk.sh's own exit and message" 4 "install-ndk: sdkmanager did not leave the pinned NDK"
assert "install: ... and it is the last word, no OK" test "$(tail -n 1 <<<"$out" | cut -c1-12)" = "install-ndk:"
fresh d1d
flags="$accept" go STUB_GODOT_RC=7
check "install: install-godot.sh fails: its exit code ends the script" 7 ""
assert "install: ... and no OK is printed" test -z "$(grep -F 'install-android: OK' <<<"$out" || true)"
tname=nondk
tree nondk
printf '#!/usr/bin/env bash\nexit 0\n' >"$root/nondk/scripts/ci/install-ndk.sh"
fresh d1e
flags="$accept" go
check "install: install-ndk.sh reports no NDK folder" 4 "install-ndk.sh reported no NDK folder"
tname=t
fresh d2
echo other >"$ks"
flags="$accept" go
check "install: an existing keystore that is no debug keystore" 6 "is no Android debug keystore"
assert "install: ... is left as it was" test "$(cat "$ks")" = other
echo "debug-ks alias=other storepass=android" >"$ks"
flags="$accept" go
check "install: an existing keystore of another alias" 6 "is no Android debug keystore"
echo "debug-ks alias=androiddebugkey storepass=secret" >"$ks"
flags="$accept" go
check "install: an existing keystore of another password" 6 "is no Android debug keystore"
assert "install: ... is left as it was" test "$(cat "$ks")" = "debug-ks alias=androiddebugkey storepass=secret"
echo "debug-ks alias=androiddebugkey storepass=android" >"$ks"
flags="$accept" go
check "install: an existing debug keystore is kept" 0 "debug keystore is in place already"
assert "install: ... and keytool makes no other" test "$(calls 'keytool -genkeypair ')" = 0

# (7) the Godot editor: the session's godot is reused when it is the very file install-godot.sh pins (read from its
# file, no version in the installer), else install-godot.sh's default stays; GODOT_HOME from the environment wins.
fresh g
flags="$accept" go PATH="$root/bin:$root/tools:$root/gbin"
check "install: the session's godot is the pinned file" 0 "install-android: OK"
gh_real="$(cd "$root/gh" && pwd -P)"
assert "install: ... its folder is GODOT_HOME for install-godot.sh, so no second editor is unpacked" grep -Fq "GODOT_BIN_DIR=$root/home/.local/opt/godot-android-bin GODOT_HOME=$gh_real" "$root/log"
fresh g2
flags="$accept" go PATH="$root/bin:$root/tools:$root/gbin-other"
check "install: the session's godot is another version" 0 "install-android: OK"
assert "install: ... GODOT_HOME stays unset" test "$(grep -c 'GODOT_HOME=$' "$root/log")" = 1
fresh g3
flags="$accept" go
check "install: no godot on PATH" 0 "install-android: OK"
assert "install: ... GODOT_HOME stays unset" test "$(grep -c 'GODOT_HOME=$' "$root/log")" = 1
tname=gt
tree gt "$fixture_sha" "$cli_sha" 8.8.8
cp "$root/gh/Godot_v9.9.9-stable_linux.x86_64" "$root/gh/Godot_v8.8.8-stable_linux.x86_64"
mkdir -p "$root/gbin-8" && ln -s "$root/gh/Godot_v8.8.8-stable_linux.x86_64" "$root/gbin-8/godot"
fresh g5
flags="$accept" go PATH="$root/bin:$root/tools:$root/gbin-8"
check "install: the pin is the one in install-godot.sh (8.8.8 here), and godot is that file" 0 "install-android: OK"
assert "install: ... it is reused" grep -Fq "GODOT_HOME=$gh_real" "$root/log"
fresh g6
flags="$accept" go PATH="$root/bin:$root/tools:$root/gbin"
check "install: ... and the 9.9.9 file of the first case is not that pin" 0 "install-android: OK"
assert "install: ... GODOT_HOME stays unset" test "$(grep -c 'GODOT_HOME=$' "$root/log")" = 1
tname=t
fresh g4
flags="$accept" go PATH="$root/bin:$root/tools:$root/gbin" GODOT_HOME="$root/mine"
check "install: GODOT_HOME is set" 0 "install-android: OK"
assert "install: ... it is kept" grep -Fq "GODOT_HOME=$root/mine" "$root/log"

# (8) the script file: one NDK pin, the hosts it reaches, and the flag only where a person types it.
assert "install: no NDK version in the script (the pin stays in build-native.sh)" test -z "$(grep -E "[0-9]{2,}\.[0-9]+\.[0-9]{6,}|ndk;|NDK_VERSION=|$ndk_pin" "$script" || true)"
assert "install: it reaches dl.google.com only (and names the terms on developer.android.com)" test "$(grep -o 'https\?://[^/" ]*' "$script" | sort -u)" = "https://developer.android.com
https://dl.google.com"

# No automatic path may hold the flag or run the installer. The whole tree is searched (tracked files and new ones that
# are not ignored), not a list of known places: the hook wiring in .claude/settings.json, verify.sh and any script
# that setup.sh or CI calls count. The flag may stand in the installer, this test and the documentation only. The
# installer's name may also stand in a comment or in the text of a message (die, echo, printf) of another file, but no
# other line of it may have it (that would be a call, with a path of any shape). test-install-android.sh is the
# offline test, which ci.yml runs.
tree_files() { (cd "$repo" && { git ls-files -z --cached --others --exclude-standard 2>/dev/null || find . -type f -not -path './.git/*' -print0; }); }
files_naming() { tree_files | (cd "$repo" && xargs -0 -r grep -IlF -e "$1" 2>/dev/null) | sed 's|^\./||' || true; }
doc_file() { case "$1" in scripts/cloud/install-android.sh | scripts/ci/test-install-android.sh | README.md | CLAUDE.md | docs/* | .claude/agents/* | .claude/skills/* | .claude/agent-memory/*) return 0 ;; esac; return 1; }
holders=""
while IFS= read -r f; do
  [ -n "$f" ] && ! doc_file "$f" && holders="$holders [$f]"
done < <(files_naming "$accept")
assert "install: the flag stands in no automatic path (the whole tree is searched)${holders:+, found in:$holders}" test -z "$holders"
callers=""
while IFS= read -r f; do
  [ -n "$f" ] && ! doc_file "$f" || continue
  if [ -n "$(sed 's/test-install-android//g' "$repo/$f" | grep -F install-android | grep -Ev '^[[:space:]]*#|(die|echo|printf)[[:space:]]' || true)" ]; then callers="$callers [$f]"; fi
done < <(files_naming install-android)
assert "install: no other file calls the installer (setup.sh, a hook, settings.json, verify.sh, CI, the scripts)${callers:+, found in:$callers}" test -z "$callers"

if [ "$failures" -ne 0 ]; then
  echo "test-install-android: $failures case(s) failed" >&2
  exit 1
fi
echo "test-install-android: all cases passed"
