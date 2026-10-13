#!/usr/bin/env bash
# The ELF and libc++ checks of the Android kernels library as the APK packs it (ADR 0013 sections 8 and
# 10), and a description, with no verdict, of the template's libraries. It takes file paths only:
# export-android.sh extracts the files from the APK, test-android-elf.sh runs it on fixtures.
# Usage: bash scripts/ci/check-android-elf.sh check [--machine NAME] [--entry-symbol NAME] LIBRARY LIBCXX
#        bash scripts/ci/check-android-elf.sh describe FILE...
#   check     LIBRARY is our library, LIBCXX the APK's libc++_shared.so. Every failing check is reported,
#             then the exit is 1: the machine (default AArch64) and a shared object; NEEDED only system
#             libraries or libc++_shared.so (required when LIBRARY uses a libc++ symbol); the entry symbol
#             (default ENTRY_SYMBOL of build-native.sh) exported; every PT_LOAD p_align at least 0x4000;
#             PT_GNU_RELRO ending on a 0x4000 boundary (Google's check); every undefined libc++ symbol
#             defined by LIBCXX. That is a C++ mangled _Z... name, a libc++abi __cxa_... or __gxx_... helper
#             that bionic's libc does not define, __dynamic_cast (godot-cpp's Wrapped uses dynamic_cast) and
#             __emutls_get_address (emulated TLS below API 29): the names the template's libc++_shared.so
#             exports besides C++ mangled ones, less its compiler-rt helper __muloti4, which is not counted.
#   describe  prints the .note.android.ident strings and the PT_LOAD alignment of each FILE.
# Env:   READELF, NM override the tools; default llvm-readelf and llvm-nm of $ANDROID_NDK_ROOT, else binutils.
# Exit:  0 ok, 1 a check failed, 2 usage error, 3 tool missing.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# The system libraries the phone resolves, as build-native.sh lists them (test-android-elf.sh compares).
ALLOWED="libc.so libm.so libdl.so liblog.so libandroid.so libc++_shared.so"
LIBCXX="libc++_shared.so"
MIN_ALIGN=$((0x4000))

die() {
  local code="$1"
  shift
  echo "check-android-elf: $*" >&2
  exit "$code"
}

ndk_bin="${ANDROID_NDK_ROOT:-/nonexistent}/toolchains/llvm/prebuilt/linux-x86_64/bin"
if [ -x "$ndk_bin/llvm-readelf" ] && [ -x "$ndk_bin/llvm-nm" ]; then
  readelf_bin="${READELF:-$ndk_bin/llvm-readelf}"
  nm_bin="${NM:-$ndk_bin/llvm-nm}"
else
  readelf_bin="${READELF:-readelf}"
  nm_bin="${NM:-nm}"
fi
for tool in "$readelf_bin" "$nm_bin"; do
  command -v "$tool" >/dev/null 2>&1 || die 3 "$tool is missing (install binutils)"
done

load_aligns() { "$readelf_bin" -lW "$1" 2>&1 | awk '$1 == "LOAD" { printf "%s ", $NF }' || true; }

mode="${1:-}"
[ $# -eq 0 ] || shift
if [ "$mode" = describe ]; then
  [ $# -ge 1 ] || die 2 "describe needs at least one file"
  for file in "$@"; do
    note="$("$readelf_bin" -p .note.android.ident "$file" 2>&1 | sed -n 's/^[[:space:]]*\[[[:space:]]*[0-9a-f]*\][[:space:]]*//p' | grep -E '[A-Za-z0-9]{2,}' | tr '\n' ' ' || true)"
    echo "check-android-elf: $(basename "$file"): .note.android.ident: ${note:-none}; PT_LOAD align: $(load_aligns "$file")"
  done
  exit 0
fi

machine="AArch64"
entry="$(sed -n 's/^ENTRY_SYMBOL="\(.*\)"$/\1/p' "$ROOT/scripts/build-native.sh")"
while [ "$mode" = check ] && [ $# -gt 0 ]; do
  case "$1" in
    --machine | --entry-symbol)
      [ $# -ge 2 ] && [ -n "$2" ] || die 2 "$1 needs a value"
      if [ "$1" = --machine ]; then machine="$2"; else entry="$2"; fi
      shift 2
      ;;
    *) break ;;
  esac
done
[ "$mode" = check ] && [ $# -eq 2 ] || die 2 "usage: check [--machine NAME] [--entry-symbol NAME] LIBRARY LIBCXX | describe FILE..."
[ -n "$entry" ] || die 2 "scripts/build-native.sh has no ENTRY_SYMBOL line"
lib="$1"
libcxx="$2"
name="$(basename "$lib")"

problems=""
problem() { problems="${problems}check-android-elf: FAIL $name: $1"$'\n'; }

header="$("$readelf_bin" -h "$lib" 2>&1)" || die 1 "$name is not an ELF file: $header"
grep -Eq "^[[:space:]]*Machine:[[:space:]]+${machine}[[:space:]]*\$" <<<"$header" ||
  problem "is not a '${machine}' ELF file: $(grep -E '^[[:space:]]*Machine:' <<<"$header" | tr -s ' ' || true)"
grep -Eq '^[[:space:]]*Type:[[:space:]]+DYN' <<<"$header" || problem "is not a shared object"

loads=0
small=0
relro_end=""
while read -r type _ vaddr _ _ memsz rest; do
  case "$type" in
    LOAD)
      loads=$((loads + 1))
      [ $((${rest##* })) -ge "$MIN_ALIGN" ] || small=$((small + 1))
      ;;
    GNU_RELRO) relro_end=$((vaddr + memsz)) ;;
  esac
done <<<"$("$readelf_bin" -lW "$lib" 2>&1)"
[ "$loads" -gt 0 ] || problem "has no PT_LOAD segment"
[ "$small" -eq 0 ] || problem "$small of $loads PT_LOAD segments have p_align below 0x4000 (16 KB pages)"
if [ -z "$relro_end" ]; then
  problem "has no PT_GNU_RELRO segment"
elif [ $((relro_end % MIN_ALIGN)) -ne 0 ]; then
  problem "PT_GNU_RELRO ends at $(printf '0x%x' "$relro_end"), not on a 0x4000 boundary"
fi

dynamic="$("$readelf_bin" -d "$lib" 2>&1)" || die 1 "$readelf_bin -d failed on $name: $dynamic"
needed="$(sed -n 's/^.*(NEEDED)[[:space:]]*Shared library: \[\(.*\)\].*$/\1/p' <<<"$dynamic" | tr '\n' ' ')"
needed="${needed% }"
for dep in $needed; do
  case " $ALLOWED " in *" $dep "*) ;; *) problem "needs $dep, which neither Android nor Godot's template provides (allowed: $ALLOWED)" ;; esac
done

defined="$("$nm_bin" -D --defined-only "$lib" 2>&1)" || die 1 "$nm_bin -D failed on $name: $defined"
awk -v e="$entry" '$2 == "T" && $3 == e { found = 1 } END { exit !found }' <<<"$defined" || problem "does not export the entry symbol $entry"

# Undefined libc++ symbols against what the APK's libc++_shared.so defines. Weak references (w) are skipped, and
# the version suffix nm prints (__cxa_atexit@LIBC on bionic's symbols in the real libraries) is cut on both sides.
undefined="$("$nm_bin" -D --undefined-only "$lib" 2>&1)" || die 1 "$nm_bin -D failed on $name: $undefined"
cxx_defined="$("$nm_bin" -D --defined-only "$libcxx" 2>&1)" || die 1 "$nm_bin -D failed on $(basename "$libcxx"): $cxx_defined"
wanted="$(awk '
  { sub(/@.*/, "", $2) }
  $1 == "U" && ($2 ~ /^(_Z|__gxx_)/ || $2 == "__dynamic_cast" || $2 == "__emutls_get_address" ||
    ($2 ~ /^__cxa_/ && $2 !~ /^__cxa_(atexit|finalize|thread_atexit_impl)$/)) { print $2 }' <<<"$undefined" | LC_ALL=C sort -u)"
have="$(awk '{ sub(/@.*/, "", $3); print $3 }' <<<"$cxx_defined" | LC_ALL=C sort -u)"
missing="$(grep -vxF -f <(printf '%s\n' "$have") <<<"$wanted" || true)"
[ -z "$missing" ] || problem "uses $(grep -c . <<<"$missing") libc++ symbol(s) that $(basename "$libcxx") does not define, first: $(head -n 3 <<<"$missing" | tr '\n' ' ')"
if [ -n "$wanted" ]; then
  case " $needed " in *" $LIBCXX "*) ;; *) problem "uses libc++ symbols but $LIBCXX is not NEEDED" ;; esac
fi

if [ -n "$problems" ]; then
  printf '%s' "$problems" >&2
  exit 1
fi
echo "check-android-elf: OK $name: $machine shared object, exports $entry, needs ${needed:-nothing}, $loads PT_LOAD of p_align 0x4000 or more, RELRO ends at $(printf '0x%x' "$relro_end"), $(grep -c . <<<"$wanted" || true) libc++ symbol(s) defined by $(basename "$libcxx")"
