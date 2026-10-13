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
(cd "$root/apk" && zip -q -r -D "$root/stub.apk" lib assets)
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
  mkdir -p "$root/$1/scripts" "$root/$1/docs"
  cp "$repo/scripts/export-web.sh" "$repo/scripts/export-android.sh" "$repo/scripts/seed-extension-list.sh" \
    "$repo/scripts/verify-allowlist.txt" "$root/$1/scripts/"
  cp -R "$repo/docs/licenses" "$root/$1/docs/licenses"
}

# run NAME web|android: runs the export script in the tree NAME and sets rc and out.
run() {
  rc=0
  out="$(cd "$root/$1" && env -i PATH="$root/bin:$PATH" HOME="$root/home" TMPDIR="$root/tmp" GODOT="$root/bin/godot" \
    JAVA_HOME="$root/jdk" ANDROID_HOME="$root/sdk" STUB_APK="$root/stub.apk" STUB_PCK_EXTRA="${STUB_PCK_EXTRA:-}" \
    GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$root/keystore" GODOT_ANDROID_KEYSTORE_DEBUG_USER=u \
    GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=p bash "scripts/export-$2.sh" 2>&1)" || rc=$?
}

# (1) Both scripts run through with the stubs and write a notice that ends with the licence file.
tree ok
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
  if tail -c "$size" "$notice" | cmp -s - "$license"; then
    pass "$kind: the notice ends with the libc++ LICENSE.TXT, unchanged"
  else
    fail "$kind: the notice does not end with the libc++ LICENSE.TXT"
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

# (3) A missing or empty libc++ file stops each script with exit 1 and a message that names it.
for kind in web android; do
  for state in missing empty; do
    tree "$kind-$state"
    if [ "$state" = missing ]; then rm "$root/$kind-$state/$libcxx/LICENSE.TXT"; else : >"$root/$kind-$state/$libcxx/LICENSE.TXT"; fi
    run "$kind-$state" "$kind"
    if [ "$rc" = 1 ] && grep -Fq "$libcxx/LICENSE.TXT is missing or empty" <<<"$out"; then
      pass "$kind: exit 1 when the libc++ file is $state"
    else
      fail "$kind: wanted exit 1 and 'is missing or empty' with the libc++ file $state, got exit $rc: $(tail -n 1 <<<"$out")"
    fi
  done
done

# (4) ADR 0013 section 7: a .gdextension in the web pack (the Web preset must exclude native/*) stops
# export-web.sh with exit 1, which the engine itself only warns about.
tree web-native
STUB_PCK_EXTRA=res://native/sim_kernels.gdextension run web-native web
if [ "$rc" = 1 ] && grep -Fq "the pack holds a .gdextension" <<<"$out"; then
  pass "web: exit 1 when the pack holds a .gdextension"
else
  fail "web: wanted exit 1 and 'the pack holds a .gdextension', got exit $rc: $(tail -n 1 <<<"$out")"
fi

if [ "$failures" -ne 0 ]; then
  echo "test-export-notices: $failures case(s) failed" >&2
  exit 1
fi
echo "test-export-notices: all cases passed"
