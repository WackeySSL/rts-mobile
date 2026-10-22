#!/usr/bin/env bash
# Offline test of the licence notices and the packed-library checks of export-web.sh and export-android.sh
# (P26l, P55a2, ADR 0005 section 5, ADR 0013 sections 10 and 11). It runs both real scripts in a temp copy of
# scripts/ and docs/licenses/, against stub godot, java, apksigner, aapt2, readelf and nm on PATH, so no Godot,
# Android SDK, token or network is touched. It checks that each script writes a THIRD_PARTY_LICENSES.txt that
# ends with the unchanged libc++ LICENSE.TXT and then the godot-cpp LICENSE.md, that the two notices agree line
# for line after their header line, that the tags they name and the SHA-256 of the libc++ licence are the ones
# the README and build-native.sh record, and that each script exits 1 when either licence file is missing or
# empty. For export-android.sh it checks that the APK's library holds the built bytes, that libc++_shared.so is
# required, that a failing ELF check fails the export and, from the stubs' log, which files the checks and the
# description ran on. For export-android.sh --release (P51r, the perf APK of the gate) it checks the preset and
# the template it exports with, the release keystore variables, the library entry android.release.arm64 and the
# three checks of that mode: not debuggable, the dev_menu feature in the pack and the release template's engine
# library. ci.yml runs it in android-debug-apk, next to the offline test of publish-dev-release.sh.
# Needs: bash, zip, unzip, strings (binutils), sha256sum.
# Usage: bash scripts/ci/test-export-notices.sh      Exit: 0 all cases pass, 1 a case failed.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
root="$(mktemp -d)"
trap 'rm -rf "${root:?}"' EXIT
failures=0
libcxx="docs/licenses/llvm-libc++"
license="$repo/$libcxx/LICENSE.TXT"

pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

# Stubs. The Godot stub writes what each script checks after its export: the web artifacts with
# threads off and the dev_menu feature in the pack, or an APK with the files the checks look for.
mkdir -p "$root/bin" "$root/tmp" "$root/jdk/bin" "$root/sdk/platform-tools" "$root/sdk/build-tools/36.0.0" \
  "$root/apk/lib/arm64-v8a" "$root/apk/assets/scenes"
cat >"$root/bin/godot" <<'STUB'
#!/usr/bin/env bash
# Every headless editor start needs the seeded extension list when the project has a .gdextension; the
# real Godot 4.7.2 aborts with exit 134 without it (ADR 0013 section 9).
if [ "$1" != "--version" ] && [ -f native/sim_kernels.gdextension ] && ! grep -Fq res://native/sim_kernels.gdextension .godot/extension_list.cfg 2>/dev/null; then
  echo "stub godot: started without the seeded extension list" >&2
  exit 134
fi
case "$*" in
  --version*) echo "4.7.2.stable.official.0000000" ;;
  *"--export-release Web "*)
    dir="$(dirname "${!#}")"
    printf 'const GODOT_THREADS_ENABLED = false;\n' >"$dir/index.html"
    echo js >"$dir/index.js"
    echo wasm >"$dir/index.wasm"
    printf 'project\n_custom_features\ndev_menu\n%s\n' "$STUB_PCK_EXTRA" >"$dir/index.pck"
    ;;
  *"--export-debug Android "* | *"--export-release Android perf "*)
    echo "$ANDROID_HOME/build-tools/36.0.0/apksigner sign --ks stub"
    cp "$STUB_APK" "${!#}"
    ;;
esac
STUB
cat >"$root/jdk/bin/java" <<'STUB'
#!/usr/bin/env bash
echo 'openjdk version "17.0.12" 2024-07-16' >&2
STUB
cat >"$root/sdk/build-tools/36.0.0/aapt2" <<'STUB'
#!/usr/bin/env bash
if [ "$2" = badging ]; then
  echo "package: name='dk.appcode.rts.dev' versionCode='1' versionName=''"
  case "$STUB_DEBUGGABLE" in badging | all) echo "application-debuggable" ;; esac
  exit 0
fi
case "$STUB_DEBUGGABLE" in xmltree | all) echo 'A: http://schemas.android.com/apk/res/android:debuggable(0x0101000f)=true' ;; esac
echo 'A: package="dk.appcode.rts.dev"'
echo "A: http://schemas.android.com/apk/res/android:screenOrientation(0x0101001e)=${STUB_ORIENTATION:-13}"
echo 'A: http://schemas.android.com/apk/res/android:name="android.permission.VIBRATE"'
STUB
printf '#!/usr/bin/env bash\nexit 0\n' | tee "$root/sdk/platform-tools/adb" >"$root/sdk/build-tools/36.0.0/apksigner"
chmod +x "$root/bin/godot" "$root/jdk/bin/java" "$root/sdk/build-tools/36.0.0/"* "$root/sdk/platform-tools/adb"
echo so >"$root/apk/lib/arm64-v8a/libgodot_android.so"
echo remap >"$root/apk/assets/scenes/main.tscn.remap"
# The kernels library of the debug export (tree() writes its .gdextension entry and the built copy) and libc++.
native="libsim_kernels.android.template_debug.arm64.so"
native_release="libsim_kernels.android.template_release.arm64.so"
echo kernels >"$root/apk/lib/arm64-v8a/$native"
echo libcxx >"$root/apk/lib/arm64-v8a/libc++_shared.so"
# readelf and nm answer by the content of the file they are given (scripts/ci/test-android-elf.sh tests the checks
# on real ELF files): "kernels" is a good arm64 library whose PT_LOAD alignment STUB_ALIGN sets, "libcxx" defines
# what the kernels library imports, and any other file (the template's "so") has 16 KB alignment and no symbols.
# Each call is logged to STUB_LOG with that content, so the test sees which file a tool was asked about.
cat >"$root/bin/readelf" <<'STUB'
#!/usr/bin/env bash
file="${!#}"
[ -f "$file" ] || { echo "readelf: Error: '$file': No such file" >&2; exit 1; }
what="$(cat "$file")"
echo "readelf $* <$what>" >>"$STUB_LOG"
case "$1:$what" in
  -h:kernels) printf '  Machine:   AArch64\n  Type:      DYN (Shared object file)\n' ;;
  -d:kernels) echo ' 0x01 (NEEDED)   Shared library: [libc++_shared.so]' ;;
  -lW:kernels) printf '  LOAD      0x0 0x0 0x0 0x10 0x10 R %s\n  GNU_RELRO 0x0 0xfed8 0xfed8 0x128 0x128 R 0x1\n' "$STUB_ALIGN" ;;
  -lW:*) printf '  LOAD      0x0 0x0 0x0 0x10 0x10 R 0x4000\n' ;;
  -p:so) printf "String dump of section '.note.android.ident':\n  [     0]  Android\n  [     8]  r29\n  [    18]  14206865\n" ;;
  -p:libcxx) printf "String dump of section '.note.android.ident':\n  [     0]  Android\n  [     8]  r28\n  [    18]  13004108\n" ;;
esac
STUB
cat >"$root/bin/nm" <<'STUB'
#!/usr/bin/env bash
file="${!#}"
[ -f "$file" ] || { echo "nm: '$file': No such file" >&2; exit 1; }
what="$(cat "$file")"
echo "nm $* <$what>" >>"$STUB_LOG"
case "$*:$what" in
  *--defined-only*:kernels) echo "0000000000001000 T sim_kernels_library_init" ;;
  *--defined-only*:libcxx) echo "0000000000002000 T _ZdlPv" ;;
  *--undefined-only*:kernels) echo "                 U _ZdlPv" ;;
esac
STUB
chmod +x "$root/bin/readelf" "$root/bin/nm"
(cd "$root/apk" && zip -q -r -D "$root/stub.apk" lib assets)
variant() { # NAME [FILE]: stub.apk as NAME.apk, with FILE (under apk/) removed, or with other bytes in the kernels library
  rm -rf "$root/v" && cp -R "$root/apk" "$root/v"
  # "kernelz" is as long as "kernels": a size-only comparison would pass it.
  if [ -n "${2:-}" ]; then rm "$root/v/$2"; else echo kernelz >"$root/v/lib/arm64-v8a/$native"; fi
  (cd "$root/v" && zip -q -r -D "$root/$1.apk" lib assets)
}
variant badbytes
variant nocxx lib/arm64-v8a/libc++_shared.so
variant nolib "lib/arm64-v8a/$native"
# The perf APK of the release export (P51r): the release library instead of the debug one, and the project settings
# that carry the custom features (assets/project.binary). The engine library "so" must be the release template's.
rapk() { # NAME [ENGINE-LIBRARY-BYTES [FEATURE]]: the release APK as NAME.apk
  rm -rf "$root/r" && cp -R "$root/apk" "$root/r"
  rm "$root/r/lib/arm64-v8a/$native"
  echo kernels >"$root/r/lib/arm64-v8a/$native_release"
  echo "${2:-so}" >"$root/r/lib/arm64-v8a/libgodot_android.so"
  printf 'project\n_custom_features\n%s\n' "${3:-dev_menu}" >"$root/r/assets/project.binary"
  (cd "$root/r" && zip -q -r -D "$root/$1.apk" lib assets)
}
rapk release
rapk release-wrong-engine sa
rapk release-no-feature so other
mkdir -p "$root/tpl/lib/arm64-v8a"
echo so >"$root/tpl/lib/arm64-v8a/libgodot_android.so"
(cd "$root/tpl" && zip -q -r -D "$root/android_release.apk" lib)
echo keystore >"$root/keystore"
for dir in "$root/home/.local/share/godot/export_templates/4.7.2.stable" \
  "$root/home/Library/Application Support/Godot/export_templates/4.7.2.stable"; do
  mkdir -p "$dir"
  for name in version.txt web_nothreads_debug.zip web_nothreads_release.zip android_debug.apk; do
    echo stub >"$dir/$name"
  done
  cp "$root/android_release.apk" "$dir/android_release.apk"
done
cp -R "$root/home" "$root/home-no-release"
rm "$root/home-no-release/.local/share/godot/export_templates/4.7.2.stable/android_release.apk"

# tree NAME: a copy of the scripts and licence folders under $root/NAME. The scripts change into
# the folder above their own, so they read and write inside the copy.
tree() {
  mkdir -p "$root/$1/scripts/ci" "$root/$1/docs" "$root/$1/native/bin"
  printf 'android.debug.arm64 = "res://native/bin/%s"\nandroid.release.arm64 = "res://native/bin/%s"\n' "$native" "$native_release" \
    >"$root/$1/native/sim_kernels.gdextension"
  echo kernels >"$root/$1/native/bin/$native"
  echo kernels >"$root/$1/native/bin/$native_release"
  cp "$repo/scripts/export-web.sh" "$repo/scripts/export-android.sh" "$repo/scripts/seed-extension-list.sh" \
    "$repo/scripts/build-native.sh" "$repo/scripts/verify-allowlist.txt" "$root/$1/scripts/"
  cp "$repo/scripts/ci/check-android-elf.sh" "$repo/scripts/ci/godot-cpp-notice.sh" "$root/$1/scripts/ci/"
  cp -R "$repo/docs/licenses" "$root/$1/docs/licenses"
}

# run NAME web|android|release: runs the export script in the tree NAME (release: export-android.sh --release, with the
# release keystore variables unless NO_RELEASE_KEYS is set) and sets rc and out.
run() {
  rc=0
  : >"$root/$1.stub.log"
  script="$2" args="" apk="$root/stub.apk" keys=()
  if [ "$2" = release ]; then
    script=android args=--release apk="$root/release.apk"
    if [ -z "${NO_RELEASE_KEYS:-}" ]; then
      keys=(GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$root/keystore" GODOT_ANDROID_KEYSTORE_RELEASE_USER=u GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=p)
    fi
  fi
  out="$(cd "$root/$1" && env -i PATH="$root/bin:$PATH" HOME="${STUB_HOME:-$root/home}" TMPDIR="$root/tmp" GODOT="$root/bin/godot" \
    JAVA_HOME="$root/jdk" ANDROID_HOME="$root/sdk" STUB_APK="${STUB_APK:-$apk}" STUB_ALIGN="${STUB_ALIGN:-0x4000}" \
    STUB_PCK_EXTRA="${STUB_PCK_EXTRA:-}" STUB_DEBUGGABLE="${STUB_DEBUGGABLE:-}" STUB_ORIENTATION="${STUB_ORIENTATION:-}" STUB_LOG="$root/$1.stub.log" \
    GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$root/keystore" GODOT_ANDROID_KEYSTORE_DEBUG_USER=u \
    GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=p ${keys[@]+"${keys[@]}"} bash "scripts/export-$script.sh" $args 2>&1)" || rc=$?
}

# (1) Both scripts run through with the stubs and write a notice that ends with the godot-cpp licence, after
# libc++'s (ADR 0013 section 11).
tree ok
cpp_tag="$(sed -n 's/^GODOT_CPP_TAG="\(.*\)"$/\1/p' "$repo/scripts/build-native.sh")"
cpp_sha="$(sed -n 's/^GODOT_CPP_SHA="\(.*\)"$/\1/p' "$repo/scripts/build-native.sh")"
cpp_dir="docs/licenses/godot-cpp-${cpp_tag#godot-}"
cpp_license="$repo/$cpp_dir/LICENSE.md"
cpp_size="$(wc -c <"$cpp_license" | tr -d ' ')"
size="$(wc -c <"$license" | tr -d ' ')"
sha="$(sha256sum "$license" | cut -d' ' -f1)"
for kind in web android; do
  run ok "$kind"
  if [ "$kind" = android ]; then android_out="$out"; fi
  notice="$root/ok/build/$kind/THIRD_PARTY_LICENSES.txt"
  if [ "$rc" != 0 ] || [ ! -s "$notice" ]; then
    fail "$kind: the export did not run through (exit $rc): $(tail -n 3 <<<"$out")"
    continue
  fi
  pass "$kind: the export runs through with stub tools"
  # The godot-cpp section ends the notice (a blank line, a rule, the title line and a rule come before its text).
  title="$(grep -n '^godot-cpp .*: LICENSE\.md$' "$notice" | cut -d: -f1 || true)"
  if [ -n "$title" ] && head -n $((title - 3)) "$notice" | tail -c "$size" | cmp -s - "$license"; then
    pass "$kind: the libc++ LICENSE.TXT, unchanged, ends the notice before the godot-cpp section"
  else
    fail "$kind: the libc++ LICENSE.TXT does not end right before the godot-cpp section"
  fi
  if tail -c "$cpp_size" "$notice" | cmp -s - "$cpp_license"; then
    pass "$kind: the notice ends with the godot-cpp LICENSE.md, unchanged"
  else
    fail "$kind: the notice does not end with the godot-cpp LICENSE.md"
  fi
  if grep -Fxq "godot-cpp $cpp_tag (commit $cpp_sha): LICENSE.md" "$notice"; then
    pass "$kind: the notice names the godot-cpp tag and commit that build-native.sh pins"
  else
    fail "$kind: the godot-cpp title does not name $cpp_tag and $cpp_sha of build-native.sh"
  fi
  grep -Fq 'Godot Engine 4.7.2-stable: COPYRIGHT.txt' "$notice" || fail "$kind: Godot's COPYRIGHT.txt is gone from the notice"
  tag="$(sed -n 's/^LLVM libc++ \(llvmorg-[0-9.]*\): LICENSE\.TXT$/\1/p' "$notice")"
  if [ -n "$tag" ] && grep -Fxq -- "- Tag: \`$tag\`" "$repo/$libcxx/README.md"; then
    pass "$kind: the notice names $tag, the tag the licence README records"
  else
    fail "$kind: the tag in the notice ('$tag') is missing or not the one in $libcxx/README.md"
  fi
done
grep -Fq "$sha" "$repo/$libcxx/README.md" && pass "the README records the SHA-256 of LICENSE.TXT" ||
  fail "$libcxx/README.md does not record the SHA-256 $sha of LICENSE.TXT"

# (2) ADR 0005 section 5: the APK's notice has the same content as the web build's. Only the
# header line names the build.
if cmp -s <(tail -n +2 "$root/ok/build/web/THIRD_PARTY_LICENSES.txt") \
  <(tail -n +2 "$root/ok/build/android/THIRD_PARTY_LICENSES.txt"); then
  pass "the two notices agree after their header line"
else
  fail "the web and Android notices differ after their header line"
fi

# (2b) ADR 0013 section 10: the checks ran on the right files. The stubs logged each call with the content of its
# file (kernels, libcxx or so): the library as the APK packs it (never the built copy) first and the APK's
# libc++_shared.so second, and the template's libraries were described, with their notes in the export's output.
packed='/export-android-native\.[^/]*/lib/arm64-v8a'
for call in "readelf -h .*$packed/$native <kernels>" "readelf -lW .*$packed/$native <kernels>" \
  "readelf -d .*$packed/$native <kernels>" "nm -D --defined-only .*$packed/$native <kernels>" \
  "nm -D --undefined-only .*$packed/$native <kernels>" "nm -D --defined-only .*$packed/libc\+\+_shared\.so <libcxx>" \
  "readelf -p .note.android.ident .*$packed/libgodot_android\.so <so>" "readelf -p .note.android.ident .*$packed/libc\+\+_shared\.so <libcxx>"; do
  if grep -Eq -- "^$call\$" "$root/ok.stub.log"; then
    base="${call##*/}"
    pass "android: the stubs were asked '${call%% .*}' about ${base//\\/}"
  else
    fail "android: the stubs were not asked '$call' (log: $(tr '\n' ';' <"$root/ok.stub.log"))"
  fi
done
# The notes of the real Godot 4.7.2 template: libgodot_android.so is built with NDK r29 (29.0.14206865), and the NDK
# r29 ships a libc++_shared.so that is stamped r28 (28.0.13004108).
for spec in "libgodot_android.so:r29 14206865" "libc++_shared.so:r28 13004108"; do
  name="${spec%%:*}"
  if grep -Fq "check-android-elf: $name: .note.android.ident: Android ${spec#*:} ; PT_LOAD align: 0x4000" <<<"$android_out"; then
    pass "android: the export prints the .note.android.ident and PT_LOAD alignment of the template's $name"
  else
    fail "android: the export output lacks the description of the template's $name"
  fi
done

# (3) A missing or empty libc++ or godot-cpp licence file stops each script with exit 1 and a message that names it.
for kind in web android; do
  for file in "$libcxx/LICENSE.TXT" "$cpp_dir/LICENSE.md"; do
    for state in missing empty; do
      name="$kind-$state-$(basename "$file")"
      tree "$name"
      if [ "$state" = missing ]; then rm "$root/$name/$file"; else : >"$root/$name/$file"; fi
      run "$name" "$kind"
      if [ "$rc" = 1 ] && grep -Fq "$file is missing or empty" <<<"$out"; then
        pass "$kind: exit 1 when $file is $state"
      else
        fail "$kind: wanted exit 1 and '$file is missing or empty' with the file $state, got exit $rc: $(tail -n 1 <<<"$out")"
      fi
    done
  done
done

# (4) ADR 0013 section 7: a .gdextension in the web pack (the Web preset must exclude native/*) stops
# export-web.sh with exit 1, which the engine itself only warns about. The pack holds the generated
# file's comment line (it mentions .gdextension) before the path, and the message must quote the path.
tree web-native
STUB_PCK_EXTRA=$'; build has no .gdextension and loads no library. Do not edit.\nres://native/sim_kernels.gdextension' run web-native web
if [ "$rc" = 1 ] && grep -Fq "must exclude native/*): res://native/sim_kernels.gdextension" <<<"$out"; then
  pass "web: exit 1 when the pack holds a .gdextension, and the message quotes its path"
else
  fail "web: wanted exit 1 and 'the pack holds a .gdextension (...): res://native/sim_kernels.gdextension', got exit $rc: $(tail -n 1 <<<"$out")"
fi

# (5) ADR 0013 section 10: export-android.sh checks the library of its export mode. Each case changes one thing
# about the APK, the tree or the ELF facts the stubs report.
native_case() { # TREE WANTED-EXIT WANTED-TEXT, with STUB_APK or STUB_ALIGN in the environment
  tree "$1"
  run "$1" android
  if [ "$rc" = "$2" ] && grep -Fq -- "$3" <<<"$out"; then
    pass "android: $1"
  else
    fail "android: $1 (wanted exit $2 and '$3', got exit $rc: $(tail -n 2 <<<"$out" | tr '\n' ' '))"
  fi
}
native_case "the packed library is the one CI built" 0 "export-android: lib/arm64-v8a/$native is the library CI built"
STUB_APK="$root/badbytes.apk" native_case "the APK's library is not the built one" 1 "is not the library CI built"
STUB_APK="$root/nocxx.apk" native_case "the APK lacks libc++_shared.so" 1 "the APK lacks lib/arm64-v8a/libc++_shared.so"
STUB_APK="$root/nolib.apk" native_case "the APK lacks the library" 1 "the APK lacks lib/arm64-v8a/$native"
STUB_ALIGN=0x1000 native_case "the ELF checks fail on a 4 KB aligned library" 1 "p_align below 0x4000"
# ADR 0015 section 7 (P64): the manifest must say fullUser (13). A landscape lock (11, userLandscape) or the plain
# sensor value (6) means the project setting or the engine's mapping changed, and the build would not turn.
STUB_ORIENTATION=11 native_case "a landscape-locked manifest (11) fails" 1 "the manifest screenOrientation is not 13 (fullUser)"
STUB_ORIENTATION=6 native_case "a manifest with the plain sensor value (6) fails" 1 "the manifest screenOrientation is not 13 (fullUser)"
tree no-entry
: >"$root/no-entry/native/sim_kernels.gdextension"
run no-entry android
if [ "$rc" = 4 ] && grep -Fq "no android.debug.arm64 entry in native/sim_kernels.gdextension" <<<"$out"; then
  pass "android: exit 4 when the .gdextension has no android.debug.arm64 entry"
else
  fail "android: wanted exit 4 and 'no android.debug.arm64 entry', got exit $rc: $(tail -n 1 <<<"$out")"
fi
tree no-built
rm "$root/no-built/native/bin/$native"
run no-built android
if [ "$rc" = 4 ] && grep -Fq "bash scripts/build-native.sh --platform android --arch arm64 --target template_debug" <<<"$out"; then
  pass "android: exit 4 when the library was not built, and the message says how"
else
  fail "android: wanted exit 4 and the build-native.sh command, got exit $rc: $(tail -n 1 <<<"$out")"
fi

# (6) P51r: export-android.sh --release exports the preset "Android perf" with the release template, the release keystore
# and the library entry android.release.arm64, and then runs the checks of that mode. Each case changes one thing.
release_case() { # TREE WANTED-EXIT WANTED-TEXT, with STUB_APK, STUB_DEBUGGABLE, STUB_HOME or NO_RELEASE_KEYS in the environment
  tree "$1"
  run "$1" release
  if [ "$rc" = "$2" ] && grep -Fq -- "$3" <<<"$out"; then
    pass "release: $1"
  else
    fail "release: $1 (wanted exit $2 and '$3', got exit $rc: $(tail -n 2 <<<"$out" | tr '\n' ' '))"
  fi
}
release_case "the perf APK is exported and checked" 0 "export-android: OK build/android/rts-mobile-perf-release.apk"
grep -Fq "release template confirmed: not debuggable, dev_menu packed" <<<"$out" ||
  fail "release: the output does not say that the release template is confirmed"
grep -Fq "lib/arm64-v8a/$native_release is the library CI built" <<<"$out" ||
  fail "release: the packed library is not the release one ($native_release)"
perf="$root/the perf APK is exported and checked/build/android"
[ ! -e "$perf/rts-mobile-debug.apk" ] || fail "release: a debug APK was written"
if head -n 1 "$perf/THIRD_PARTY_LICENSES.txt" | grep -Fxq "rts-mobile Android perf (release template) build: third-party licences" &&
  cmp -s <(tail -n +2 "$root/ok/build/web/THIRD_PARTY_LICENSES.txt") <(tail -n +2 "$perf/THIRD_PARTY_LICENSES.txt"); then
  pass "release: the notice names the perf build and agrees with the web build's after its header line"
else
  fail "release: the notice header or content is wrong"
fi
STUB_DEBUGGABLE=badging release_case "a debuggable badging fails" 1 "the APK is debuggable"
STUB_DEBUGGABLE=xmltree release_case "a debuggable manifest dump fails" 1 "the manifest is debuggable"
STUB_APK="$root/release-no-feature.apk" release_case "a pack without the dev_menu feature fails" 1 "the APK lacks the dev_menu custom feature"
STUB_APK="$root/release-wrong-engine.apk" release_case "an engine library that is not the release template's fails" 1 "is not the one of the release template"
STUB_APK="$root/stub.apk" release_case "a debug-library APK fails the packed-library check" 1 "the APK lacks lib/arm64-v8a/$native_release"
STUB_HOME="$root/home-no-release" release_case "the release template is required" 4 "android_release.apk"
NO_RELEASE_KEYS=1 release_case "the release keystore variables are required" 5 "GODOT_ANDROID_KEYSTORE_RELEASE_PATH is not set"
tree release-no-built
rm "$root/release-no-built/native/bin/$native_release"
run release-no-built release
if [ "$rc" = 4 ] && grep -Fq "bash scripts/build-native.sh --platform android --arch arm64 --target template_release" <<<"$out"; then
  pass "release: exit 4 when the release library was not built, and the message says how"
else
  fail "release: wanted exit 4 and the template_release build command, got exit $rc: $(tail -n 1 <<<"$out")"
fi
# The debug export runs none of those checks: the dev APK is debuggable and has no dev_menu feature in its pack.
STUB_DEBUGGABLE=all native_case "the debug export does not run the release checks" 0 "export-android: OK build/android/rts-mobile-debug.apk"

if [ "$failures" -ne 0 ]; then
  echo "test-export-notices: $failures case(s) failed" >&2
  exit 1
fi
echo "test-export-notices: all cases passed"
