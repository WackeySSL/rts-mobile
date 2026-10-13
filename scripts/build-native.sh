#!/usr/bin/env bash
# Builds the native sim kernels (native/sim_kernels, ADR 0013) against godot-cpp, fetched at a
# pinned commit into the git-ignored native/godot-cpp. The library goes to the git-ignored
# native/bin/, and so does the native/sim_kernels.gdextension that names it: generated, so that a
# checkout without a build is a plain GDScript project (ADR 0013 section 9). verify.sh runs it first.
# Usage: bash scripts/build-native.sh [--platform linux] [--target template_debug|template_release]
#                                     [--arch x86_64|arm64]    (linux: the host architecture only)
# Env:   SCONS=<binary> (default: scons; must be 4.9.1), SCONS_CACHE=<folder> (godot-cpp's CacheDir)
# Needs: git and network access to github.com (first run only), scons 4.9.1, and g++ (godot-cpp's
#        SConstruct never reads CXX; use_llvm=yes picks clang). Flags: native/sim_kernels/SConstruct.
# Exit:  0 ok
#        2 bad flag or an impossible platform/arch pair
#        3 tool missing (git, scons 4.9.1, g++)
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

platform="linux"
target="template_debug"
arch="x86_64"
while [ $# -gt 0 ]; do
  case "$1" in
    --platform | --target | --arch)
      [ $# -ge 2 ] && [ -n "$2" ] || die 2 "$1 needs a value"
      case "$1" in
        --platform) platform="$2" ;;
        --target) target="$2" ;;
        --arch) arch="$2" ;;
      esac
      shift 2
      ;;
    *) die 2 "unknown argument '$1' (usage: bash scripts/build-native.sh [--platform linux] [--target template_debug|template_release] [--arch x86_64|arm64])" ;;
  esac
done
[ "$platform" = "linux" ] || die 2 "--platform must be linux, got '$platform'"
case "$target" in template_debug | template_release) ;; *) die 2 "--target must be template_debug or template_release, got '$target'" ;; esac
host_arch="$(uname -m)"
case "$host_arch" in aarch64 | arm64) host_arch="arm64" ;; esac
[ "$arch" = "$host_arch" ] || die 2 "linux builds the host architecture only ($host_arch), got --arch $arch"

# (1) Tools. Each missing one is named.
command -v git >/dev/null 2>&1 || die 3 "git is missing (needed to fetch godot-cpp)"
command -v "$SCONS" >/dev/null 2>&1 || die 3 "scons is missing: pipx install scons==${SCONS_VERSION} (or set SCONS=/path/to/scons)"
scons_version="$("$SCONS" --version 2>/dev/null | sed -n 's/^.*SCons: v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*$/\1/p' | head -n 1 || true)"
[ "$scons_version" = "$SCONS_VERSION" ] ||
  die 3 "needs scons ${SCONS_VERSION}, '$SCONS' reports '${scons_version:-nothing}': pipx install scons==${SCONS_VERSION}"
command -v g++ >/dev/null 2>&1 || die 3 "g++ is missing (install g++; the build uses it whatever CXX says)"
echo "build-native: $(g++ --version | head -n 1), scons ${scons_version}"

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
echo "build-native: ${platform} ${target} ${arch}, ${jobs} jobs"
log="$(mktemp -t build-native.XXXXXX)"
set +e
(
  cd "$ROOT/native/sim_kernels"
  "$SCONS" "-j${jobs}" "platform=${platform}" "target=${target}" "arch=${arch}" \
    "build_profile=${ROOT}/native/sim_kernels/build_profile.json"
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

# (4) The generated .gdextension names every platform's library, whatever was built, so that its
# content never depends on the build that wrote it; Godot loads its own platform's entry only.
ext="$ROOT/native/sim_kernels.gdextension"
text="; Generated by scripts/build-native.sh and git-ignored (ADR 0013 section 9): a checkout without a
; build has no .gdextension and loads no library. Do not edit.
[configuration]

entry_symbol = \"sim_kernels_library_init\"
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
