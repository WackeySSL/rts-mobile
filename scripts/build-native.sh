#!/usr/bin/env bash
# Builds the native sim kernels (native/sim_kernels, ADR 0013) against godot-cpp, fetched at a
# pinned commit into the git-ignored native/godot-cpp. The library goes to the git-ignored
# native/bin/, and so does the native/sim_kernels.gdextension that names it: generated, so that a
# checkout without a build is a plain GDScript project (ADR 0013 section 9). verify.sh runs it first.
# Usage: bash scripts/build-native.sh [--platform linux|android] [--target template_debug|template_release]
#                                     [--arch x86_64|arm64] [--compiler gcc|clang] [--optimize speed]
#                                     [--sanitize undefined] [--print-cache-key]
#   --arch defaults to the one value a platform accepts: linux builds the host architecture only,
#   android arm64 only (CI, or a cloud session after scripts/cloud/install-android.sh; scripts/ci/install-ndk.sh
#   installs the NDK_VERSION below).
#   --compiler clang adds use_llvm=yes (the native-clang CI job; the default gcc is the host g++, and android
#   always uses the NDK's clang). --optimize speed adds optimize=speed (-O3; template_debug is -O2 without it).
#   --sanitize undefined (the CI sanitizer job, ADR 0013 section 10) builds our sources with g++ -O1 -fsanitize=undefined
#   -fno-sanitize-recover=all and without -fwrapv, so a signed overflow aborts; the library links the shared libubsan and
#   keeps its name, so it replaces a plain build of the same platform, target and arch (Linux and g++ only). It fixes the
#   optimisation at -O1, so it refuses --optimize.
#   --print-cache-key prints the CI cache key (ADR 0013 section 8: platform, arch, target, compiler version,
#   optimize, sanitize, godot-cpp SHA, SCons version) alone on stdout and exits 0 before the fetch and the build.
#   It checks the toolchain first, so android needs the NDK installed already: the key serves the
#   godot-cpp and SCons cache after install-ndk.sh, never a cache of the NDK itself (key that on NDK_VERSION).
# Env:   SCONS=<binary> (default: scons; must be 4.9.1), SCONS_CACHE=<folder> (godot-cpp's CacheDir),
#        ANDROID_NDK_ROOT=<NDK folder> (android; must be <sdk>/ndk/29.0.14206865, the layout that
#        sdkmanager makes and that godot-cpp's tools/android.py reads as $ANDROID_HOME/ndk/<version>).
# Needs: git and network access to github.com (first run only), scons 4.9.1, g++ and binutils
#        (readelf, nm) for linux (godot-cpp's SConstruct never reads CXX; use_llvm=yes picks clang),
#        and for --sanitize undefined g++'s libubsan.
#        Flags: native/sim_kernels/SConstruct.
# Exit:  0 ok
#        2 bad flag or an impossible platform/arch/compiler combination
#        3 tool missing (git, scons 4.9.1, g++ or clang, binutils, libubsan, or the NDK and its toolchain), or an NDK
#          of another version than the pinned one
#        4 godot-cpp fetch or SHA check failed, or the build failed, produced no library, or the
#          library fails the ELF check (machine, shared object, entry symbol, and on Android only
#          system libraries or Godot's libc++_shared.so as dependencies; a sanitized library must need the
#          shared libubsan, call a signed-overflow handler (no -fwrapv) and call fatal handlers only)
# Success prints "build-native: OK <library> (<bytes> bytes)". Bash 3.2 compatible.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$(pwd -P)"

# godot-4.5-stable, the newest godot-cpp tag; there is no 4.6 or 4.7 tag. GDExtension is forward
# compatible, so the library (compatibility_minimum = "4.5") loads in Godot 4.7.2.
GODOT_CPP_URL="https://github.com/godotengine/godot-cpp.git"
GODOT_CPP_TAG="godot-4.5-stable"
GODOT_CPP_SHA="e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77"
SCONS_VERSION="4.9.1"
# NDK r29, Michael's answer of 2026-10-13: the NDK Godot 4.7.2's Android template is built with, whose
# libc++_shared.so our library links (ADR 0013 section 8's status note). godot-cpp godot-4.5-stable keeps its
# own default (tools/android.py, "ndk_version", 28.1.13356709); the ndk_version flag below overrides it.
# scripts/ci/install-ndk.sh reads this line, keep its shape; the stub NDK of scripts/ci/test-native-scripts.sh
# follows it.
NDK_VERSION="29.0.14206865"
ENTRY_SYMBOL="sim_kernels_library_init"
SCONS="${SCONS:-scons}"
GODOT_CPP_DIR="$ROOT/native/godot-cpp"

die() {
  local code="$1"
  shift
  echo "build-native: $*" >&2
  exit "$code"
}

platform="linux"
target="template_debug"
arch=""
compiler=""
optimize=""
sanitize=""
print_key=0
while [ $# -gt 0 ]; do
  case "$1" in
    --platform | --target | --arch | --compiler | --optimize | --sanitize)
      [ $# -ge 2 ] && [ -n "$2" ] || die 2 "$1 needs a value"
      case "$1" in
        --platform) platform="$2" ;;
        --target) target="$2" ;;
        --arch) arch="$2" ;;
        --compiler) compiler="$2" ;;
        --optimize) optimize="$2" ;;
        --sanitize) sanitize="$2" ;;
      esac
      shift 2
      ;;
    --print-cache-key) print_key=1; shift ;;
    *) die 2 "unknown argument '$1' (usage: bash scripts/build-native.sh [--platform linux|android] [--target template_debug|template_release] [--arch x86_64|arm64] [--compiler gcc|clang] [--optimize speed] [--sanitize undefined] [--print-cache-key])" ;;
  esac
done
case "$platform" in linux | android) ;; *) die 2 "--platform must be linux or android, got '$platform'" ;; esac
case "$target" in template_debug | template_release) ;; *) die 2 "--target must be template_debug or template_release, got '$target'" ;; esac
case "$compiler" in "" | gcc | clang) ;; *) die 2 "--compiler must be gcc or clang, got '$compiler'" ;; esac
case "$optimize" in "" | speed) ;; *) die 2 "--optimize must be speed, got '$optimize'" ;; esac
case "$sanitize" in "" | undefined) ;; *) die 2 "--sanitize must be undefined, got '$sanitize'" ;; esac
[ -z "$sanitize" ] || [ "$platform" = "linux" ] || die 2 "--sanitize builds the Linux library only (the phone never runs a sanitized one)"
[ -z "$sanitize" ] || [ "$compiler" != "clang" ] || die 2 "--sanitize undefined builds with g++: clang links no UBSan runtime into a shared library"
[ -z "$sanitize" ] || [ -z "$optimize" ] || die 2 "--sanitize undefined builds at -O1 whatever --optimize says: drop --optimize"
host_arch="$(uname -m)"
case "$host_arch" in aarch64 | arm64) host_arch="arm64" ;; esac
if [ "$platform" = "android" ]; then
  [ -n "$arch" ] || arch="arm64"
  [ "$arch" = "arm64" ] || die 2 "android builds arm64 only (the preset ships arm64-v8a), got --arch $arch"
  [ "$compiler" != "gcc" ] || die 2 "android builds with the NDK's clang, got --compiler gcc"
  compiler="clang"
else
  [ -n "$arch" ] || arch="$host_arch"
  [ -n "$compiler" ] || compiler="gcc"
  [ "$arch" = "$host_arch" ] || die 2 "linux builds the host architecture only ($host_arch), got --arch $arch"
fi

# (1) Tools. Each missing one is named.
command -v git >/dev/null 2>&1 || die 3 "git is missing (needed to fetch godot-cpp)"
command -v "$SCONS" >/dev/null 2>&1 || die 3 "scons is missing: pipx install scons==${SCONS_VERSION} (or set SCONS=/path/to/scons)"
scons_version="$("$SCONS" --version 2>/dev/null | sed -n 's/^.*SCons: v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*$/\1/p' | head -n 1 || true)"
[ "$scons_version" = "$SCONS_VERSION" ] ||
  die 3 "needs scons ${SCONS_VERSION}, '$SCONS' reports '${scons_version:-nothing}': pipx install scons==${SCONS_VERSION}"
scons_env=()
scons_args=()
if [ "$platform" = "linux" ]; then
  if [ "$compiler" = "clang" ]; then
    cxx="clang++"
    command -v clang >/dev/null 2>&1 && command -v clang++ >/dev/null 2>&1 || die 3 "clang or clang++ is missing (install clang)"
    cc_version="$(clang++ --version 2>/dev/null | sed -n 's/^.*clang version \([0-9][0-9.]*\).*$/\1/p' | head -n 1 || true)"
    scons_args=("use_llvm=yes")
  else
    cxx="g++"
    command -v g++ >/dev/null 2>&1 || die 3 "g++ is missing (install g++; the build uses it whatever CXX says)"
    cc_version="$(g++ -dumpfullversion 2>/dev/null || true)"
    # -print-file-name answers the bare name when the file is not in the compiler's search path.
    [ -z "$sanitize" ] || [ "$(g++ -print-file-name=libubsan.so 2>/dev/null)" != "libubsan.so" ] ||
      die 3 "g++ has no libubsan (install libubsan1 and the sanitizer runtime of gcc)"
  fi
  [ -n "$cc_version" ] || die 3 "$cxx reports no version"
  for tool in readelf nm; do
    command -v "$tool" >/dev/null 2>&1 || die 3 "$tool is missing (install binutils)"
  done
  cc_id="${compiler}${cc_version}"
  echo "build-native: $("$cxx" --version | head -n 1), scons ${scons_version}" >&2
else
  ndk="${ANDROID_NDK_ROOT:-}"
  [ -n "$ndk" ] || die 3 "ANDROID_NDK_ROOT is not set (Android NDK missing: CI sets it, a cloud session gets it from scripts/cloud/install-android.sh)"
  # godot-cpp reads the NDK as $ANDROID_HOME/ndk/<ndk_version> and falls back to ANDROID_NDK_ROOT only
  # when ANDROID_HOME is no option at all (a KeyError), so derive the SDK folder from the NDK folder.
  if [ "$(basename "$ndk")" != "$NDK_VERSION" ] || [ "$(basename "$(dirname "$ndk")")" != "ndk" ]; then
    die 3 "ANDROID_NDK_ROOT='$ndk' must be <sdk>/ndk/${NDK_VERSION} (the layout sdkmanager makes)"
  fi
  toolchain="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
  [ -x "$toolchain/clang++" ] || die 3 "the Android NDK toolchain is missing: no $toolchain/clang++"
  ndk_revision="$(sed -n 's/^Pkg\.Revision[[:space:]]*=[[:space:]]*\([0-9][0-9.]*\).*$/\1/p' "$ndk/source.properties" 2>/dev/null | head -n 1 || true)"
  [ "$ndk_revision" = "$NDK_VERSION" ] ||
    die 3 "needs Android NDK ${NDK_VERSION}, '$ndk' is '${ndk_revision:-unknown}': run scripts/ci/install-ndk.sh"
  for tool in llvm-readelf llvm-nm; do
    [ -x "$toolchain/$tool" ] || die 3 "the Android NDK toolchain is missing: no $toolchain/$tool"
  done
  cc_id="ndk${ndk_revision}"
  echo "build-native: Android NDK ${ndk_revision}, scons ${scons_version}" >&2
  # ANDROID_HOME for this one process only, so that godot-cpp finds exactly the NDK checked above.
  scons_env=(env -u ANDROID_SDK_ROOT "ANDROID_HOME=$(dirname "$(dirname "$ndk")")")
  scons_args=("ndk_version=${NDK_VERSION}")
fi
[ -z "$optimize" ] || scons_args+=("optimize=${optimize}")
[ -z "$sanitize" ] || scons_args+=("sanitize=${sanitize}")
if [ "$print_key" = 1 ]; then
  echo "native-${platform}-${arch}-${target}-${cc_id}${optimize:+-$optimize}${sanitize:+-sanitize-$sanitize}-godotcpp-${GODOT_CPP_SHA}-scons${scons_version}"
  exit 0
fi

# (2) godot-cpp at the pinned commit. The SHA is checked after the fetch and on every run.
sha_of() { git -C "$1" rev-parse HEAD 2>/dev/null || true; }
if [ -e "$GODOT_CPP_DIR" ]; then
  have="$(sha_of "$GODOT_CPP_DIR")"
  [ "$have" = "$GODOT_CPP_SHA" ] ||
    die 4 "native/godot-cpp is at '${have:-no git checkout}', not the pinned ${GODOT_CPP_SHA}: delete native/godot-cpp and rerun"
else
  tmp="$(mktemp -d "$ROOT/native/.godot-cpp-fetch.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  echo "build-native: fetching godot-cpp ${GODOT_CPP_TAG} (${GODOT_CPP_SHA})"
  (
    cd "$tmp"
    git init -q .
    git remote add origin "$GODOT_CPP_URL"
    git fetch -q --depth 1 origin "$GODOT_CPP_SHA"
    git checkout -q FETCH_HEAD
  ) || die 4 "fetching godot-cpp from $GODOT_CPP_URL failed"
  got="$(sha_of "$tmp")"
  [ "$got" = "$GODOT_CPP_SHA" ] || die 4 "godot-cpp SHA mismatch: fetched '${got}', pinned ${GODOT_CPP_SHA}"
  : >"$tmp/.gdignore" # Godot must not import godot-cpp's sources as project resources
  mv "$tmp" "$GODOT_CPP_DIR"
  trap - EXIT
fi

# (3) Build. build_profile binds only the engine classes the bind layer uses instead of all ~1000,
# which takes a cold godot-cpp build from minutes to seconds; it changes no compiler flag.
jobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
echo "build-native: ${platform} ${target} ${arch} (${cc_id}${optimize:+, optimize=${optimize}}${sanitize:+, sanitize=${sanitize}}), ${jobs} jobs"
log="$(mktemp -t build-native.XXXXXX)"
set +e
(
  cd "$ROOT/native/sim_kernels"
  ${scons_env[@]+"${scons_env[@]}"} "$SCONS" "-j${jobs}" "platform=${platform}" "target=${target}" "arch=${arch}" \
    "build_profile=${ROOT}/native/sim_kernels/build_profile.json" ${scons_args[@]+"${scons_args[@]}"}
) 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e
if [ "$status" -ne 0 ]; then
  tail -n 30 "$log" >&2
  die 4 "scons failed with exit code ${status} (log: $log)"
fi
library="$ROOT/native/bin/libsim_kernels.${platform}.${target}.${arch}.so"
[ -s "$library" ] || die 4 "scons succeeded but ${library#"$ROOT"/} is missing or empty (log: $log)"
rm -f "$log"

# (4) Look inside the library, so that a wrong build fails here and not on the phone: the right
# machine, a shared object, the entry symbol exported, and on Android no dependency that the phone
# cannot resolve (the NDK's clang++ links the libc++_shared.so that Godot's template ships). Host
# binutils for linux, the NDK's llvm tools for android.
if [ "$platform" = "android" ]; then
  elf_readelf="$toolchain/llvm-readelf"
  elf_nm="$toolchain/llvm-nm"
  elf_machine="AArch64"
  elf_allowed="libc.so libm.so libdl.so liblog.so libandroid.so libc++_shared.so"
else
  elf_readelf="readelf"
  elf_nm="nm"
  elf_allowed=""
  case "$arch" in x86_64) elf_machine="Advanced Micro Devices X86-64" ;; *) elf_machine="AArch64" ;; esac
fi
elf_name="${library#"$ROOT"/}"
elf_header="$("$elf_readelf" -h "$library" 2>&1)" || die 4 "$elf_readelf -h failed on $elf_name: $elf_header"
grep -Eq "^[[:space:]]*Machine:[[:space:]]+${elf_machine}[[:space:]]*\$" <<<"$elf_header" ||
  die 4 "$elf_name is not a '${elf_machine}' ELF file: $(grep -E '^[[:space:]]*Machine:' <<<"$elf_header" | tr -s ' ' || true)"
grep -Eq '^[[:space:]]*Type:[[:space:]]+DYN' <<<"$elf_header" || die 4 "$elf_name is not a shared object"
elf_dynamic="$("$elf_readelf" -d "$library" 2>&1)" || die 4 "$elf_readelf -d failed on $elf_name: $elf_dynamic"
elf_needed="$(sed -n 's/^.*(NEEDED)[[:space:]]*Shared library: \[\(.*\)\].*$/\1/p' <<<"$elf_dynamic" | tr '\n' ' ')"
if [ -n "$elf_allowed" ]; then
  for lib in $elf_needed; do
    case " $elf_allowed " in
      *" $lib "*) ;;
      *) die 4 "$elf_name needs $lib, which neither Android nor Godot's template provides (allowed: $elf_allowed)" ;;
    esac
  done
fi
elf_symbols="$("$elf_nm" -D --defined-only "$library" 2>&1)" || die 4 "$elf_nm -D failed on $elf_name: $elf_symbols"
grep -Eq " T ${ENTRY_SYMBOL}\$" <<<"$elf_symbols" || die 4 "$elf_name does not export the entry symbol ${ENTRY_SYMBOL}"
if [ -n "$sanitize" ]; then
  # Instrumented and linked to the shared runtime: the handlers are undefined symbols that libubsan provides.
  case " $elf_needed " in *" libubsan.so"*) ;; *) die 4 "$elf_name does not need the shared libubsan (needs: ${elf_needed:-nothing})" ;; esac
  elf_undefined="$("$elf_nm" -D --undefined-only "$library" 2>&1)" || die 4 "$elf_nm -D --undefined-only failed on $elf_name: $elf_undefined"
  grep -Eq ' U __ubsan_handle_' <<<"$elf_undefined" || die 4 "$elf_name calls no __ubsan_handle_ function: it was not instrumented"
  # Signed overflow is checked only without -fwrapv, and a handler is fatal only with -fno-sanitize-recover=all (its name
  # ends in _abort; the two that cannot return have no other kind): losing either flag would leave the library running
  # green over the bugs it is there to find.
  elf_handlers="$(grep -Eo '__ubsan_handle_[A-Za-z0-9_]+' <<<"$elf_undefined" || true)"
  grep -Eq '^__ubsan_handle_(add|sub|mul)_overflow_abort$' <<<"$elf_handlers" ||
    die 4 "$elf_name calls no fatal signed-overflow handler: -fwrapv is on, or the checks are not fatal"
  elf_recoverable="$(grep -Ev '_abort$|^__ubsan_handle_(builtin_unreachable|missing_return)$' <<<"$elf_handlers" | tr '\n' ' ' || true)"
  [ -z "$elf_recoverable" ] || die 4 "$elf_name calls handlers that return after a report (${elf_recoverable% }): -fno-sanitize-recover=all is off"
fi
echo "build-native: ELF ok: ${elf_machine}, shared object, exports ${ENTRY_SYMBOL}, needs ${elf_needed:-nothing}${sanitize:+(instrumented: $sanitize)}"

# (5) The generated .gdextension names every platform's library, whatever was built, so that its
# content never depends on the build that wrote it; Godot loads its own platform's entry only.
ext="$ROOT/native/sim_kernels.gdextension"
text="; Generated by scripts/build-native.sh and git-ignored (ADR 0013 section 9): a checkout without a
; build has no .gdextension and loads no library. Do not edit.
[configuration]

entry_symbol = \"${ENTRY_SYMBOL}\"
compatibility_minimum = \"4.5\"
reloadable = false

[libraries]
"
for combo in linux.x86_64 linux.arm64 android.arm64; do
  for mode in debug release; do
    text="${text}
${combo%%.*}.${mode}.${combo#*.} = \"res://native/bin/libsim_kernels.${combo%%.*}.template_${mode}.${combo#*.}.so\""
  done
done
if [ ! -f "$ext" ] || [ "$(cat "$ext")" != "$text" ]; then
  printf '%s\n' "$text" >"$ext"
fi
echo "build-native: OK ${library#"$ROOT"/} ($(wc -c <"$library" | tr -d ' ') bytes)"
