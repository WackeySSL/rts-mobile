#!/usr/bin/env bash
# Offline test of the native build scripts (P53b, ADR 0013 sections 8-10): seed-extension-list.sh on
# fixture trees, the NATIVE LIBRARY MISSING check of run-tests.sh, build-native.sh's exit codes and
# ELF checks against stub scons, git, g++, readelf and nm (and a stub NDK), and check-cpp-format.sh
# against a stub clang-format, and the order of verify.sh's native steps. Needs no Godot, SCons, compiler,
# NDK or network, and runs the scripts in a scrubbed environment on a stub uname (x86_64 unless a case
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

check() { # name, wanted exit code, wanted text in the output (may be empty); uses rc and out
  if [ "$rc" = "$2" ] && { [ -z "$3" ] || grep -Fq -- "$3" <<<"$out"; }; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (wanted exit $2 and '$3', got exit $rc: $(tail -n 1 <<<"$out"))" >&2
    failures=$((failures + 1))
  fi
}

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
for a in "$@"; do case "$a" in platform=* | target=* | arch=*) eval "${a%%=*}=${a#*=}" ;; esac; done
mkdir -p ../bin && echo stub >"../bin/libsim_kernels.${platform}.${target}.${arch}.so"
STUB
printf '#!/usr/bin/env bash\necho "g++ (stub) 13.3.0"\n' >"$root/bin/g++"
cat >"$root/bin/readelf" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  -h) echo "  Machine:   ${STUB_MACHINE:-Advanced Micro Devices X86-64}"; echo "  Type:   ${STUB_TYPE:-DYN (Shared object file)}" ;;
  -d) for lib in ${STUB_NEEDED:-libc.so.6}; do echo " 0x01 (NEEDED)   Shared library: [$lib]"; done ;;
esac
STUB
printf '#!/usr/bin/env bash\necho "0000000000001000 T ${STUB_SYMBOL:-sim_kernels_library_init}"\n' >"$root/bin/nm"
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
STUB
chmod +x "$root"/bin/*
ndk="$root/sdk/ndk/28.1.13356709"
tc="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
mkdir -p "$tc"
echo "Pkg.Revision = 28.1.13356709" >"$ndk/source.properties"
cp "$root/bin/g++" "$tc/clang++" && cp "$root/bin/readelf" "$tc/llvm-readelf" && cp "$root/bin/nm" "$tc/llvm-nm"

# tree NAME: scripts and the folders they expect, under $root/NAME. run NAME ENV... -- SCRIPT ARGS...
tree() {
  mkdir -p "$root/$1/scripts/ci" "$root/$1/native/sim_kernels" "$root/$1/native/godot-cpp" "$root/$1/addons/gdUnit4/bin"
  cp "$repo"/scripts/{seed-extension-list,build-native,run-tests}.sh "$root/$1/scripts/"
  cp "$repo/scripts/ci/check-cpp-format.sh" "$root/$1/scripts/ci/"
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
run bn bash scripts/build-native.sh --platform android --arch arm64
check "build: android without ANDROID_NDK_ROOT" 3 "ANDROID_NDK_ROOT is not set"
run bn ANDROID_NDK_ROOT="$root/sdk/ndk/27.0.0" bash scripts/build-native.sh --platform android --arch arm64
check "build: android with another NDK folder" 3 "must be <sdk>/ndk/28.1.13356709"
run bn ANDROID_NDK_ROOT="$ndk" STUB_MACHINE=AArch64 STUB_NEEDED="libc.so libm.so libc++_shared.so" bash scripts/build-native.sh --platform android
check "build: android, no --arch, system libraries and libc++_shared.so" 0 "needs libc.so libm.so libc++_shared.so"
check "build: android without --arch builds arm64" 0 "OK native/bin/libsim_kernels.android.template_debug.arm64.so"
run bn ANDROID_NDK_ROOT="$ndk" STUB_MACHINE=AArch64 STUB_NEEDED="libc.so libfoo.so" bash scripts/build-native.sh --platform android --arch arm64
check "build: android, a dependency the phone cannot resolve" 4 "needs libfoo.so"

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
