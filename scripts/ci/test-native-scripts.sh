#!/usr/bin/env bash
# Offline test of the native build scripts (P53b, ADR 0013 sections 8-10): seed-extension-list.sh on
# fixture trees, the NATIVE LIBRARY MISSING check of run-tests.sh, build-native.sh's exit codes and
# ELF checks against stub scons, git, g++, clang++, readelf and nm (and a stub NDK), check-cpp-format.sh
# against a stub clang-format, install-ndk.sh against a stub sdkmanager (P55a), check-native-tests.sh on
# fixtures, run-sanitizer-harness.sh against a stub Godot and g++ (P57), and the order of verify.sh's native steps. Needs no Godot, SCons, compiler, Android SDK, NDK or
# network, and runs the scripts in a scrubbed environment on a stub uname (x86_64 unless a case
# says otherwise), so the host changes no result. ci.yml runs it in the verify job.
# Usage: bash scripts/ci/test-native-scripts.sh      Exit: 0 all cases pass, 1 a case failed.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
root="$(mktemp -d)"
trap 'rm -rf "${root:?}"' EXIT
failures=0
# The scripts' override variables, set to junk: run() scrubs the environment, so none may reach a script.
export SCONS=/nonexistent CLANG_FORMAT=/nonexistent ANDROID_NDK_ROOT=/nonexistent ANDROID_HOME=/nonexistent RUN_TESTS_SKIP_IMPORT=1
sha="$(sed -n 's/^GODOT_CPP_SHA="\(.*\)"$/\1/p' "$repo/scripts/build-native.sh")"
# Michael's "NDK r29" (2026-10-13), kept here on its own: a change of NDK_VERSION in build-native.sh fails the cases below.
ndk_pin="29.0.14206865"

check() { # name, wanted exit code, wanted text in the output (may be empty); uses rc and out
  if [ "$rc" = "$2" ] && { [ -z "$3" ] || grep -Fq -- "$3" <<<"$out"; }; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (wanted exit $2 and '$3', got exit $rc: $(tail -n 1 <<<"$out"))" >&2
    failures=$((failures + 1))
  fi
}
assert() { if "${@:2}"; then echo "ok: $1"; else echo "FAIL: $1" >&2; failures=$((failures + 1)); fi; } # name, command...

# Stubs. scons writes the library that build-native.sh looks for; readelf and nm answer from STUB_*.
mkdir -p "$root/bin" "$root/tmp"
cat >"$root/bin/uname" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "-m" ]; then echo "${STUB_UNAME:-x86_64}"; else command -p uname "$@"; fi
STUB
cat >"$root/bin/git" <<STUB
#!/usr/bin/env bash
echo "\${STUB_SHA:-$sha}"
STUB
cat >"$root/bin/scons" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "--version" ]; then echo "	SCons: v${STUB_SCONS:-4.9.1}.0123abc, by stub"; exit 0; fi
echo "$*" >../../scons.args # the flags build-native.sh passed, in the tree root
echo "${ANDROID_HOME:-}" >../../scons.home # the SDK folder godot-cpp would read the NDK from
for a in "$@"; do case "$a" in platform=* | target=* | arch=*) eval "${a%%=*}=${a#*=}" ;; esac; done
mkdir -p ../bin && echo stub >"../bin/libsim_kernels.${platform}.${target}.${arch}.so"
STUB
# g++: its version, a runtime library that STUB_RUNTIME names as missing, and for the harness build (P57) the -o file,
# a script that acts as STUB_HARNESS says: it refuses a dump of a format other than 1 unless that is "accept".
cat >"$root/bin/g++" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  -dumpfullversion) echo 13.3.0; exit 0 ;;
  -print-file-name=*)
    lib="${1#-print-file-name=}"
    if [ "${STUB_RUNTIME:-}" = "$lib" ]; then echo "$lib"; else echo "/usr/lib/gcc/$lib"; fi
    exit 0 ;;
esac
case " $* " in
  *" -fsanitize=address,undefined "*)
    [ "${STUB_GXX:-}" != fail ] || { echo "g++: error: stub" >&2; exit 1; }
    prev=""
    for arg in "$@"; do
      if [ "$prev" = "-o" ]; then
        cat >"$arg" <<'HARNESS'
#!/usr/bin/env bash
mode="${STUB_HARNESS:-ok}"
[ "$mode" != find ] || { echo "sanitizer_harness: FINDING: stub" >&2; exit 1; }
format="$(od -An -tu4 -j4 -N4 "$(find "$1" -name 'state_*.bin' | sort | sed -n 1p)" | tr -d ' ')"
if [ "$format" != 1 ] && [ "$mode" != accept ]; then echo "sanitizer_harness: World.STATE_FORMAT $format is a layout this harness does not know" >&2; exit 2; fi
HARNESS
        chmod +x "$arg"
      fi
      prev="$arg"
    done ;;
esac
echo "g++ (stub) 13.3.0"
STUB
printf '#!/usr/bin/env bash\necho "${STUB_CLANGV:-Ubuntu clang version 18.1.3 (1ubuntu1)}"\n' | tee "$root/bin/clang" >"$root/bin/clang++"
cat >"$root/bin/readelf" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  -h) echo "  Machine:   ${STUB_MACHINE:-Advanced Micro Devices X86-64}"; echo "  Type:   ${STUB_TYPE:-DYN (Shared object file)}" ;;
  -d) for lib in ${STUB_NEEDED:-libc.so.6}; do echo " 0x01 (NEEDED)   Shared library: [$lib]"; done ;;
esac
STUB
cat >"$root/bin/nm" <<'STUB'
#!/usr/bin/env bash
case " $* " in
  *" --undefined-only "*) echo "                 U ${STUB_UNDEF:-__ubsan_handle_add_overflow}" ;;
  *) echo "0000000000001000 T ${STUB_SYMBOL:-sim_kernels_library_init}" ;;
esac
STUB
cat >"$root/bin/clang-format" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "--version" ]; then echo "clang-format version ${STUB_CF:-20.1.8}"; exit 0; fi
# Like the real tool, only --dry-run together with --Werror turns a file that needs formatting (BAD) into exit 1.
for flag in --dry-run --Werror; do case " $* " in *" $flag "*) ;; *) exit 0 ;; esac; done
for file in "$@"; do
  if [ -f "$file" ] && grep -q BAD "$file"; then echo "$file: error: code should be clang-formatted" >&2; exit 1; fi
done
STUB
cat >"$root/bin/godot" <<'STUB'
#!/usr/bin/env bash
# A headless editor start needs the seeded extension list when the project has a .gdextension; the real
# Godot 4.7.2 aborts with exit 134 without it (ADR 0013 section 9).
if [ -f native/sim_kernels.gdextension ] && ! grep -Fq res://native/sim_kernels.gdextension .godot/extension_list.cfg 2>/dev/null; then
  echo "stub godot: started without the seeded extension list" >&2
  exit 134
fi
# The dump step (godot ... -s <script> -- <out dir>, P57), as STUB_DUMP says it ends.
case " $* " in
  *" -s "*)
    for arg; do out="$arg"; done
    case "${STUB_DUMP:-ok}" in
      ok) printf 'RTSD\001\000\000\000' >"$out/state_00015.bin"; echo "dump_states: wrote 1 dumps to $out" ;;
      fail) echo "dump_states: FAIL no dump caught a waiting field" >&2; exit 1 ;;
      noline) printf 'RTSD\001\000\000\000' >"$out/state_00015.bin" ;;
      error) printf 'RTSD\001\000\000\000' >"$out/state_00015.bin"; echo "dump_states: wrote 1 dumps"; echo "SCRIPT ERROR: Parse Error" ;;
      empty) echo "dump_states: wrote 1 dumps" ;;
    esac ;;
esac
STUB
chmod +x "$root"/bin/*
ndk="$root/sdk/ndk/$ndk_pin"
tc="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
mkdir -p "$tc"
echo "Pkg.Revision = $ndk_pin" >"$ndk/source.properties"
cp "$root/bin/g++" "$tc/clang++" && cp "$root/bin/readelf" "$tc/llvm-readelf" && cp "$root/bin/nm" "$tc/llvm-nm"

# tree NAME: scripts and the folders they expect, under $root/NAME. run NAME ENV... -- SCRIPT ARGS...
tree() {
  mkdir -p "$root/$1/scripts/ci" "$root/$1/native/sim_kernels" "$root/$1/native/godot-cpp" "$root/$1/addons/gdUnit4/bin"
  cp "$repo"/scripts/{seed-extension-list,build-native,run-tests}.sh "$root/$1/scripts/"
  cp "$repo"/scripts/ci/{check-cpp-format,check-native-tests,install-ndk,run-sanitizer-harness}.sh "$root/$1/scripts/ci/"
  touch "$root/$1/addons/gdUnit4/bin/GdUnitCmdTool.gd"
}
run() {
  local name="$1"
  shift
  rc=0
  out="$(cd "$root/$name" && env -i PATH="$root/bin:$PATH" HOME="$root" TMPDIR="$root/tmp" GODOT="$root/bin/godot" "$@" 2>&1)" || rc=$?
}

# (1) seed-extension-list.sh: visible extensions only, replaced on every run, removed when none is left.
tree seed
mkdir -p "$root/seed/addons/x" "$root/seed/.hidden" "$root/seed/native/godot-cpp/test" "$root/seed/.godot"
touch "$root"/seed/native/{a,b,c,d,e,f}.gdextension "$root/seed/addons/x/x.gdextension" "$root/seed/.hidden/h.gdextension" \
  "$root/seed/native/godot-cpp/.gdignore" "$root/seed/native/godot-cpp/test/example.gdextension"
echo "res://stale/old.gdextension" >"$root/seed/.godot/extension_list.cfg"
run seed bash scripts/seed-extension-list.sh
check "seed: runs" 0 ""
want="$(echo res://addons/x/x.gdextension; printf 'res://native/%s.gdextension\n' a b c d e f)"
if [ "$(cat "$root/seed/.godot/extension_list.cfg")" = "$want" ]; then
  echo "ok: seed: lists the visible extensions only, sorted, and drops the stale entry"
else
  echo "FAIL: seed: wrong list: $(cat "$root/seed/.godot/extension_list.cfg")" >&2
  failures=$((failures + 1))
fi
cp "$root/seed/.godot/extension_list.cfg" "$root/first.cfg"
run seed bash scripts/seed-extension-list.sh
cmp -s "$root/first.cfg" "$root/seed/.godot/extension_list.cfg" && echo "ok: seed: idempotent" || { echo "FAIL: seed: second run changed the list" >&2; failures=$((failures + 1)); }
rm "$root"/seed/native/{a,b,c,d,e,f}.gdextension "$root/seed/addons/x/x.gdextension"
run seed bash scripts/seed-extension-list.sh
if [ ! -e "$root/seed/.godot/extension_list.cfg" ]; then echo "ok: seed: no extension, no list"; else echo "FAIL: seed: list kept" >&2; failures=$((failures + 1)); fi

# (2) run-tests.sh stops with exit 3 and the fixed message before Godot starts, without the library.
tree rt
run rt bash scripts/run-tests.sh
check "run-tests: no .gdextension" 3 "NATIVE LIBRARY MISSING: run bash scripts/build-native.sh first"
printf 'linux.debug.x86_64 = "res://native/bin/lib.so"\nlinux.debug.arm64 = "res://native/bin/lib.so"\n' >"$root/rt/native/sim_kernels.gdextension"
run rt bash scripts/run-tests.sh
check "run-tests: .gdextension without its library" 3 "NATIVE LIBRARY MISSING"
mkdir -p "$root/rt/native/bin" && echo lib >"$root/rt/native/bin/lib.so"
run rt bash scripts/run-tests.sh
check "run-tests: seeds the extension list, then goes on (no results.xml, exit 1)" 1 "no test cases ran"

# (3) build-native.sh: flags, tool versions, the SHA, the ELF checks and the generated .gdextension.
tree bn
run bn bash scripts/build-native.sh --bogus
check "build: unknown flag" 2 "unknown argument"
run bn bash scripts/build-native.sh --platform android --arch x86_64
check "build: android is arm64 only" 2 "arm64 only"
run bn STUB_SCONS=4.9.0 bash scripts/build-native.sh
check "build: SCons 4.9.0" 3 "needs scons 4.9.1"
run bn STUB_SHA=0000 bash scripts/build-native.sh
check "build: godot-cpp at another commit" 4 "not the pinned"
run bn bash scripts/build-native.sh
check "build: linux, stubs" 0 "ELF ok"
assert "build: the defaults pass neither use_llvm, optimize nor sanitize" test "$(grep -Ec 'use_llvm|optimize|sanitize' "$root/bn/scons.args")" = 0
grep -Fq 'android.release.arm64 = "res://native/bin/libsim_kernels.android.template_release.arm64.so"' "$root/bn/native/sim_kernels.gdextension" &&
  grep -Fq 'entry_symbol = "sim_kernels_library_init"' "$root/bn/native/sim_kernels.gdextension" &&
  echo "ok: build: the generated .gdextension names every platform's library" || { echo "FAIL: build: .gdextension" >&2; failures=$((failures + 1)); }
run bn STUB_UNAME=aarch64 STUB_MACHINE=AArch64 bash scripts/build-native.sh
check "build: linux on an arm64 host, no --arch" 0 "OK native/bin/libsim_kernels.linux.template_debug.arm64.so"
run bn STUB_UNAME=aarch64 bash scripts/build-native.sh --arch x86_64
check "build: linux on an arm64 host, --arch x86_64" 2 "host architecture only (arm64)"
run bn STUB_MACHINE="AArch64" bash scripts/build-native.sh
check "build: wrong machine" 4 "is not a 'Advanced Micro Devices X86-64' ELF file"
run bn STUB_TYPE="EXEC (Executable file)" bash scripts/build-native.sh
check "build: not a shared object" 4 "not a shared object"
run bn STUB_SYMBOL=other_init bash scripts/build-native.sh
check "build: entry symbol missing" 4 "does not export the entry symbol"
run bn bash scripts/build-native.sh --compiler msvc
check "build: unknown compiler" 2 "--compiler must be gcc or clang"
run bn bash scripts/build-native.sh --optimize size
check "build: unknown optimize" 2 "--optimize must be speed"
run bn bash scripts/build-native.sh --platform android --compiler gcc
check "build: android takes clang only" 2 "NDK's clang"
run bn bash scripts/build-native.sh --compiler clang --optimize speed
check "build: clang at speed" 0 "(clang18.1.3, optimize=speed)"
assert "build: clang at speed passes use_llvm=yes and optimize=speed" grep -Eq 'use_llvm=yes.*optimize=speed' "$root/bn/scons.args"
run bn STUB_CLANGV=nonsense bash scripts/build-native.sh --compiler clang
check "build: clang without a readable version" 3 "clang++ reports no version"
# --sanitize undefined (P57): g++ on Linux only, a library that needs the shared libubsan and calls its handlers.
run bn bash scripts/build-native.sh --sanitize address
check "build: unknown sanitize" 2 "--sanitize must be undefined"
run bn bash scripts/build-native.sh --sanitize undefined --compiler clang
check "build: sanitize takes g++ only" 2 "builds with g++"
run bn bash scripts/build-native.sh --sanitize undefined --platform android
check "build: sanitize is for the Linux library only" 2 "Linux library only"
run bn STUB_RUNTIME=libubsan.so bash scripts/build-native.sh --sanitize undefined
check "build: sanitize without libubsan" 3 "g++ has no libubsan"
run bn bash scripts/build-native.sh --sanitize undefined
check "build: sanitized library without the shared libubsan" 4 "does not need the shared libubsan"
run bn STUB_NEEDED="libc.so.6 libubsan.so.1" STUB_UNDEF=memcpy bash scripts/build-native.sh --sanitize undefined
check "build: sanitized library that calls no handler" 4 "was not instrumented"
run bn STUB_NEEDED="libc.so.6 libubsan.so.1" bash scripts/build-native.sh --sanitize undefined
check "build: sanitize undefined" 0 "(instrumented: undefined)"
assert "build: sanitize undefined passes sanitize=undefined to SCons" grep -Fq "sanitize=undefined" "$root/bn/scons.args"
# --print-cache-key: ci.yml writes its stdout to $GITHUB_OUTPUT, so stdout holds the key alone (one line, the
# info line goes to stderr), printed before the godot-cpp fetch (the cache restores it) and before the build.
# The tree has no native/godot-cpp: a fetch would create it, and the build would write scons.args.
tree bk
rmdir "$root/bk/native/godot-cpp"
key_is() { # name, wanted key, ENV... -- script args: exit 0 and exactly the key on stdout
  local name="$1" want="$2"
  shift 2
  rc=0
  key_out="$(cd "$root/bk" && env -i PATH="$root/bin:$PATH" HOME="$root" TMPDIR="$root/tmp" "$@" 2>/dev/null)" || rc=$?
  assert "$name" test "$rc:$key_out" = "0:$want"
}
key_is "build: cache key (platform, arch, target, compiler version, godot-cpp SHA, SCons) alone on stdout" \
  "native-linux-x86_64-template_debug-gcc13.3.0-godotcpp-$sha-scons4.9.1" bash scripts/build-native.sh --print-cache-key
key_is "build: cache key, sanitize undefined" \
  "native-linux-x86_64-template_debug-gcc13.3.0-sanitize-undefined-godotcpp-$sha-scons4.9.1" \
  bash scripts/build-native.sh --sanitize undefined --print-cache-key
key_is "build: cache key, clang at speed, release" \
  "native-linux-x86_64-template_release-clang18.1.3-speed-godotcpp-$sha-scons4.9.1" \
  bash scripts/build-native.sh --compiler clang --optimize speed --target template_release --print-cache-key
key_is "build: cache key, android (the NDK installed first)" \
  "native-android-arm64-template_debug-ndk$ndk_pin-godotcpp-$sha-scons4.9.1" \
  ANDROID_NDK_ROOT="$ndk" bash scripts/build-native.sh --platform android --print-cache-key
key_is "build: cache key, android arm64 template_release (ci.yml's third key)" \
  "native-android-arm64-template_release-ndk$ndk_pin-godotcpp-$sha-scons4.9.1" \
  ANDROID_NDK_ROOT="$ndk" bash scripts/build-native.sh --platform android --arch arm64 --target template_release --print-cache-key
assert "build: --print-cache-key fetches no godot-cpp" test ! -e "$root/bk/native/godot-cpp"
assert "build: --print-cache-key builds nothing" test ! -e "$root/bk/scons.args"
run bk bash scripts/build-native.sh --platform android --print-cache-key
check "build: cache key, android without the NDK installed" 3 "ANDROID_NDK_ROOT is not set"
run bn bash scripts/build-native.sh --platform android --arch arm64
check "build: android without ANDROID_NDK_ROOT" 3 "ANDROID_NDK_ROOT is not set"
run bn ANDROID_NDK_ROOT="$root/sdk/ndk/27.0.0" bash scripts/build-native.sh --platform android --arch arm64
check "build: android with another NDK folder" 3 "must be <sdk>/ndk/$ndk_pin"
run bn ANDROID_NDK_ROOT="$ndk" STUB_MACHINE=AArch64 STUB_NEEDED="libc.so libm.so libc++_shared.so" bash scripts/build-native.sh --platform android
check "build: android, no --arch, system libraries and libc++_shared.so" 0 "needs libc.so libm.so libc++_shared.so"
check "build: android without --arch builds arm64" 0 "OK native/bin/libsim_kernels.android.template_debug.arm64.so"
assert "build: android passes the pinned ndk_version to SCons" grep -Fq "ndk_version=$ndk_pin" "$root/bn/scons.args"
assert "build: android gives SCons the NDK's SDK folder as ANDROID_HOME" test "$(cat "$root/bn/scons.home")" = "$root/sdk"
run bn ANDROID_NDK_ROOT="$ndk" STUB_MACHINE=AArch64 STUB_NEEDED="libc.so libm.so libc++_shared.so" bash scripts/build-native.sh --platform android --arch arm64 --target template_release
check "build: android arm64 template_release" 0 "OK native/bin/libsim_kernels.android.template_release.arm64.so"
run bn ANDROID_NDK_ROOT="$ndk" STUB_MACHINE=AArch64 STUB_NEEDED="libc.so libfoo.so" bash scripts/build-native.sh --platform android --arch arm64
check "build: android, a dependency the phone cannot resolve" 4 "needs libfoo.so"

# (3b) install-ndk.sh (P55a): the version is the NDK_VERSION line of build-native.sh (no second pin), sdkmanager
# installs it into <sdk>/ndk/<version>, a second run calls nothing, and a wrong result is exit 4. The stub makes
# what sdkmanager makes; STUB_SDKM=fail exits 1, STUB_SDKM_REVISION installs another revision, STUB_SDKM_TOOLS
# only those tools and STUB_SDKM_STDIN=1 fails the call when the script answered a licence prompt on stdin. $root/tools holds the few tools the script and the stub use, so that no sdkmanager of the host is on PATH.
tools="clang++ llvm-readelf llvm-nm" # what sdkmanager's stub makes, and what install-ndk.sh checks
mkdir -p "$root/sdkm" "$root/tools"
cat >"$root/sdkm/sdkmanager" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>sdkmanager.args # in the tree root, one line per call
if [ -n "${STUB_SDKM_STDIN:-}" ]; then # a licence answer on stdin would be an acceptance
  IFS= read -r answer || answer=
  [ "$answer" != y ] || { echo "stub sdkmanager: a licence was accepted on stdin" >&2; exit 1; }
fi
[ "${STUB_SDKM:-}" != fail ] || { echo "stub sdkmanager: License for package NDK not accepted" >&2; exit 1; }
for a in "$@"; do case "$a" in --sdk_root=*) dir="${a#*=}" ;; ndk\;*) version="${a#ndk;}" ;; esac; done
bin="$dir/ndk/$version/toolchains/llvm/prebuilt/linux-x86_64/bin"
mkdir -p "$bin" && echo "Pkg.Revision = ${STUB_SDKM_REVISION:-$version}" >"$dir/ndk/$version/source.properties"
for tool in ${STUB_SDKM_TOOLS-clang++ llvm-readelf llvm-nm}; do printf '#!/bin/sh\n' >"$bin/$tool" && chmod +x "$bin/$tool"; done
STUB
chmod +x "$root/sdkm/sdkmanager"
for tool in bash sed grep head dirname mkdir chmod; do ln -s "$(command -v "$tool")" "$root/tools/$tool"; done
new_sdk() { sdk="$root/$1"; mkdir -p "$sdk"; } # name: a fresh, empty SDK folder $root/name
tree in
run in bash scripts/ci/install-ndk.sh --help
check "ndk: an argument" 2 "takes no arguments"
run in bash scripts/ci/install-ndk.sh
check "ndk: no SDK folder" 3 "ANDROID_HOME is not set"
run in ANDROID_HOME="$root/nowhere" bash scripts/ci/install-ndk.sh
check "ndk: the SDK folder does not exist" 3 "does not exist"
new_sdk isdk0
run in PATH="$root/tools" ANDROID_HOME="$sdk" bash scripts/ci/install-ndk.sh
check "ndk: no sdkmanager in the SDK or on PATH" 3 "sdkmanager is missing"
run in SDKMANAGER="$root/none" ANDROID_HOME="$sdk" bash scripts/ci/install-ndk.sh
check "ndk: SDKMANAGER names a missing binary" 3 "sdkmanager is missing"
tree in2
grep -v '^NDK_VERSION=' "$repo/scripts/build-native.sh" >"$root/in2/scripts/build-native.sh"
run in2 ANDROID_HOME="$sdk" bash scripts/ci/install-ndk.sh
check "ndk: build-native.sh without its NDK_VERSION line" 2 "needs exactly one NDK_VERSION"
{ cat "$repo/scripts/build-native.sh"; echo 'NDK_VERSION="1.2.3"'; } >"$root/in2/scripts/build-native.sh"
run in2 ANDROID_HOME="$sdk" bash scripts/ci/install-ndk.sh
check "ndk: build-native.sh with two NDK_VERSION lines" 2 "(it has 2)"
new_sdk isdk1
mkdir -p "$sdk/cmdline-tools/latest/bin" && cp "$root/sdkm/sdkmanager" "$sdk/cmdline-tools/latest/bin/"
: >"$root/github.env"
run in STUB_SDKM_STDIN=1 GITHUB_ENV="$root/github.env" ANDROID_HOME="$sdk/" bash scripts/ci/install-ndk.sh <<<y
check "ndk: installs the pinned NDK through the SDK's own sdkmanager, accepting no licence" 0 "install-ndk: OK $sdk/ndk/$ndk_pin"
assert "ndk: sdkmanager got the SDK folder and the pinned package" test "$(cat "$root/in/sdkmanager.args")" = "--sdk_root=$sdk ndk;$ndk_pin"
assert "ndk: ANDROID_NDK_ROOT goes to GITHUB_ENV" test "$(cat "$root/github.env")" = "ANDROID_NDK_ROOT=$sdk/ndk/$ndk_pin"
run in ANDROID_NDK_ROOT="$sdk/ndk/$ndk_pin" bash scripts/build-native.sh --platform android --print-cache-key
check "ndk: build-native.sh accepts what was installed" 0 "-ndk$ndk_pin-godotcpp-"
: >"$root/github.env2"
run in PATH="$root/tools" GITHUB_ENV="$root/github.env2" ANDROID_HOME="$sdk" bash scripts/ci/install-ndk.sh
check "ndk: a second run finds the NDK" 0 "installed already"
assert "ndk: a second run does not call sdkmanager" test "$(wc -l <"$root/in/sdkmanager.args" | tr -d ' ')" = 1
assert "ndk: a second run still sets ANDROID_NDK_ROOT (the image's own is another NDK)" test "$(cat "$root/github.env2")" = "ANDROID_NDK_ROOT=$sdk/ndk/$ndk_pin"
new_sdk isdk2
run in PATH="$root/sdkm:$root/tools" ANDROID_SDK_ROOT="$sdk" bash scripts/ci/install-ndk.sh
check "ndk: sdkmanager on PATH, SDK folder from ANDROID_SDK_ROOT" 0 "install-ndk: OK $sdk/ndk/$ndk_pin"
new_sdk isdk3
sed 's/^NDK_VERSION=.*/NDK_VERSION="30.1.2"/' "$repo/scripts/build-native.sh" >"$root/in2/scripts/build-native.sh"
run in2 SDKMANAGER="$root/sdkm/sdkmanager" ANDROID_HOME="$sdk" bash scripts/ci/install-ndk.sh
check "ndk: the version is build-native.sh's NDK_VERSION line, installed via SDKMANAGER" 0 "install-ndk: OK $sdk/ndk/30.1.2"
assert "ndk: sdkmanager was asked for that version" test "$(cat "$root/in2/sdkmanager.args")" = "--sdk_root=$sdk ndk;30.1.2"
new_sdk isdk4
run in STUB_SDKM=fail SDKMANAGER="$root/sdkm/sdkmanager" ANDROID_HOME="$sdk" bash scripts/ci/install-ndk.sh
check "ndk: sdkmanager fails" 4 "sdkmanager failed with exit code 1"
new_sdk isdk5
run in STUB_SDKM_REVISION=28.1.13356709 SDKMANAGER="$root/sdkm/sdkmanager" ANDROID_HOME="$sdk" bash scripts/ci/install-ndk.sh
check "ndk: sdkmanager leaves another revision" 4 "did not leave the pinned NDK $ndk_pin: '$sdk/ndk/$ndk_pin' is '28.1.13356709'"
for missing in clang++ llvm-readelf llvm-nm; do
  new_sdk "isdk6-${missing//+/p}"
  run in STUB_SDKM_TOOLS="${tools/$missing/}" SDKMANAGER="$root/sdkm/sdkmanager" ANDROID_HOME="$sdk" bash scripts/ci/install-ndk.sh
  check "ndk: an incomplete toolchain, no $missing" 4 "no $sdk/ndk/$ndk_pin/toolchains/llvm/prebuilt/linux-x86_64/bin/$missing"
done
# A folder of the pinned name that holds another revision (a stale or half-made install) is no NDK: sdkmanager runs.
tree in3
new_sdk isdk7
mkdir -p "$sdk/ndk/$ndk_pin" && echo "Pkg.Revision = 28.1.13356709" >"$sdk/ndk/$ndk_pin/source.properties"
run in3 SDKMANAGER="$root/sdkm/sdkmanager" ANDROID_HOME="$sdk" bash scripts/ci/install-ndk.sh
check "ndk: a stale folder of the pinned name is installed over" 0 "install-ndk: OK $sdk/ndk/$ndk_pin"
assert "ndk: sdkmanager ran once for the stale folder" test "$(cat "$root/in3/sdkmanager.args" 2>/dev/null)" = "--sdk_root=$sdk ndk;$ndk_pin"

# --check (P55b) installs nothing: it answers whether the pinned NDK is complete, and it calls no sdkmanager even when one
# is there and the NDK is not. The installer of cloud sessions asks it before sdkmanager, which records the SDK licence, may run.
tree in4
run in4 bash scripts/ci/install-ndk.sh --bogus
check "ndk: an argument but --check" 2 "takes no arguments but --check, got '--bogus'"
run in4 bash scripts/ci/install-ndk.sh --check
check "ndk --check: no SDK folder is set" 3 "ANDROID_HOME is not set"
new_sdk isdk8
mkdir -p "$sdk/cmdline-tools/latest/bin" && cp "$root/sdkm/sdkmanager" "$sdk/cmdline-tools/latest/bin/"
run in4 ANDROID_HOME="$sdk" bash scripts/ci/install-ndk.sh --check
check "ndk --check: an SDK without the NDK" 1 "Android NDK $ndk_pin is not installed"
assert "ndk --check: ... calls no sdkmanager and installs nothing" test ! -e "$root/in4/sdkmanager.args" -a ! -e "$sdk/ndk"
run in4 ANDROID_HOME="$root/nowhere" bash scripts/ci/install-ndk.sh --check
check "ndk --check: an SDK folder that does not exist" 1 "is not installed"
mkdir -p "$sdk/ndk/$ndk_pin" && echo "Pkg.Revision = 28.1.13356709" >"$sdk/ndk/$ndk_pin/source.properties"
run in4 ANDROID_HOME="$sdk" bash scripts/ci/install-ndk.sh --check
check "ndk --check: a folder of the pinned name with another revision" 1 "'28.1.13356709'"
for missing in clang++ llvm-readelf llvm-nm; do
  new_sdk "isdk9-${missing//+/p}"
  run in STUB_SDKM_TOOLS="${tools/$missing/}" SDKMANAGER="$root/sdkm/sdkmanager" ANDROID_HOME="$sdk" bash scripts/ci/install-ndk.sh
  run in4 ANDROID_HOME="$sdk" bash scripts/ci/install-ndk.sh --check
  check "ndk --check: an incomplete toolchain, no $missing" 1 "no $sdk/ndk/$ndk_pin/toolchains/llvm/prebuilt/linux-x86_64/bin/$missing"
done
: >"$root/github.env3"
run in4 GITHUB_ENV="$root/github.env3" ANDROID_HOME="$root/sdk" bash scripts/ci/install-ndk.sh --check
check "ndk --check: the NDK is installed" 0 "installed already"
assert "ndk --check: ... it still sets ANDROID_NDK_ROOT" test "$(cat "$root/github.env3")" = "ANDROID_NDK_ROOT=$root/sdk/ndk/$ndk_pin"
: >"$root/github.env4"
run in4 GITHUB_ENV="$root/github.env4" ANDROID_HOME="$sdk" bash scripts/ci/install-ndk.sh --check
assert "ndk --check: ... and it sets nothing when the NDK is missing" test ! -s "$root/github.env4"

# (4) check-cpp-format.sh: the pinned clang-format, then every .cpp, .h and .hpp below native/sim_kernels,
# in every folder (and nothing else). The stub fails only a BAD file, and only on --dry-run with --Werror.
tree cf
src="$root/cf/native/sim_kernels"
mkdir -p "$src/src/bind" "$src/src/core"
echo "int x;" | tee "$src/src/bind/a.cpp" "$src/src/bind/b.h" >"$src/src/core/c.hpp"
echo "BAD" >"$src/SConstruct"
run cf bash scripts/ci/check-cpp-format.sh
check "format: pinned version, three C++ files formatted, other files ignored" 0 "3 files formatted"
run cf STUB_CF=18.1.3 bash scripts/ci/check-cpp-format.sh
check "format: another clang-format version" 3 "needs clang-format 20.1.8"
run cf CLANG_FORMAT="$root/none" bash scripts/ci/check-cpp-format.sh
check "format: clang-format missing" 3 "clang-format is missing"
for file in bind/a.cpp bind/b.h core/c.hpp; do
  echo "int BAD;" >"$src/src/$file"
  run cf bash scripts/ci/check-cpp-format.sh
  check "format: $file needs formatting" 1 "$file: error: code should be clang-formatted"
  echo "int x;" >"$src/src/$file"
done
rm -r "$src/src"
run cf bash scripts/ci/check-cpp-format.sh
check "format: no C++ files" 1 "no C++ files"

# (4b) check-native-tests.sh (P55): suites are discovered, not listed. `suite NAME CASES [COUNTER set to 1]
# [CHILD TAG of the first case] [PACKAGE]` writes a gdUnit4 suite into the fixture results.xml; the package
# is the suite file's folder, which for test_b is sub/ and for test_golden_hashes tests/perf.
suite() {
  local i c='failures="0" errors="0" skipped="0"' pkg=tests/sim/native
  case "$1" in test_b) pkg=$pkg/sub ;; test_golden_hashes) pkg=tests/perf ;; esac
  printf '<testsuite name="%s" package="%s" %s>\n' "$1" "${5:-$pkg}" "${c/${3:-x}=\"0\"/${3:-x}=\"1\"}"
  for ((i = 1; i <= $2; i++)); do printf '<testcase name="c%s">%s</testcase>\n' "$i" "$([ "$i" = 1 ] && [ -n "${4:-}" ] && echo "<$4/>")"; done
  echo '</testsuite>'
}
xml() { { echo '<testsuites>'; cat; echo '</testsuites>'; } >"$root/nt/r.xml"; }
nt() { run nt bash scripts/ci/check-native-tests.sh "$@" "$root/nt/r.xml"; }
tree nt
nsrc="$root/nt/tests/sim/native"
mkdir -p "$nsrc/sub" "$nsrc/sanitizer"
touch "$nsrc/test_a.gd" "$nsrc/test_a.gd.uid" "$nsrc/helper.gd" "$nsrc/sub/test_b.gd" "$nsrc/sanitizer/test_dump.gd"
{ suite test_a 2; suite test_b 1; } | xml
nt
check "natives: both discovered suites ran (the sanitizer one is not required)" 0 "OK 2 suites"
run nt bash scripts/ci/check-native-tests.sh --list
assert "natives: --list names the two suites, not the sanitizer's, a helper or a .uid" test "$out" = "tests/sim/native/sub/test_b.gd"$'\n'"tests/sim/native/test_a.gd"
mkdir -p "$root/nt/reports/gdunit/report_1"
cp "$root/nt/r.xml" "$root/nt/reports/gdunit/report_1/results.xml"
run nt bash scripts/ci/check-native-tests.sh
check "natives: results.xml defaults to reports/gdunit/report_1 (run-tests.sh writes it there)" 0 "OK 2 suites"
rm -r "$root/nt/reports"
suite test_a 2 | xml
nt
check "natives: a discovered suite missing from results.xml" 1 "test_b: found 0 times"
{ suite test_a 2; suite test_b 1 "" "" tests/sim/native; } | xml
nt
check "natives: a suite found only in another folder is not that suite" 1 "test_b: found 0 times in results.xml in tests/sim/native/sub"
{ suite test_a 2; suite test_b 1; suite test_a 1 "" "" tests/sim; } | xml
nt
check "natives: a suite elsewhere with the same base name is not a second one" 0 "OK 2 suites"
{ suite test_a 2; suite test_b 0; } | xml
nt
check "natives: a suite with zero cases" 1 "test_b: no cases ran"
{ suite test_a 2; suite test_b 1; suite test_b 1; } | xml
nt
check "natives: a suite twice in results.xml" 1 "test_b: found 2 times"
touch "$nsrc/sub/test_a.gd"
nt
check "natives: two suite files with one base name" 1 "share the base name test_a"
rm "$nsrc/sub/test_a.gd"
for tag in failure error skipped; do
  { suite test_a 2 "" "$tag"; suite test_b 1; } | xml
  nt
  check "natives: a case reporting $tag" 1 "test_a: case c1 failed, errored or was skipped"
done
for counter in failures errors skipped; do
  { suite test_a 2 "$counter"; suite test_b 1; } | xml
  nt
  check "natives: a suite reporting $counter=1" 1 "test_a: $counter=1"
done
{ suite test_a 2; suite test_b 1; suite test_golden_hashes 3; } | xml
nt --require test_golden_hashes
check "natives: --require a suite elsewhere that ran" 0 "OK 3 suites"
suite test_a 2 | xml
nt --require test_golden_hashes
check "natives: --require a suite that is missing, and test_b too" 1 "test_golden_hashes: found 0 times"
nt --require ../x
check "natives: --require takes a suite name" 2 "--require needs a suite name"
echo "not xml" >"$root/nt/r.xml"
nt
check "natives: results.xml not XML" 4 "not readable XML"
run nt PYTHON="$root/none" bash scripts/ci/check-native-tests.sh "$root/nt/r.xml"
check "natives: python3 missing" 3 "is missing"
rm "$root/nt/r.xml"
nt
check "natives: results.xml missing" 4 "is missing or empty"
rm -r "$nsrc/test_a.gd" "$nsrc/sub"
nt
check "natives: no suites and no kernel_list.h (before P54), no results.xml needed" 0 "no native suites yet (before P54)"
nt --require test_golden_hashes
check "natives: no suites but a --require suite needs a results.xml" 4 "is missing or empty"
mkdir -p "$root/nt/native/sim_kernels/src/bind" && touch "$root/nt/native/sim_kernels/src/bind/kernel_list.h"
nt
check "natives: no suites with kernel_list.h (the floor)" 1 "kernel_list.h exists"
nt --require test_golden_hashes
check "natives: the floor holds with a --require suite too" 1 "kernel_list.h exists"

# (4b) run-sanitizer-harness.sh (P57) against a stub Godot, whose dump step ends as STUB_DUMP says, and a stub g++,
# whose harness acts as STUB_HARNESS says.
tree sh
run sh bash scripts/ci/run-sanitizer-harness.sh
check "harness: no work folder" 2 "usage"
run sh GODOT=/nonexistent bash scripts/ci/run-sanitizer-harness.sh "$root/sh/work"
check "harness: Godot missing" 3 "Godot is missing"
run sh STUB_RUNTIME=libasan.so bash scripts/ci/run-sanitizer-harness.sh "$root/sh/work"
check "harness: g++ without libasan" 3 "g++ has no libasan.so"
run sh bash scripts/ci/run-sanitizer-harness.sh "$root/sh/work"
check "harness: dumps, builds, runs, and sees the unknown format refused" 0 "run-sanitizer-harness: OK"
for case_ in "STUB_DUMP=fail:4:the dump step exited with 1" "STUB_DUMP=noline:4:did not report" "STUB_DUMP=error:4:Godot logged an error" \
  "STUB_DUMP=empty:4:wrote no state_*.bin" "STUB_GXX=fail:4:the harness did not build" "STUB_HARNESS=find:1:the harness failed with exit code 1" \
  "STUB_HARNESS=accept:1:took a dump of an unknown"; do
  run sh "${case_%%:*}" bash scripts/ci/run-sanitizer-harness.sh "$root/sh/work"
  want="${case_#*:}"
  check "harness: ${case_%%:*}" "${want%%:*}" "${want#*:}"
done

# (5) verify.sh builds first, seeds before the import, tests after it and checks the C++ format last.
prev=0
order=ok
for step in scripts/build-native.sh scripts/seed-extension-list.sh --import scripts/run-tests.sh scripts/ci/check-cpp-format.sh; do
  at="$(awk -v s="$step" 'index($0, "run_step") && index($0, s) { print NR; exit }' "$repo/scripts/verify.sh")"
  if [ -z "$at" ] || [ "$at" -le "$prev" ]; then order="wrong at $step"; fi
  prev="${at:-$prev}"
done
if [ "$order" = ok ]; then echo "ok: verify.sh runs build, seed, import, tests, C++ format in that order"; else echo "FAIL: verify.sh step order: $order" >&2; failures=$((failures + 1)); fi

if [ "$failures" -ne 0 ]; then
  echo "test-native-scripts: $failures case(s) failed" >&2
  exit 1
fi
echo "test-native-scripts: all cases passed"
