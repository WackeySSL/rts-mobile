#!/usr/bin/env bash
# Offline test of the licence notices of export-web.sh and export-android.sh (P26l, ADR 0005
# section 5). It runs both real scripts in a temp copy of scripts/ and docs/licenses/, against stub
# godot, java, apksigner and aapt2 on PATH, so no Godot, Android SDK, token or network is touched.
# It checks that each script writes a THIRD_PARTY_LICENSES.txt that ends with the unchanged libc++
# LICENSE.TXT, that the two notices agree line for line after their header line, that the tag they
# name and the SHA-256 of the licence file are the ones docs/licenses/llvm-libc++/README.md records,
# and that each script exits 1 when the libc++ file is missing or empty. ci.yml runs it in
# android-debug-apk, next to the offline test of publish-dev-release.sh.
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
  *"--export-debug Android "*)
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
echo 'A: package="dk.appcode.rts.dev"'
echo 'A: http://schemas.android.com/apk/res/android:screenOrientation(0x0101001e)=11'
echo 'A: http://schemas.android.com/apk/res/android:name="android.permission.VIBRATE"'
STUB
printf '#!/usr/bin/env bash\nexit 0\n' | tee "$root/sdk/platform-tools/adb" >"$root/sdk/build-tools/36.0.0/apksigner"
chmod +x "$root/bin/godot" "$root/jdk/bin/java" "$root/sdk/build-tools/36.0.0/"* "$root/sdk/platform-tools/adb"
echo so >"$root/apk/lib/arm64-v8a/libgodot_android.so"
echo remap >"$root/apk/assets/scenes/main.tscn.remap"
# The kernels library of the debug export (tree() writes its .gdextension entry and the built copy) and libc++.
native="libsim_kernels.android.template_debug.arm64.so"
echo kernels >"$root/apk/lib/arm64-v8a/$native"
echo libcxx >"$root/apk/lib/arm64-v8a/libc++_shared.so"
# readelf and nm answer as if every file were a good arm64 library (scripts/ci/test-android-elf.sh tests the
# checks on real ELF files); STUB_ALIGN sets the PT_LOAD alignment they report.
cat >"$root/bin/readelf" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  -h) printf '  Machine:   AArch64\n  Type:      DYN (Shared object file)\n' ;;
  -lW) printf '  LOAD      0x0 0x0 0x0 0x10 0x10 R %s\n  GNU_RELRO 0x0 0xfed8 0xfed8 0x128 0x128 R 0x1\n' "$STUB_ALIGN" ;;
  -d) echo ' 0x01 (NEEDED)   Shared library: [libc++_shared.so]' ;;
esac
STUB
cat >"$root/bin/nm" <<'STUB'
#!/usr/bin/env bash
case "$*" in *--undefined-only*) ;; *) echo "0000000000001000 T sim_kernels_library_init" ;; esac
STUB
chmod +x "$root/bin/readelf" "$root/bin/nm"
(cd "$root/apk" && zip -q -r -D "$root/stub.apk" lib assets)
variant() { # NAME [FILE]: stub.apk as NAME.apk, with FILE (under apk/) removed, or with the kernels library changed
  rm -rf "$root/v" && cp -R "$root/apk" "$root/v"
  if [ -n "${2:-}" ]; then rm "$root/v/$2"; else echo other >"$root/v/lib/arm64-v8a/$native"; fi
  (cd "$root/v" && zip -q -r -D "$root/$1.apk" lib assets)
}
variant badbytes
variant nocxx lib/arm64-v8a/libc++_shared.so
variant nolib "lib/arm64-v8a/$native"
echo keystore >"$root/keystore"
for dir in "$root/home/.local/share/godot/export_templates/4.7.2.stable" \
  "$root/home/Library/Application Support/Godot/export_templates/4.7.2.stable"; do
  mkdir -p "$dir"
  for name in version.txt web_nothreads_debug.zip web_nothreads_release.zip android_debug.apk; do
    echo stub >"$dir/$name"
  done
done

# tree NAME: a copy of the scripts and licence folders under $root/NAME. The scripts change into
# the folder above their own, so they read and write inside the copy.
tree() {
  mkdir -p "$root/$1/scripts/ci" "$root/$1/docs" "$root/$1/native/bin"
  printf 'android.debug.arm64 = "res://native/bin/%s"\n' "$native" >"$root/$1/native/sim_kernels.gdextension"
  echo kernels >"$root/$1/native/bin/$native"
  cp "$repo/scripts/export-web.sh" "$repo/scripts/export-android.sh" "$repo/scripts/seed-extension-list.sh" \
    "$repo/scripts/build-native.sh" "$repo/scripts/verify-allowlist.txt" "$root/$1/scripts/"
  cp "$repo/scripts/ci/check-android-elf.sh" "$repo/scripts/ci/godot-cpp-notice.sh" "$root/$1/scripts/ci/"
  cp -R "$repo/docs/licenses" "$root/$1/docs/licenses"
}

# run NAME web|android: runs the export script in the tree NAME and sets rc and out.
run() {
  rc=0
  out="$(cd "$root/$1" && env -i PATH="$root/bin:$PATH" HOME="$root/home" TMPDIR="$root/tmp" GODOT="$root/bin/godot" \
    JAVA_HOME="$root/jdk" ANDROID_HOME="$root/sdk" STUB_APK="${STUB_APK:-$root/stub.apk}" STUB_ALIGN="${STUB_ALIGN:-0x4000}" \
    STUB_PCK_EXTRA="${STUB_PCK_EXTRA:-}" \
    GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$root/keystore" GODOT_ANDROID_KEYSTORE_DEBUG_USER=u \
    GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=p bash "scripts/export-$2.sh" 2>&1)" || rc=$?
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
  notice="$root/ok/build/$kind/THIRD_PARTY_LICENSES.txt"
  if [ "$rc" != 0 ] || [ ! -s "$notice" ]; then
    fail "$kind: the export did not run through (exit $rc): $(tail -n 3 <<<"$out")"
    continue
  fi
  pass "$kind: the export runs through with stub tools"
  # The godot-cpp section ends the notice (a blank line, a rule, the title line and a rule come before its text).
  title="$(grep -n '^godot-cpp .*: LICENSE\.md$' "$notice" | cut -d: -f1)"
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

if [ "$failures" -ne 0 ]; then
  echo "test-export-notices: $failures case(s) failed" >&2
  exit 1
fi
echo "test-export-notices: all cases passed"
