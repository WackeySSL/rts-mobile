#!/usr/bin/env bash
# Offline test of the AAB export (P410c, ADR 0040 sections 2 and 4): scripts/ci/check-aab.sh on fixture bundles, and
# scripts/export-android.sh --aab in a scratch git tree. Everything the real run needs from Google (the Android SDK,
# Gradle, Google's Maven) is a stub here, so this proves the script logic only: which commands run in which order,
# that project.godot is back to its committed state on every exit, the exit codes and the verdict of each check. What
# the real Godot, Gradle and bundletool print is the android-aab job's to prove.
# Part 1 (check-aab.sh): a good bundle passes; one failing bundle per check (package, debuggable, permission, screen
#   orientation, App ID not Google's test ID, no App ID, a missing library, another ABI, a test path, library bytes,
#   unsigned, ELF or alignment verdict, a bundletool jar of another SHA-256) and the usage errors.
# Part 2 (export-android.sh --aab): the Godot call, the plugin install before it, [editor_plugins] present during the
#   export and gone after it (also after a failed export, a failed check and a plugin that saves settings), a dirty
#   project.godot kept as it was, an existing [editor_plugins] refused, --release with --aab refused, the exit codes
#   4 (Gradle template missing or not the pinned one) and 5 (no release keystore), and the pin of the Gradle template.
# Needs: bash, git, zip, unzip, sha256sum, curl. ci.yml runs it in the verify job (the required check).
# Usage: bash scripts/ci/test-aab.sh      Exit: 0 all cases pass, 1 a case failed.
set -euo pipefail
for tool in git zip unzip sha256sum curl cmp; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "test-aab: $tool is missing (needed by this test)" >&2
    exit 3
  }
done
repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
root="$(mktemp -d)"
# A real-looking publisher ID, built at run time so that no tracked text holds it (P420's ad ID guard).
fake_pub="ca-app-pub-$(printf '%s%s' 1234567890 123456)"
trap 'rm -rf "${root:?}"' EXIT
failures=0
rc=0
out=""

check() { # name, wanted exit code, wanted text in the output (may be empty); uses rc and out
  if [ "$rc" = "$2" ] && { [ -z "$3" ] || grep -Fq -- "$3" <<<"$out"; }; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (wanted exit $2 and '$3', got exit $rc: $(tail -n 3 <<<"$out" | tr '\n' ' '))" >&2
    failures=$((failures + 1))
  fi
}
assert() { if "${@:2}"; then echo "ok: $1"; else echo "FAIL: $1" >&2; failures=$((failures + 1)); fi; }

mkdir -p "$root/bin" "$root/serve"
# ---------------------------------------------------------------- part 1: check-aab.sh
bt_name="bundletool-all-$(sed -n 's/^BT_VERSION="\(.*\)"$/\1/p' "$repo/scripts/ci/check-aab.sh").jar"
printf 'a stand-in for bundletool\n' >"$root/serve/$bt_name"
bt_sha="$(sha256sum <"$root/serve/$bt_name" | cut -d' ' -f1)"
cat >"$root/bin/jarsigner" <<'STUB'
#!/usr/bin/env bash
echo "${STUB_JARSIGNER_TEXT:-jar verified.}"
exit "${STUB_JARSIGNER_RC:-0}"
STUB
cat >"$root/bin/java" <<'STUB'
#!/usr/bin/env bash
echo "java $*" >>"${STUB_LOG:-/dev/null}"
case "$*" in
  *"dump manifest"*)
    [ -z "${STUB_BT_FAIL:-}" ] || { echo "bundletool: the bundle is broken" >&2; exit 1; }
    cat "$STUB_MANIFEST"
    ;;
  *) echo 'openjdk version "17.0.12" 2024-07-16' >&2 ;;
esac
STUB
chmod +x "$root/bin/jarsigner" "$root/bin/java"
cat >"$root/manifest.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    android:versionCode="1"
    package="dk.appcode.rts">
  <uses-permission android:name="android.permission.VIBRATE" />
  <uses-permission android:name="android.permission.INTERNET" />
  <uses-permission android:name="com.google.android.gms.permission.AD_ID" />
  <application android:label="Treadline">
    <meta-data
        android:name="com.google.android.gms.ads.APPLICATION_ID"
        android:value="ca-app-pub-3940256099942544~3347511713" />
    <activity
        android:name="com.godot.game.GodotApp"
        android:screenOrientation="fullUser" />
  </application>
</manifest>
XML

# A tree with the real check-aab.sh (its pin swapped for the stand-in's SHA-256) and a stub ELF checker that logs.
mkdir -p "$root/chk/scripts/ci" "$root/chk/assets/art/fonts/fam"
cp "$repo/scripts/ci/font-notice.sh" "$root/chk/scripts/ci/"
echo "SIL OFL stand-in" >"$root/chk/assets/art/fonts/fam/OFL.txt"
: >"$root/chk/assets/art/fonts/fam/Fam-Regular.ttf"
sed "s/^BT_SHA256=.*/BT_SHA256=\"$bt_sha\"/" "$repo/scripts/ci/check-aab.sh" >"$root/chk/scripts/ci/check-aab.sh"
cat >"$root/chk/scripts/ci/check-android-elf.sh" <<'STUB'
#!/usr/bin/env bash
echo "elf $*" >>"$STUB_LOG"
case "$1" in
  check) exit "${STUB_ELF_RC:-0}" ;;
  align) exit "${STUB_ALIGN_RC:-0}" ;;
esac
STUB
real_sha="$(sed -n 's/^BT_SHA256="\(.*\)"$/\1/p' "$repo/scripts/ci/check-aab.sh")"
[ "$real_sha" = "a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29" ] &&
  echo "ok: check-aab.sh pins bundletool 1.18.3 by its SHA-256" || { echo "FAIL: the bundletool pin is not 1.18.3's SHA-256" >&2; failures=$((failures + 1)); }

mkdir -p "$root/aab/base/lib/arm64-v8a" "$root/aab/base/assets/scenes" "$root/aab/base/manifest" "$root/aab/base/assets/assets/art/fonts/fam"
echo ofl >"$root/aab/base/assets/assets/art/fonts/fam/OFL.txt"
echo "banner ca-app-pub-3940256099942544/6300978111 is Google's test unit" >"$root/aab/base/assets/ids.txt"
echo engine >"$root/aab/base/lib/arm64-v8a/libgodot_android.so"
echo kernels >"$root/aab/base/lib/arm64-v8a/libsim_kernels.so"
echo libcxx >"$root/aab/base/lib/arm64-v8a/libc++_shared.so"
echo remap >"$root/aab/base/assets/scenes/main.tscn.remap"
echo proto >"$root/aab/base/manifest/AndroidManifest.xml"
mkdir -p "$root/built"
echo kernels >"$root/built/libsim_kernels.so"
bundle() { # NAME [EXTRA-FILE...]: the fixture as NAME.aab, with extra files (paths under aab/) added or, with -FILE, removed
  rm -rf "$root/v" && cp -R "$root/aab" "$root/v"
  local f
  for f in "$@"; do
    case "$f" in
      -*) rm -f "$root/v/${f#-}" ;;
      kernelz) echo kernelz >"$root/v/base/lib/arm64-v8a/libsim_kernels.so" ;;
      installtime) mkdir "$root/v/installTime" && mv "$root/v/base/assets" "$root/v/installTime/assets" ;;
      noassets) rm -rf "$root/v/base/assets" ;;
      realid) echo "unit $fake_pub/1111111111" >"$root/v/base/assets/ad_ids.cfg" ;;
      *) mkdir -p "$root/v/$(dirname "$f")" && echo x >"$root/v/$f" ;;
    esac
  done
  rm -f "$root/$1.aab"
  (cd "$root/v" && zip -q -r -D "$root/$1.aab" .)
}
chk() { # BUNDLE [VAR=value...]: runs check-aab.sh on BUNDLE.aab; the manifest is $root/manifest.xml unless MANIFEST is set
  local bundle="$1"
  shift
  : >"$root/chk.log"
  rc=0
  out="$(cd "$root/chk" && env -i PATH="$root/bin:$PATH" HOME="$root/home" BUNDLETOOL_DIR="$root/bt" \
    BUNDLETOOL_BASE_URL="file://$root/serve" STUB_MANIFEST="${MANIFEST:-$root/manifest.xml}" STUB_LOG="$root/chk.log" "$@" \
    bash scripts/ci/check-aab.sh "$root/$bundle.aab" "${NATIVE:-$root/built/libsim_kernels.so}" 2>&1)" || rc=$?
}
mutate() { sed "$1" "$root/manifest.xml" >"$root/m.xml"; MANIFEST="$root/m.xml"; }

bundle good
rm -rf "$root/bt"
chk good
check "a good bundle passes; bundletool is fetched" 0 "check-aab: OK $root/good.aab"
assert "the fetched bundletool is in place" test -s "$root/bt/$bt_name"
assert "the kernels library got the ELF checks and every library the alignment check" \
  grep -Eq "^elf check .*libsim_kernels\.so .*libc\+\+_shared\.so\$" "$root/chk.log"
assert "the alignment check ran on all three libraries" grep -Eq '^elf align (\S+\.so( |$)){3}$' "$root/chk.log"
assert "bundletool was asked for the manifest of this bundle, with the pinned jar" \
  grep -Fxq "java -jar $root/bt/$bt_name dump manifest --bundle=$root/good.aab" "$root/chk.log"
check "the permissions are printed" 0 "manifest permissions: android.permission.VIBRATE android.permission.INTERNET com.google.android.gms.permission.AD_ID"
chk good
check "a second run needs no download (the jar in place is verified again)" 0 "check-aab: OK"
printf 'tampered\n' >"$root/bt/$bt_name"
chk good
check "a tampered jar in place is replaced by a verified download" 0 "check-aab: OK"
assert "the replaced jar has the pinned SHA-256" test "$(sha256sum <"$root/bt/$bt_name" | cut -d' ' -f1)" = "$bt_sha"
printf 'another jar\n' >"$root/serve/$bt_name"
rm -rf "$root/bt"
chk good
check "a download with another SHA-256 is refused" 1 "SHA-256 mismatch for bundletool"
printf 'a stand-in for bundletool\n' >"$root/serve/$bt_name"

for spec in \
  "s/package=\"dk.appcode.rts\"/package=\"dk.appcode.rts.dev\"/|the manifest package is not dk.appcode.rts" \
  "s/<application /<application android:debuggable=\"true\" /|the manifest is debuggable" \
  "/permission.INTERNET/d|the manifest lacks the INTERNET permission" \
  "/permission.VIBRATE/d|the manifest lacks the VIBRATE permission" \
  "s/fullUser/portrait/|screenOrientation is not fullUser (13): android:screenOrientation=\"portrait\"" \
  "s/3347511713/1234567890/|is not Google's test App ID" \
  "/APPLICATION_ID/d|is not Google's test App ID (found: none)"; do
  mutate "${spec%%|*}"
  chk good
  check "manifest: ${spec#*|}" 1 "${spec#*|}"
done
MANIFEST="$root/manifest.xml"
sed 's/fullUser/13/' "$root/manifest.xml" >"$root/m.xml"
MANIFEST="$root/m.xml" chk good
check "screenOrientation 13 passes too" 0 "check-aab: OK"
unset MANIFEST

bundle nolib -base/lib/arm64-v8a/libc++_shared.so
chk nolib
check "a bundle without libc++_shared.so fails" 1 "the bundle lacks base/lib/arm64-v8a/libc++_shared.so"
bundle nokernels -base/lib/arm64-v8a/libsim_kernels.so
chk nokernels
check "a bundle without the kernels library fails" 1 "the bundle lacks base/lib/arm64-v8a/libsim_kernels.so"
bundle noengine -base/lib/arm64-v8a/libgodot_android.so
chk noengine
check "a bundle without the engine library fails" 1 "the bundle lacks base/lib/arm64-v8a/libgodot_android.so"
bundle abi base/lib/x86_64/libgodot_android.so
chk abi
check "a library for another ABI fails" 1 "libraries for other ABIs"
bundle gdunit base/assets/addons/gdUnit4/plugin.cfg
chk gdunit
check "a gdUnit4 path fails" 1 "the bundle holds test files: base/assets/addons/gdUnit4/plugin.cfg"
bundle tests base/assets/tests/sim/test_x.gd
chk tests
check "a tests/ path fails" 1 "the bundle holds test files"
bundle noscene -base/assets/scenes/main.tscn.remap
chk noscene
check "a bundle without the boot scene fails" 1 "the bundle lacks assets/scenes/main.tscn.remap in base/ or installTime/"
bundle instt installtime
chk instt
check "project files in installTime/assets pass" 0 "check-aab: OK"
bundle noasset noassets
chk noasset
check "a bundle with no */assets/ entry fails" 1 "the bundle has no */assets/ entry"
bundle idreal realid
chk idreal
check "an ad ID of another publisher in an asset fails" 1 "ad ID of a publisher other than Google's test one: $fake_pub"
bundle nofont -base/assets/assets/art/fonts/fam/OFL.txt
chk nofont
check "a bundle without a font's OFL.txt fails" 1 "the bundle lacks the font licence assets/assets/art/fonts/fam/OFL.txt"
bundle two -base/lib/arm64-v8a/libc++_shared.so base/assets/tests/x.gd
chk two
check "two faults: the first is reported" 1 "the bundle lacks base/lib/arm64-v8a/libc++_shared.so"
check "two faults: the second is reported too" 1 "the bundle holds test files"
bundle bytes kernelz
chk bytes
check "other kernels bytes than CI built fail" 1 "is not the library CI built"
chk good STUB_BT_FAIL=1
check "a failing bundletool is exit 1" 1 "bundletool dump manifest failed"
chk good JAVA_HOME="$root/nojdk"
check "no java is exit 3" 3 "java is missing"
mkdir -p "$root/jdk/bin"
cp "$root/bin/java" "$root/jdk/bin/java"
chk good JAVA_HOME="$root/jdk"
check "no jarsigner is exit 3" 3 "jarsigner is missing"
chk good STUB_JARSIGNER_TEXT="jar is unsigned."
check "an unsigned bundle fails" 1 "does not say 'jar verified'"
chk good STUB_JARSIGNER_RC=1
check "a failing jarsigner fails" 1 "jarsigner -verify failed"
chk good STUB_ELF_RC=1
check "a failing ELF check fails" 1 "fails the ELF checks above"
chk good STUB_ALIGN_RC=1
check "a failing alignment check fails" 1 "not 16 KB aligned"
NATIVE="$root/none.so" chk good
check "a missing built library is exit 1" 1 "the library CI built"
rc=0
out="$(cd "$root/chk" && bash scripts/ci/check-aab.sh one 2>&1)" || rc=$?
check "one argument is a usage error" 2 "usage:"

# ---------------------------------------------------------------- part 2: export-android.sh --aab
src_sum="$(sed -n 's/^ANDROID_SOURCE_SUM="\([0-9a-f]\{64\}\)  android_source\.zip"$/\1/p' "$repo/scripts/ci/install-godot.sh")"
assert "install-godot.sh pins android_source.zip by a 64-digit SHA-256" test -n "$src_sum"
mkdir -p "$root/jdk/bin" "$root/sdk/platform-tools" "$root/home/.local/share/godot/export_templates/4.7.2.stable" "$root/tmp"
cp "$root/bin/java" "$root/jdk/bin/java"
printf '#!/usr/bin/env bash\nexit 0\n' >"$root/sdk/platform-tools/adb"
chmod +x "$root/sdk/platform-tools/adb"
echo keystore >"$root/keystore"
templates="$root/home/.local/share/godot/export_templates/4.7.2.stable"
echo 4.7.2.stable >"$templates/version.txt"
echo "a stand-in for the Gradle template" >"$templates/android_source.zip"
tpl_sha="$(sha256sum <"$templates/android_source.zip" | cut -d' ' -f1)"
cat >"$root/bin/godot" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  --version*) echo "4.7.2.stable.official.0000000" ;;
  *"--export-release Android internal "*)
    echo "godot $*" >>"$STUB_LOG"
    cp project.godot "$STUB_LOG.project"
    [ -z "${STUB_REWRITE_PRESETS:-}" ] || printf '\n[preset.9]\n' >>export_presets.cfg
    [ -z "${STUB_PLUGIN_SAVES:-}" ] || printf '\n[admob]\n\n[admob/general]\nandroid/app_id="x"\nadmob/general/android/app_id="x"\n' >>project.godot
    [ -z "${STUB_EXPORT_RC:-}" ] || exit "$STUB_EXPORT_RC"
    [ -n "${STUB_NO_BUNDLE:-}" ] || echo "bundle" >"${!#}"
    ;;
  *) echo "godot $*" >>"$STUB_LOG" ;;
esac
STUB
chmod +x "$root/bin/godot"

new_tree() { # NAME: a git tree with the scripts, the licence folders and a committed project.godot
  local t="$root/$1" f
  mkdir -p "$t/scripts/ci" "$t/docs" "$t/native/bin" "$t/build"
  printf 'android.release.arm64 = "res://native/bin/libsim.release.so"\n' >"$t/native/sim_kernels.gdextension"
  echo kernels >"$t/native/bin/libsim.release.so"
  cp "$repo/scripts/export-android.sh" "$repo/scripts/seed-extension-list.sh" "$repo/scripts/build-native.sh" \
    "$repo/scripts/verify-allowlist.txt" "$t/scripts/"
  cp "$repo/scripts/ci/font-notice.sh" "$repo/scripts/ci/godot-cpp-notice.sh" "$t/scripts/ci/"
  sed "s/^ANDROID_SOURCE_SUM=.*/ANDROID_SOURCE_SUM=\"$tpl_sha  android_source.zip\"/" "$repo/scripts/ci/install-godot.sh" >"$t/scripts/ci/install-godot.sh"
  cp -R "$repo/docs/licenses" "$t/docs/licenses"
  while IFS= read -r f; do
    mkdir -p "$t/$(dirname "$f")"
    case "$f" in */OFL.txt) cp "$repo/$f" "$t/$f" ;; *) : >"$t/$f" ;; esac
  done < <(cd "$repo" && find assets/art/fonts -type f \( -name OFL.txt -o -iname '*.ttf' -o -iname '*.otf' -o -iname '*.woff' -o -iname '*.woff2' \))
  # Stubs of the two scripts that this test does not test here (the plugin installer, part 1's checker).
  printf '#!/usr/bin/env bash\necho "plugins installed" >>"$STUB_LOG"\nexit "${STUB_PLUGINS_RC:-0}"\n' >"$t/scripts/ci/install-android-plugins.sh"
  printf '#!/usr/bin/env bash\necho "check-aab $*" >>"$STUB_LOG"\nexit "${STUB_CHECK_RC:-0}"\n' >"$t/scripts/ci/check-aab.sh"
  printf '[application]\n\nconfig/name="x"\n\n[rendering]\n\nrenderer/rendering_method="gl_compatibility"\n' >"$t/project.godot"
  printf '[preset.0]\n\nname="Android internal"\n' >"$t/export_presets.cfg"
  printf 'build/\nandroid/\n' >"$t/.gitignore"
  (cd "$t" && git init -q . && git config user.email t@example.invalid && git config user.name t && git add -A && git commit -q -m init)
}
aab() { # TREE [VAR=value...] -- [script args]: runs export-android.sh in TREE; sets rc and out; the log is $root/TREE.log
  local t="$1" env_args=()
  shift
  while [ $# -gt 0 ] && [ "$1" != -- ]; do env_args+=("$1"); shift; done
  [ $# -eq 0 ] || shift
  : >"$root/$t.log"
  rc=0
  out="$(cd "$root/$t" && env -i PATH="$root/bin:$PATH" HOME="${STUB_HOME:-$root/home}" TMPDIR="$root/tmp" GODOT="$root/bin/godot" \
    JAVA_HOME="$root/jdk" ANDROID_HOME="$root/sdk" STUB_LOG="$root/$t.log" \
    GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$root/keystore" GODOT_ANDROID_KEYSTORE_RELEASE_USER=u GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=p \
    ${env_args[@]+"${env_args[@]}"} bash scripts/export-android.sh "$@" 2>&1)" || rc=$?
}
pristine() { assert "$1: project.godot equals its committed state" bash -c "cd '$root/$2' && git diff --quiet HEAD -- project.godot"; }

new_tree ok
aab ok -- --aab
check "--aab runs through with stub tools" 0 "export-android: OK build/android/rts-mobile-internal.aab"
assert "the bundle is where the script says" test -s "$root/ok/build/android/rts-mobile-internal.aab"
assert "the licence notice is written beside it" test -s "$root/ok/build/android/THIRD_PARTY_LICENSES.txt"
assert "godot got the template switch, the release export and the preset" \
  grep -Eq '^godot --headless --path \. --install-android-build-template --export-release Android internal .*/build/android/rts-mobile-internal\.aab$' "$root/ok.log"
assert "the plugin libraries were installed before the export" \
  bash -c "grep -n 'plugins installed\|^godot .*--export-release' '$root/ok.log' | head -n 1 | grep -q 'plugins installed'"
assert "no scratch folder is left behind" test -z "$(find "$root/tmp" -mindepth 1 -maxdepth 1 -type d)"
assert "during the export project.godot enabled the plugin" \
  grep -Fxq 'enabled=PackedStringArray("res://addons/admob/plugin.cfg")' "$root/ok.log.project"
assert "the check ran on the bundle and the release library" grep -Eq '^check-aab .*/rts-mobile-internal\.aab native/bin/libsim\.release\.so$' "$root/ok.log"
pristine "after a good run" ok

new_tree saves
mkdir -p "$root/saves/android/build" && echo stale >"$root/saves/android/build/old"
aab saves STUB_PLUGIN_SAVES=1 STUB_REWRITE_PRESETS=1 -- --aab
check "a plugin that saves settings is noted with a diff, and the run passes" 0 "the run rewrote project.godot"
check "the diff shows what the plugin wrote" 0 "> android/app_id=\"x\""
check "a rewrite of export_presets.cfg is noted too" 0 "the run rewrote export_presets.cfg"
pristine "after the plugin saved settings" saves
assert "export_presets.cfg is restored too" bash -c "cd '$root/saves' && git diff --quiet HEAD -- export_presets.cfg"
assert "a stale android/build is removed before the export" test ! -e "$root/saves/android/build/old"

new_tree nobundle
aab nobundle STUB_NO_BUNDLE=1 -- --aab
check "Godot exiting 0 without a bundle is exit 1" 1 "rts-mobile-internal.aab is missing or empty"
pristine "after a missing bundle" nobundle

new_tree nogit
rm -rf "$root/nogit/.git"
cp "$root/nogit/project.godot" "$root/nogit.before"
aab nogit -- --aab
check "outside a git work tree the run passes" 0 "OK build/android"
assert "and project.godot is back as it was" cmp -s "$root/nogit/project.godot" "$root/nogit.before"

new_tree failed
aab failed STUB_EXPORT_RC=134 -- --aab
check "a Godot crash is exit 1 and names #123712" 1 "exit code 134"
check "the crash message names the watch" 1 "godotengine/godot#123712"
pristine "after a Godot crash" failed

new_tree badcheck
aab badcheck STUB_CHECK_RC=1 -- --aab
check "a failing bundle check is exit 1" 1 "the bundle failed its checks"
pristine "after a failing bundle check" badcheck

new_tree noplugins
aab noplugins STUB_PLUGINS_RC=1 -- --aab
check "a failing plugin install is exit 1 and godot never exports" 1 "could not be installed"
assert "godot did not export" bash -c "! grep -q -- '--export-release' '$root/noplugins.log'"
pristine "after a failing plugin install" noplugins

new_tree dirty
printf '\n; an edit nobody committed\n' >>"$root/dirty/project.godot"
cp "$root/dirty/project.godot" "$root/dirty.before"
aab dirty -- --aab
check "an uncommitted project.godot is allowed" 0 "OK build/android"
assert "it is put back exactly as it was" cmp -s "$root/dirty/project.godot" "$root/dirty.before"

new_tree enabled
printf '\n[editor_plugins]\n\nenabled=PackedStringArray()\n' >>"$root/enabled/project.godot"
cp "$root/enabled/project.godot" "$root/enabled.before"
aab enabled -- --aab
check "an existing [editor_plugins] section is refused" 1 "already has an [editor_plugins] section (the committed file has none); remove it (git checkout -- project.godot) and rerun"
assert "and project.godot is untouched" cmp -s "$root/enabled/project.godot" "$root/enabled.before"

aab ok -- --aab --release
check "--aab with --release is a usage error" 2 "cannot be combined"
aab ok -- --release --aab
check "--release with --aab is a usage error too" 2 "cannot be combined"
aab ok GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD= -- --aab
check "no release keystore password is exit 5" 5 "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD is not set"
echo "something else" >"$templates/android_source.zip"
aab ok -- --aab
check "a Gradle template that is not the pinned one is exit 4" 4 "is not the pinned Gradle template"
rm "$templates/android_source.zip"
aab ok -- --aab
check "a missing Gradle template is exit 4" 4 "android_source.zip"
echo "a stand-in for the Gradle template" >"$templates/android_source.zip"
aab ok -- --aab --out ../x
check "--out outside build/ is still refused with --aab" 2 "contains '..'"
aab ok -- --nonsense
check "an unknown flag is exit 2 and the usage names --aab" 2 "[--release | --aab]"

assert "no scratch folder is left behind by any run" test -z "$(find "$root/tmp" -mindepth 1 -maxdepth 1 -type d)"
if [ "$failures" -ne 0 ]; then
  echo "test-aab: $failures case(s) failed" >&2
  exit 1
fi
echo "test-aab: all cases passed"
