#!/usr/bin/env bash
# Offline test of scripts/ci/check-android-elf.sh (P55a2, ADR 0013 sections 8 and 10) on ELF fixtures that gcc
# builds here: a good library, a fake libc++_shared.so and a versioned libc.so, and one failing variant per check.
# The fixtures have the host's machine; the real arm64 run is the Android job's. Every case runs with GNU
# binutils and, when on PATH or in $ANDROID_NDK_ROOT, with llvm-readelf and llvm-nm (the NDK's tools).
# Needs: bash, gcc, binutils (readelf, nm, objcopy, dd). Exit: 0 all cases pass, 1 a case failed.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
root="$(mktemp -d)"
trap 'rm -rf "${root:?}"' EXIT
failures=0
checker="$repo/scripts/ci/check-android-elf.sh"
entry="$(sed -n 's/^ENTRY_SYMBOL="\(.*\)"$/\1/p' "$repo/scripts/build-native.sh")"

run() { # ARGS...: runs the checker with the tools in $tools; sets rc and out
  rc=0
  out="$(env -i PATH="$PATH" HOME="$root" ${tools[@]+"${tools[@]}"} bash "$checker" "$@" 2>&1)" || rc=$?
}
t() { # name, wanted exit code, wanted text, checker arguments (after "check"): run and check
  local name="$1" want="$2" text="$3"
  shift 3
  run check "$@"
  check "$name" "$want" "$text"
}
check() { # name, wanted exit code, wanted text in the output
  if [ "$rc" = "$2" ] && grep -Fq -- "$3" <<<"$out"; then
    echo "ok: $label: $1"
  else
    echo "FAIL: $label: $1 (wanted exit $2 and '$3', got exit $rc: $(tail -n 2 <<<"$out" | tr '\n' ' '))" >&2
    failures=$((failures + 1))
  fi
}

# One source for every fixture: -DDEF=sym defines it, -DUSE=sym (and -DUSE2) are referenced by the entry function.
cat >"$root/fix.c" <<'EOF'
#ifdef DEF
void f(void) __asm__(DEF);
void f(void) {}
#else
extern void u(void) __asm__(USE);
#ifdef USE2
extern void v(void) __asm__(USE2);
#endif
void ENTRY(void) {
  u();
#ifdef USE2
  v();
#endif
}
#endif
EOF
page16="-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384"
so() { gcc -shared -nostdlib -fPIC -Wl,-z,relro $page16 "$root/fix.c" "${@:2}" -o "$root/$1"; } # OUT, then flags and libraries (after the source: --as-needed)
std='"_ZNSt6__ndk16stringC1Ev"'
so libc++_shared.so -Wl,-soname,libc++_shared.so -DDEF="$std"
printf 'LIBC { global: __cxa_atexit; };\n' >"$root/libc.map" # bionic versions its symbols: nm prints __cxa_atexit@LIBC
so libc.so -Wl,-soname,libc.so -Wl,--version-script="$root/libc.map" -DDEF='"__cxa_atexit"'
so libextra.so -Wl,-soname,libextra.so -DDEF='"extra"'
use=(-DENTRY="$entry" -DUSE="$std" -DUSE2='"__cxa_atexit"')
so good.so "${use[@]}" "$root/libc.so" "$root/libc++_shared.so"
so 4k.so "${use[@]}" -Wl,-z,max-page-size=4096 -Wl,-z,common-page-size=4096 "$root/libc.so" "$root/libc++_shared.so"
so norelro.so "${use[@]}" -Wl,-z,norelro "$root/libc.so" "$root/libc++_shared.so"
so nocxx.so "${use[@]}" "$root/libc.so"
so extra.so "${use[@]}" "$root/libc.so" -Wl,--no-as-needed "$root/libextra.so" "$root/libc++_shared.so"
so noentry.so -DENTRY=other "-DUSE=$std" "$root/libc++_shared.so"
so unknown.so -DENTRY="$entry" -DUSE='"_ZNSt6__ndk16stringD1Ev"' "$root/libc++_shared.so"
gcc -c -fPIC "${use[@]}" "$root/fix.c" -o "$root/rel.o"
machine="$(readelf -h "$root/good.so" | sed -n 's/^ *Machine: *//p')"
# RELRO end on a 4 KB boundary but not a 16 KB one (what LLD makes without -z common-page-size=16384): add 0x1000 to
# p_memsz of the PT_GNU_RELRO header, which sits at its index in the list of program headers (56 bytes each).
cp "$root/good.so" "$root/relro.so"
index="$(readelf -lW "$root/good.so" | awk '/^ +[A-Z_]+ +0x/ { if ($1 == "GNU_RELRO") print n; n++ }')"
phoff="$(readelf -h "$root/good.so" | sed -n 's/^ *Start of program headers: *\([0-9]*\).*$/\1/p')"
at=$((phoff + index * 56 + 40))
memsz="$(od -An -t u8 -j "$at" -N 8 "$root/relro.so" | tr -d ' ')"
printf "$(printf '\\x%02x\\x%02x' $(((memsz + 4096) & 255)) $((((memsz + 4096) >> 8) & 255)))" |
  dd of="$root/relro.so" bs=1 seek="$at" conv=notrunc 2>/dev/null
printf '\x08\0\0\0\x08\0\0\0\x01\0\0\0Android\0\x1d\0\0\0r29\0' >"$root/note.bin"
objcopy --add-section .note.android.ident="$root/note.bin" "$root/good.so" "$root/noted.so"

cxx="$root/libc++_shared.so"
m=(--machine "$machine")
ndk_bin="${ANDROID_NDK_ROOT:-/nonexistent}/toolchains/llvm/prebuilt/linux-x86_64/bin"
for flavour in gnu llvm; do
  label="$flavour"
  tools=()
  if [ "$flavour" = llvm ]; then
    llvm_readelf="$(command -v llvm-readelf || echo "$ndk_bin/llvm-readelf")"
    llvm_nm="$(command -v llvm-nm || echo "$ndk_bin/llvm-nm")"
    if [ ! -x "$llvm_readelf" ] || [ ! -x "$llvm_nm" ]; then
      echo "skip: llvm: llvm-readelf and llvm-nm are on neither PATH nor in ANDROID_NDK_ROOT"
      continue
    fi
    tools=(READELF="$llvm_readelf" NM="$llvm_nm")
  fi
  t "a good library passes, with the entry symbol of build-native.sh" 0 "OK good.so: $machine shared object, exports $entry, needs libc.so libc++_shared.so, 4 PT_LOAD" "${m[@]}" "$root/good.so" "$cxx"
  t "AArch64 is the default machine" 1 "is not a 'AArch64' ELF file" "$root/good.so" "$cxx"
  t "an object file is no shared object" 1 "is not a shared object" "${m[@]}" "$root/rel.o" "$cxx"
  t "a 4 KB aligned PT_LOAD" 1 "4 of 4 PT_LOAD segments have p_align below 0x4000 (16 KB pages)" "${m[@]}" "$root/4k.so" "$cxx"
  t "a RELRO end on a 4 KB boundary only" 1 "PT_GNU_RELRO ends at 0x11000, not on a 0x4000 boundary" "${m[@]}" "$root/relro.so" "$cxx"
  t "no PT_GNU_RELRO" 1 "has no PT_GNU_RELRO segment" "${m[@]}" "$root/norelro.so" "$cxx"
  t "libc++ symbols without libc++_shared.so NEEDED" 1 "uses libc++ symbols but libc++_shared.so is not NEEDED" "${m[@]}" "$root/nocxx.so" "$cxx"
  t "a NEEDED library the phone cannot resolve" 1 "needs libextra.so, which neither Android nor Godot's template provides" "${m[@]}" "$root/extra.so" "$cxx"
  t "no entry symbol" 1 "does not export the entry symbol $entry" "${m[@]}" "$root/noentry.so" "$cxx"
  t "--entry-symbol names another entry" 0 "exports other" "${m[@]}" --entry-symbol other "$root/noentry.so" "$cxx"
  t "a libc++ symbol that libc++_shared.so does not define" 1 "uses 1 libc++ symbol(s) that libc++_shared.so does not define, first: _ZNSt6__ndk16stringD1Ev" "${m[@]}" "$root/unknown.so" "$cxx"
  t "every failing check is reported: the machine" 1 "is not a 'AArch64' ELF file" "$root/4k.so" "$cxx"
  check "every failing check is reported: the alignment" 1 "PT_LOAD segments have p_align below 0x4000"
  t "check needs both files" 2 "usage: check" "${m[@]}" "$root/good.so"
  run describe "$root/noted.so" "$root/good.so"
  check "describe prints the .note.android.ident strings and the PT_LOAD alignment, no verdict" 0 "noted.so: .note.android.ident: Android r29 ; PT_LOAD align: 0x4000 0x4000 0x4000 0x4000"
  check "describe goes on when a file has no note" 0 "good.so: .note.android.ident: none; PT_LOAD align: 0x4000"
done

# The two lists that live in build-native.sh too: the system libraries of its ELF check and the entry symbol.
allowed="$(sed -n 's/^ALLOWED="\(.*\)"$/\1/p' "$checker")"
[ -n "$allowed" ] && [ "$allowed" = "$(sed -n 's/^  elf_allowed="\(libc.*\)"$/\1/p' "$repo/scripts/build-native.sh")" ] ||
  { echo "FAIL: the NEEDED allow-list differs from build-native.sh's elf_allowed" >&2; failures=$((failures + 1)); }
# What makes the checks pass on the real library: SConstruct sets both sizes, or LLD ends RELRO on 4 KB.
for flag in max-page-size=16384 common-page-size=16384; do
  grep -Fq "\"-Wl,-z,$flag\"" "$repo/native/sim_kernels/SConstruct" ||
    { echo "FAIL: native/sim_kernels/SConstruct does not pass -Wl,-z,$flag on Android" >&2; failures=$((failures + 1)); }
done
if [ "$failures" -ne 0 ]; then
  echo "test-android-elf: $failures case(s) failed" >&2
  exit 1
fi
echo "test-android-elf: all cases passed"
