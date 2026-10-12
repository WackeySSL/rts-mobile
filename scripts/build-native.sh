#!/usr/bin/env bash
# PROBE ONLY (spike P26n, branch claude/p26n-cpp-spike, never merged): builds the ProbeTickNative
# GDExtension (native/probe_tick) against godot-cpp, fetched at a pinned commit into the git-ignored
# native/godot-cpp, and writes the library to the git-ignored native/bin/.
# Usage: bash scripts/build-native.sh [--platform linux|android] [--target template_debug|template_release]
#                                     [--arch x86_64|arm64]
#   defaults: --platform linux --target template_debug --arch x86_64
#   linux builds the host architecture only; android builds arm64 only (Android is built in CI,
#   a cloud session has no NDK).
# Env:   SCONS=<binary> (default: scons; must be 4.9.1), CXX=<compiler> (linux, default: g++),
#        ANDROID_NDK_ROOT=<NDK folder> (android; the toolchain is read from
#        $ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64).
# Needs: git and network access to github.com (first run only), scons 4.9.1
#        (pip install scons==4.9.1), a C++ compiler.
# Flags: godot-cpp's defaults per target, nothing added: template_debug = -O2 (optimize=speed_trace,
#        DEBUG_ENABLED), template_release = -O3 (optimize=speed, NDEBUG); no LTO, no debug symbols.
# Exit:  0 ok
#        2 bad flag or an impossible platform/arch pair
#        3 tool missing (git, scons 4.9.1, the compiler, or ANDROID_NDK_ROOT / the NDK toolchain)
#        4 godot-cpp fetch or SHA check failed, or the build failed or produced no library
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
SCONS="${SCONS:-scons}"
GODOT_CPP_DIR="$ROOT/native/godot-cpp"

die() {
  local code="$1"
  shift
  echo "build-native: $*" >&2
  exit "$code"
}

usage() {
  echo "usage: bash scripts/build-native.sh [--platform linux|android] [--target template_debug|template_release] [--arch x86_64|arm64]" >&2
}

platform="linux"
target="template_debug"
arch="x86_64"
while [ $# -gt 0 ]; do
  case "$1" in
    --platform | --target | --arch)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        usage
        die 2 "$1 needs a value"
      fi
      case "$1" in
        --platform) platform="$2" ;;
        --target) target="$2" ;;
        --arch) arch="$2" ;;
      esac
      shift 2
      ;;
    --platform=* | --target=* | --arch=*)
      value="${1#*=}"
      case "$1" in
        --platform=*) platform="$value" ;;
        --target=*) target="$value" ;;
        --arch=*) arch="$value" ;;
      esac
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      die 2 "unknown argument '$1'"
      ;;
  esac
done

case "$platform" in linux | android) ;; *) usage; die 2 "--platform must be linux or android, got '$platform'" ;; esac
case "$target" in template_debug | template_release) ;; *) usage; die 2 "--target must be template_debug or template_release, got '$target'" ;; esac
case "$arch" in x86_64 | arm64) ;; *) usage; die 2 "--arch must be x86_64 or arm64, got '$arch'" ;; esac

if [ "$platform" = "android" ] && [ "$arch" != "arm64" ]; then
  die 2 "android builds arm64 only (the preset ships arm64-v8a), got --arch $arch"
fi
if [ "$platform" = "linux" ]; then
  host_arch="$(uname -m)"
  case "$host_arch" in aarch64 | arm64) host_arch="arm64" ;; esac
  if [ "$arch" != "$host_arch" ]; then
    die 2 "linux builds the host architecture only ($host_arch), got --arch $arch"
  fi
fi

# (1) Tools. Each missing one is named.
command -v git >/dev/null 2>&1 || die 3 "git is missing (needed to fetch godot-cpp)"
command -v "$SCONS" >/dev/null 2>&1 || die 3 "scons is missing: pip install scons==${SCONS_VERSION} (or set SCONS=/path/to/scons)"
scons_version="$("$SCONS" --version 2>/dev/null | sed -n 's/^.*SCons: v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*$/\1/p' | head -n 1 || true)"
[ "$scons_version" = "$SCONS_VERSION" ] ||
  die 3 "needs scons ${SCONS_VERSION}, '$SCONS' reports '${scons_version:-nothing}': pip install scons==${SCONS_VERSION}"
scons_env=()
if [ "$platform" = "linux" ]; then
  compiler="${CXX:-g++}"
  command -v "$compiler" >/dev/null 2>&1 || die 3 "C++ compiler '$compiler' is missing (install g++ or set CXX)"
else
  ndk="${ANDROID_NDK_ROOT:-}"
  [ -n "$ndk" ] || die 3 "ANDROID_NDK_ROOT is not set (Android NDK missing; a cloud session has none, CI sets it)"
  toolchain="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
  [ -x "$toolchain/clang++" ] || die 3 "the Android NDK toolchain is missing: no $toolchain/clang++ (ANDROID_NDK_ROOT='$ndk')"
  # godot-cpp looks for $ANDROID_HOME/ndk/<its default version> first; the NDK of ANDROID_NDK_ROOT
  # is the one the caller chose, so hide the SDK variables from this one process.
  scons_env=(env -u ANDROID_HOME -u ANDROID_SDK_ROOT "ANDROID_NDK_ROOT=$ndk")
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
  # Godot must not import the sources and generated files of godot-cpp as project resources.
  : >"$tmp/.gdignore"
  mv "$tmp" "$GODOT_CPP_DIR"
  trap - EXIT
fi
mkdir -p "$ROOT/native/bin"

# (3) Build. scons caches: a second run with nothing changed rebuilds nothing.
jobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
case "$target" in
  template_debug) optimize="-O2 (godot-cpp optimize=speed_trace)" ;;
  template_release) optimize="-O3 (godot-cpp optimize=speed)" ;;
esac
echo "build-native: ${platform} ${target} ${arch}, ${optimize}, ${jobs} jobs"
log="$(mktemp -t build-native.XXXXXX)"
set +e
(
  cd "$ROOT/native/probe_tick"
  # build_profile: godot-cpp binds only the engine classes the port uses (OS, RefCounted and their
  # parents) instead of all ~1000, which takes the first build from minutes to under one.
  ${scons_env[@]+"${scons_env[@]}"} "$SCONS" "-j${jobs}" "platform=${platform}" "target=${target}" "arch=${arch}" \
    "build_profile=${ROOT}/native/probe_tick/build_profile.json"
) 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e
if [ "$status" -ne 0 ]; then
  tail -n 30 "$log" >&2
  die 4 "scons failed with exit code ${status} (log: $log)"
fi

# (4) The library.
library="$ROOT/native/bin/libprobe_tick.${platform}.${target}.${arch}.so"
[ -s "$library" ] || die 4 "scons succeeded but ${library#"$ROOT"/} is missing or empty (log: $log)"
rm -f "$log"

# (5) Godot 4.7.2 aborts at the end of a fresh `godot --import` (exit 134 or 139; 4 of 6 runs on
# the dev VM, 6 of 6 with a bare class registered) when the first scan of the project finds a
# GDExtension that registers a class. Listing the extension in .godot/extension_list.cfg first, as
# the editor does after its first scan, makes the first import load it at startup like every
# later run (0 of 6 aborts). The file only names the .gdextension; Godot rewrites it as needed.
list="$ROOT/.godot/extension_list.cfg"
mkdir -p "$ROOT/.godot"
if [ ! -f "$list" ] || ! grep -qxF 'res://native/probe_tick.gdextension' "$list"; then
  printf '%s\n' 'res://native/probe_tick.gdextension' >>"$list"
fi
echo "build-native: OK ${library#"$ROOT"/} ($(wc -c <"$library" | tr -d ' ') bytes)"
