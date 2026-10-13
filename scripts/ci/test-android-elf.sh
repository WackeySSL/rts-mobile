#!/usr/bin/env bash
# Offline test of scripts/ci/check-android-elf.sh (P55a2, ADR 0013 sections 8 and 10) on ELF fixtures that gcc
# builds here: a good library, fake libc++_shared.so and libc.so files, and one failing variant per check and per
# branch of the libc++ symbol rule. The fixtures have the host's machine unless a case patches e_machine; the real
# arm64 run is the Android job's. Every case runs with GNU binutils and with llvm-readelf and llvm-nm: the NDK's
# in ANDROID_NDK_ROOT, else (a developer machine) the ones on PATH. The llvm half prints which tools it ran and is
# skipped without any; under CI (the CI variable is set) it takes the NDK's only and fails without them, because
# install-ndk.sh has installed the NDK in an earlier step.
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

src() { # OUT SPEC...: writes $root/OUT.c. d:SYM defines a function, v:SYM a variable, u:SYM references a function,
  # w:SYM references it weakly, e:NAME names the exported function that calls every reference.
  local c="$root/$1.c" n=0 calls="" fn="" spec attr
  shift
  : >"$c"
  for spec in "$@"; do
    n=$((n + 1))
    attr=""
    case "$spec" in
      d:*) printf 'void f%d(void) __asm__("%s");\nvoid f%d(void) {}\n' "$n" "${spec#*:}" "$n" >>"$c" ;;
      v:*) printf 'int v%d __asm__("%s") = 1;\n' "$n" "${spec#*:}" >>"$c" ;;
      u:* | w:*)
        if [ "${spec%%:*}" = w ]; then attr=" __attribute__((weak))"; fi
        printf 'extern void f%d(void) __asm__("%s")%s;\n' "$n" "${spec#*:}" "$attr" >>"$c"
        calls="$calls f$n();"
        ;;
      e:*) fn="${spec#*:}" ;;
    esac
  done
  if [ -n "$fn" ]; then printf 'void %s(void) {%s }\n' "$fn" "$calls" >>"$c"; fi
}
page16="-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384"
so() { # OUT "SPEC..." [flags and libraries after the source: --as-needed keeps only the libraries it uses]
  src "$1" $2
  gcc -shared -nostdlib -fPIC -Wl,-z,relro $page16 "$root/$1.c" "${@:3}" -o "$root/$1"
}
poke() { # SRC DST OFFSET VALUE: DST is SRC with the two bytes at OFFSET set to VALUE (little endian), for ELF64 fields below 64 KB
  cp "$1" "$2"
  printf "$(printf '\\x%02x\\x%02x' $(($4 & 255)) $((($4 >> 8) & 255)))" | dd of="$2" bs=1 seek="$3" conv=notrunc 2>/dev/null
}

# The fake libc++_shared.so defines one symbol of each branch of the libc++ rule, the narrow one an unrelated symbol,
# and the importing one only references what it should define. The fake libc.so is versioned like bionic's.
std=_ZNSt6__ndk16stringC1Ev
unk=_ZNSt6__ndk16stringD1Ev
rule=("$std" __cxa_pure_virtual __gxx_personality_v0 __dynamic_cast __emutls_get_address)
bionic=(__cxa_atexit __cxa_finalize __cxa_thread_atexit_impl)
mkdir -p "$root/narrow" "$root/imp" "$root/ver" "$root/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
soname=-Wl,-soname,libc++_shared.so
so libc++_shared.so "d:${rule[0]} d:${rule[1]} d:${rule[2]} d:${rule[3]} d:${rule[4]}" "$soname"
so narrow/libc++_shared.so "d:_ZdlPv" "$soname"
so imp/libc++_shared.so "d:_ZdlPv u:$unk e:unused" "$soname"
printf 'LIBCXX_1 { global: *; };\n' >"$root/ver.map"
so ver/libc++_shared.so "d:$std" "$soname" -Wl,--version-script="$root/ver.map"
printf 'LIBC { global: %s; %s; %s; };\n' "${bionic[@]}" >"$root/libc.map" # bionic versions its symbols: nm prints __cxa_atexit@LIBC
so libc.so "d:${bionic[0]} d:${bionic[1]} d:${bionic[2]}" -Wl,-soname,libc.so -Wl,--version-script="$root/libc.map"
so libextra.so "d:extra" -Wl,-soname,libextra.so
cxx="$root/libc++_shared.so"
use="e:$entry u:$std u:${bionic[0]} u:${bionic[1]} u:${bionic[2]}"
so good.so "$use" "$root/libc.so" "$cxx"
so 4k.so "$use" -Wl,-z,max-page-size=4096 -Wl,-z,common-page-size=4096 "$root/libc.so" "$cxx"
so norelro.so "$use" -Wl,-z,norelro "$root/libc.so" "$cxx"
so nocxx.so "$use" "$root/libc.so"
so extra.so "$use" "$root/libc.so" -Wl,--no-as-needed "$root/libextra.so" "$cxx"
so noentry.so "e:other u:$std" "$cxx"
so dataentry.so "v:$entry" # the entry as a data object, not a function
so oldentry.so "d:${entry}_old" # a longer name that starts with the entry
so unknown.so "e:$entry u:$unk" "$cxx"
so mixed.so "e:$entry u:$std u:$unk" "$cxx"
so weak.so "e:$entry w:$unk" # a weak reference is no import
so prefix.so "e:$entry u:_ZdlPvm" -Wl,--no-as-needed "$cxx" # sized delete: starts like _ZdlPv, which the narrow libc++ defines
so versioned.so "e:$entry u:$std" "$root/ver/libc++_shared.so"
for i in 0 1 2 3 4; do so "rule$i.so" "e:$entry u:${rule[$i]}" "$cxx"; done
src rel "e:$entry" "u:$std"
gcc -c -fPIC "$root/rel.c" -o "$root/rel.o"
echo text >"$root/notelf.so"
mkdir "$root/notelf"
cp "$root/notelf.so" "$root/notelf/libc++_shared.so"
printf '#!/bin/sh\necho "stub NDK tool" >&2\nexit 7\n' | tee "$root/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf" >"$root/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm"
chmod +x "$root"/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/*

machine="$(readelf -h "$root/good.so" | sed -n 's/^ *Machine: *//p')"
loads="$(readelf -lW "$root/good.so" | awk '$1 == "LOAD" { c++ } END { print c }')"
aligns="$(printf '0x4000 %.0s' $(seq "$loads"))"
phoff="$(readelf -h "$root/good.so" | sed -n 's/^ *Start of program headers: *\([0-9]*\).*$/\1/p')"
phdr() { # TYPE FIELD-OFFSET [last]: the file offset of a field of the first (or last) program header of that type (56 bytes each)
  local index
  index="$(readelf -lW "$root/good.so" | awk -v type="$1" -v last="${3:-}" '/^ +[A-Z_]+ +0x/ { if ($1 == type && (last != "" || !found)) { i = n; found = 1 } n++ } END { print i }')"
  echo $((phoff + index * 56 + $2))
}
# RELRO end on a 4 KB boundary but not a 16 KB one (what LLD makes without -z common-page-size=16384): add 0x1000 to
# p_memsz (offset 40) of the PT_GNU_RELRO header.
at="$(phdr GNU_RELRO 40)"
memsz="$(od -An -t u8 -j "$at" -N 8 "$root/good.so" | tr -d ' ')"
poke "$root/good.so" "$root/relro.so" "$at" $((memsz + 4096))
poke "$root/good.so" "$root/mixedalign.so" "$(phdr LOAD 48 last)" 4096 # p_align (offset 48) of the last PT_LOAD: 4 KB, the others 16 KB
poke "$root/good.so" "$root/arm64.so" 18 183 # e_machine: EM_AARCH64, whatever the host is
poke "$root/4k.so" "$root/x86-4k.so" 18 62   # EM_X86_64, and 4 KB aligned too
printf '\x08\0\0\0\x08\0\0\0\x01\0\0\0Android\0\x1d\0\0\0r29\0' >"$root/note.bin"
objcopy --add-section .note.android.ident="$root/note.bin" "$root/good.so" "$root/noted.so"

pick_llvm() { # NDK-BIN: sets llvm_readelf and llvm_nm to the tools the llvm half runs, or to paths that are no tools.
  # The NDK's first: they are what check-android-elf.sh and export-android.sh run, and a runner image or a developer
  # machine has other LLVM versions on PATH (18 here, against the NDK's 21). PATH serves a developer machine without
  # an NDK only; under CI the NDK is required, because install-ndk.sh ran in an earlier step.
  llvm_readelf="$1/llvm-readelf"
  llvm_nm="$1/llvm-nm"
  if [ -z "${CI:-}" ] && { [ ! -x "$llvm_readelf" ] || [ ! -x "$llvm_nm" ]; }; then
    llvm_readelf="$(command -v llvm-readelf || echo none)"
    llvm_nm="$(command -v llvm-nm || echo none)"
  fi
}
selects() { # NAME WANTED CI NDK-BIN PATH: pick_llvm in a subshell with that CI value and PATH
  local got
  got="$(
    CI="$3"
    PATH="$5"
    pick_llvm "$4"
    echo "$llvm_readelf $llvm_nm"
  )"
  if [ "$got" = "$2" ]; then
    echo "ok: select: $1"
  else
    echo "FAIL: select: $1 (wanted '$2', got '$got')" >&2
    failures=$((failures + 1))
  fi
}
stub_bin="$root/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
mkdir -p "$root/pathtools" "$root/nopathtools"
printf '#!/bin/sh\n' | tee "$root/pathtools/llvm-readelf" >"$root/pathtools/llvm-nm"
chmod +x "$root"/pathtools/*
selects "the NDK's tools win over the ones on PATH" "$stub_bin/llvm-readelf $stub_bin/llvm-nm" "" "$stub_bin" "$root/pathtools:$PATH"
selects "the NDK's tools win over the ones on PATH under CI" "$stub_bin/llvm-readelf $stub_bin/llvm-nm" 1 "$stub_bin" "$root/pathtools:$PATH"
selects "PATH serves a machine without an NDK" "$root/pathtools/llvm-readelf $root/pathtools/llvm-nm" "" "$root/nondk/bin" "$root/pathtools:$PATH"
selects "no NDK and no tools on PATH leave nothing to run" "none none" "" "$root/nondk/bin" "$root/nopathtools"
selects "CI never falls back to PATH" "$root/nondk/bin/llvm-readelf $root/nondk/bin/llvm-nm" 1 "$root/nondk/bin" "$root/pathtools:$PATH"

m=(--machine "$machine")
ndk_bin="${ANDROID_NDK_ROOT:-/nonexistent}/toolchains/llvm/prebuilt/linux-x86_64/bin"
for flavour in gnu llvm; do
  label="$flavour"
  tools=()
  if [ "$flavour" = llvm ]; then
    pick_llvm "$ndk_bin"
    if [ ! -x "$llvm_readelf" ] || [ ! -x "$llvm_nm" ]; then
      if [ -n "${CI:-}" ]; then
        echo "FAIL: llvm: llvm-readelf and llvm-nm are not in ANDROID_NDK_ROOT ('${ANDROID_NDK_ROOT:-}'), and CI installs the NDK" >&2
        failures=$((failures + 1))
      else
        echo "skip: llvm: llvm-readelf and llvm-nm are on neither PATH nor in ANDROID_NDK_ROOT"
      fi
      continue
    fi
    echo "llvm tools: $llvm_readelf, $("$llvm_readelf" --version | sed -n 's/^.*LLVM version /LLVM /p')"
    tools=(READELF="$llvm_readelf" NM="$llvm_nm")
  fi
  t "a good library passes, with the entry symbol of build-native.sh" 0 "OK good.so: $machine shared object, exports $entry, needs libc.so libc++_shared.so, $loads PT_LOAD" "${m[@]}" "$root/good.so" "$cxx"
  check "bionic's __cxa_ symbols are no libc++ symbols" 0 ", 1 libc++ symbol(s) defined by libc++_shared.so"
  t "AArch64 is the default machine" 0 "OK arm64.so: AArch64 shared object" "$root/arm64.so" "$cxx"
  t "an object file is no shared object" 1 "is not a shared object" "${m[@]}" "$root/rel.o" "$cxx"
  t "a text file is no ELF file" 1 "is not an ELF file" "${m[@]}" "$root/notelf.so" "$cxx"
  t "a 4 KB aligned PT_LOAD" 1 "$loads of $loads PT_LOAD segments have p_align below 0x4000 (16 KB pages)" "${m[@]}" "$root/4k.so" "$cxx"
  t "one PT_LOAD of the others 16 KB aligned is 4 KB" 1 "1 of $loads PT_LOAD segments have p_align below 0x4000" "${m[@]}" "$root/mixedalign.so" "$cxx"
  t "a RELRO end on a 4 KB boundary only" 1 "PT_GNU_RELRO ends at 0x11000, not on a 0x4000 boundary" "${m[@]}" "$root/relro.so" "$cxx"
  t "no PT_GNU_RELRO" 1 "has no PT_GNU_RELRO segment" "${m[@]}" "$root/norelro.so" "$cxx"
  t "libc++ symbols without libc++_shared.so NEEDED" 1 "uses libc++ symbols but libc++_shared.so is not NEEDED" "${m[@]}" "$root/nocxx.so" "$cxx"
  t "a NEEDED library the phone cannot resolve" 1 "needs libextra.so, which neither Android nor Godot's template provides" "${m[@]}" "$root/extra.so" "$cxx"
  t "no entry symbol" 1 "does not export the entry symbol $entry" "${m[@]}" "$root/noentry.so" "$cxx"
  t "an entry that is a data object" 1 "does not export the entry symbol $entry" "${m[@]}" "$root/dataentry.so" "$cxx"
  t "an entry name that only starts with the entry" 1 "does not export the entry symbol $entry" "${m[@]}" "$root/oldentry.so" "$cxx"
  t "--entry-symbol names another entry" 0 "exports other" "${m[@]}" --entry-symbol other "$root/noentry.so" "$cxx"
  t "every failing check is reported: the machine" 1 "is not a 'AArch64' ELF file" "$root/x86-4k.so" "$cxx"
  check "every failing check is reported: the alignment" 1 "PT_LOAD segments have p_align below 0x4000"
  t "a libc++ symbol that libc++_shared.so does not define" 1 "uses 1 libc++ symbol(s) that libc++_shared.so does not define, first: $unk" "${m[@]}" "$root/unknown.so" "$cxx"
  t "every libc++ symbol is checked, not the first" 1 "uses 1 libc++ symbol(s) that libc++_shared.so does not define, first: $unk" "${m[@]}" "$root/mixed.so" "$cxx"
  t "a weak reference is no import" 0 "OK weak.so: $machine shared object, exports $entry, needs nothing" "${m[@]}" "$root/weak.so" "$cxx"
  t "the version suffix of libc++_shared.so's symbols is cut" 0 "OK versioned.so" "${m[@]}" "$root/versioned.so" "$root/ver/libc++_shared.so"
  for i in 0 1 2 3 4; do
    t "${rule[$i]} is a libc++ symbol, defined" 0 "OK rule$i.so: $machine shared object, exports $entry, needs libc++_shared.so" "${m[@]}" "$root/rule$i.so" "$cxx"
    t "${rule[$i]} is a libc++ symbol, not defined" 1 "uses 1 libc++ symbol(s) that libc++_shared.so does not define, first: ${rule[$i]}" "${m[@]}" "$root/rule$i.so" "$root/narrow/libc++_shared.so"
  done
  t "a libc++ symbol is defined by its whole name, not by a prefix" 1 "first: _ZdlPvm" "${m[@]}" "$root/prefix.so" "$root/narrow/libc++_shared.so"
  t "libc++_shared.so's own imports are no definitions" 1 "first: $unk" "${m[@]}" "$root/unknown.so" "$root/imp/libc++_shared.so"
  t "nm fails on a libc++_shared.so that is no ELF file" 1 "failed on libc++_shared.so" "${m[@]}" "$root/good.so" "$root/notelf/libc++_shared.so"
  t "nm fails on a libc++_shared.so that is missing" 1 "failed on libc++_shared.so" "${m[@]}" "$root/good.so" "$root/nothing/libc++_shared.so"
  t "check needs both files" 2 "usage: check" "${m[@]}" "$root/good.so"
  run describe
  check "describe needs a file" 2 "describe needs at least one file"
  run describe "$root/noted.so" "$root/good.so"
  check "describe prints the .note.android.ident strings and the PT_LOAD alignment, no verdict" 0 "noted.so: .note.android.ident: Android r29 ; PT_LOAD align: $aligns"
  check "describe goes on when a file has no note" 0 "good.so: .note.android.ident: none; PT_LOAD align: $aligns"
done

# A missing tool is exit 3, never a pass, and the NDK's llvm tools are the default (the stubs in ANDROID_NDK_ROOT
# fail with exit 7) unless READELF and NM name others.
label=tools
tools=(READELF=/nonexistent/readelf)
t "readelf missing" 3 "readelf is missing" "${m[@]}" "$root/good.so" "$cxx"
tools=(NM=/nonexistent/nm)
t "nm missing" 3 "nm is missing" "${m[@]}" "$root/good.so" "$cxx"
tools=(ANDROID_NDK_ROOT="$root/ndk")
t "the llvm tools of ANDROID_NDK_ROOT are the default" 1 "stub NDK tool" "${m[@]}" "$root/good.so" "$cxx"
tools=(ANDROID_NDK_ROOT="$root/ndk" READELF=readelf NM=nm)
t "READELF and NM override the NDK's tools" 0 "OK good.so" "${m[@]}" "$root/good.so" "$cxx"

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
