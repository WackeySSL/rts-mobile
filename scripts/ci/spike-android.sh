#!/usr/bin/env bash
# TEMPORARY P18 CI spike (deleted before the final commit): export once with the runner's SDK and
# JDK 17 and print everything that ADR 0005 only read from source.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
section() { printf '\n######## SPIKE: %s\n' "$*"; }

section "environment"
echo "JAVA_HOME=${JAVA_HOME:-unset} ANDROID_HOME=${ANDROID_HOME:-unset} ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-unset}"
"$JAVA_HOME/bin/java" -version 2>&1
echo "--- build-tools"; ls "$ANDROID_HOME/build-tools"
echo "--- platforms"; ls "$ANDROID_HOME/platforms"
echo "--- platform-tools"; ls "$ANDROID_HOME/platform-tools" | head -20
echo "--- templates"; ls -l ~/.local/share/godot/export_templates/4.7.2.stable
echo "--- editor settings dir before any Godot run"; ls -la ~/.config/godot 2>&1 | head

section "debug keystore"
ks="$RUNNER_TEMP/debug.keystore"
keytool -genkeypair -keystore "$ks" -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass android -keypass android -dname "CN=rts-mobile dev" 2>&1 | tail -3
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$ks" GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android

section "import"
godot --headless --path . --import 2>&1 | tail -5
echo "--- editor settings after import"; ls -la ~/.config/godot 2>&1 | head
grep -n -E "export/android" ~/.config/godot/editor_settings-4.7.tres 2>&1 || echo "(no export/android keys stored in editor_settings-4.7.tres)"

section "export (env only, no editor settings written)"
mkdir -p build/android && : > build/.gdignore
godot --headless --path . --export-debug Android build/android/spike.apk 2>&1 | tee "$RUNNER_TEMP/spike.log"
echo "godot exit: ${PIPESTATUS[0]}"
echo "--- lines about signing, build-tools, sdk"
grep -n -i -E "apksigner|build.tools|sdk|sign|keystore|java|warning|error" "$RUNNER_TEMP/spike.log" || true
echo "--- editor settings after export"
grep -n -E "export/android" ~/.config/godot/editor_settings-4.7.tres 2>&1 || echo "(no export/android keys stored in editor_settings-4.7.tres)"
ls -l build/android

section "apk contents"
apk=build/android/spike.apk
echo "size: $(stat -c %s "$apk") bytes, sha256 $(sha256sum "$apk" | cut -d' ' -f1)"
unzip -Z1 "$apk" | awk -F/ '{ print $1 "/" $2 }' | sort | uniq -c | sort -rn | head -40
echo "--- lib/"; unzip -l "$apk" | grep -E " lib/|\.pck|META-INF|AndroidManifest|classes|resources.arsc"
echo "--- anything with tests or gdUnit4 in the name"; unzip -Z1 "$apk" | grep -i -E "tests|gdunit" | head -20 || echo "(none)"
echo "--- first 40 assets/"; unzip -Z1 "$apk" | grep '^assets/' | head -40

section "apksigner"
for d in "$ANDROID_HOME"/build-tools/36.*; do
  echo "--- $d"
  "$d/apksigner" verify --verbose --print-certs "$apk" 2>&1 | head -30
done

section "manifest (aapt2 dump xmltree)"
latest="$(ls -d "$ANDROID_HOME"/build-tools/36.*/ | sort -V | tail -n 1)"
"${latest}aapt2" dump xmltree --file AndroidManifest.xml "$apk" 2>&1 | head -120
echo "--- badging"
"${latest}aapt2" dump badging "$apk" 2>&1 | head -30

section "second export WITHOUT JAVA_HOME and ANDROID_HOME in the environment (fresh editor settings)"
rm -f ~/.config/godot/editor_settings-4.7.tres
env -u JAVA_HOME -u ANDROID_HOME godot --headless --path . --export-debug Android build/android/spike2.apk 2>&1 | grep -n -i -E "java|sdk|android|error" | head
echo "exit: ${PIPESTATUS[0]}"
ls -l build/android
rm -f "$ks"
exit 0
