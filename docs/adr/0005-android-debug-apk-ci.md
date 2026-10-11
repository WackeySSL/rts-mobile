# ADR 0005: Android debug APK in CI and Phase 1 delivery (boot scene, web preview, licences)

Status: accepted, 2026-10-10

## Context
Phase 1 asks for "Android debug APK as a CI artifact for testing on a real device". The web
preview (ADR 0002 §9) must keep working, so Michael can compare touch in the phone browser
with the native build. The Gradle build template and signing secrets belong to Phase 6
(AdMob plugin, Play upload). Phase 1 needs neither.

Facts:
- The Godot `4.7.2-stable` export plugin (`platform/android/export/export_plugin.cpp` and
  `export.cpp`), read on 2026-10-10:
  - Without Gradle, an APK export needs `android_debug.apk` from the export templates, a Java
    SDK (`export/android/java_sdk_path`, default `$JAVA_HOME`), and an Android SDK
    (`export/android/android_sdk_path`, default `$ANDROID_HOME`) that contains
    `platform-tools/adb` and `build-tools/<ver>/apksigner`. Godot prefers the build-tools
    version that equals the target SDK (default 36, minimum SDK 24).
  - Keystore options are `PROPERTY_USAGE_SECRET`. The editor stores them in
    `.godot/export_credentials.cfg`, never in `export_presets.cfg`. They can come from the
    environment: `GODOT_ANDROID_KEYSTORE_DEBUG_PATH`, `GODOT_ANDROID_KEYSTORE_DEBUG_USER` and
    `GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD`. Path, user and password must be set together or
    not at all.
  - ABI options are `architectures/<abi>`, and only `arm64-v8a` is on by default. The haptics
    permission is `permissions/vibrate`.
- The 4.7.2 `.tpz` lists `templates/android_debug.apk` at 127 260 725 bytes (125 834 876
  compressed). `scripts/ci/remote_zip.py` can range-fetch it like the web templates (listed on
  2026-10-10).
- The `ubuntu-24.04` runner image (README, 2026-10-10) ships JDK 17 as the default
  (`JAVA_HOME_17_X64`), `ANDROID_HOME=/usr/local/lib/android/sdk`, platform-tools 37.0.1 and
  build-tools 34.0.0 to 37.0.0, including 36.0.0.
- This cloud session's proxy refused `dl.google.com` (organisation policy), so the Android SDK
  cannot be installed in a cloud session. No Android export was run locally. The first CI run
  of the Android PR is the proof.
- The default Android launcher icon in the template is the Godot logo (CC BY 4.0, already
  credited for the web boot splash).

## Decision
1. **Non-Gradle debug APK, arm64 only.** Add the export preset `Android` (preset.1):
   - `export_path="build/android/rts-mobile-debug.apk"`, `custom_features=""` (a debug build
     enables the dev menu through `OS.is_debug_build()`), and the same `exclude_filter` as
     the Web preset.
   - Options: `gradle_build/use_gradle_build=false`, `architectures/arm64-v8a=true` with the
     three other ABIs false, `package/unique_name="dk.appcode.rts.dev"` (ADR 0006),
     `package/name="Treadline dev"`, `package/signed=true`,
     `permissions/vibrate=true` and `version/code=1`.
   - No keystore values are set in the file.
   - Orientation comes from the project setting (`sensor_landscape`).
2. **Templates.** `scripts/ci/install-godot.sh --android` also fetches
   `templates/android_debug.apk` by HTTP range. The file is checked by zip CRC and a pinned
   SHA-256, computed once by release-engineer from the official `.tpz`. It has its own
   `actions/cache` entry, so the web-only jobs keep their small cache.
3. **SDK and JDK from the runner image, checked rather than trusted.**
   - The Android job sets `JAVA_HOME=$JAVA_HOME_17_X64` and uses the image's `ANDROID_HOME`.
     Both are set before the job's first Godot run, because Godot copies them into new editor
     settings.
   - `scripts/export-android.sh` exits 4 and names the missing piece when `java` 17,
     `platform-tools/adb` or `build-tools/36.*/apksigner` is absent.
   - A runner-image change therefore fails loudly instead of signing with an unexpected tool.
4. **Debug keystore generated in CI, never committed.**
   - The job runs `keytool -genkeypair` into `$RUNNER_TEMP/debug.keystore` (alias
     `androiddebugkey`, store and key password `android`, the public Android debug defaults)
     and passes it through the three `GODOT_ANDROID_KEYSTORE_DEBUG_*` variables. The file is
     deleted in an `if: always()` step.
   - On `push` to `main`, and only there, the job uses the stable debug keystore from secrets
     instead, if Michael creates them: `ANDROID_DEBUG_KEYSTORE_BASE64` and
     `ANDROID_DEBUG_KEYSTORE_PASSWORD`. Without those secrets it falls back to a generated key
     and says so in the job summary.
   - A generated key changes every run, so each new APK must be installed after uninstalling
     the previous one. PR builds always use a generated key, so PR code never sees the secret.
5. **`scripts/export-android.sh [--out DIR]`** (default `build/android`):
   - Before exporting, in this order:
     - version check: exit 3 unless `4.7.2.stable`;
     - template and toolchain checks: exit 4;
     - keystore variables set and the keystore file present: exit 5;
     - `mkdir -p`, `build/.gdignore`, then delete stale artifacts.
   - Then `godot --headless --path . --export-debug Android <out>/rts-mobile-debug.apk`.
   - Scan this run's log with the shared error pattern and allowlist.
   - Each failed check exits 1:
     - the APK exists and is not empty;
     - `unzip -l` lists `lib/arm64-v8a/libgodot_android.so` and no other `lib/<abi>/`;
     - no `assets/tests/` or `assets/addons/gdUnit4/` path;
     - `apksigner verify --print-certs` passes;
     - `aapt2 dump xmltree` of the manifest shows the package id, `screenOrientation` 6
       (sensorLandscape) and the `VIBRATE` permission.
   - Write `<out>/THIRD_PARTY_LICENSES.txt` with the same content as the web build's.
   - Print `export-android: OK <path>`. Exit 2 on a usage error.
6. **CI.**
   - `ci.yml` gains a job `android-debug-apk`: `needs: verify`, `ubuntu-24.04`,
     `permissions: contents: read`, timeout 30 min.
   - It uploads the artifact `rts-mobile-debug-apk-<sha>` (APK and licences, 14 days,
     `if-no-files-found: error`).
   - It runs the same clean-tree check as `verify`.
   - Its job summary shows the APK size, SHA-256, signing key kind (generated or stable) and
     install steps.
   - A second job `android-dev-release` runs only on `push` to `main` (`needs:
     android-debug-apk`, `permissions: contents: write`). It replaces the pre-release
     `android-dev-latest` with the APK, the licences and the commit SHA in the notes, in the
     same pattern as `toolchain-mirror.yml`. Michael gets one stable phone URL:
     `https://github.com/WackeySSL/rts-mobile/releases/download/android-dev-latest/rts-mobile-debug.apk`.
     This job needs Michael's consent before it merges (project instructions: release
     workflows).
   - Neither job is a required check in Phase 1. `verify` stays the only one.
7. **Cloud sessions do not build APKs.** `toolchain-mirror.yml` and `scripts/cloud/setup.sh`
   are unchanged. Run locally without the SDK, `export-android.sh` exits 4 and names what is
   missing.
8. **Delivery.** `scenes/main.tscn` stays the boot scene for every build. In Phase 1 it is the
   controls test map. `preview.yml` and `export-web.sh` are unchanged. Every PR keeps its web
   preview. The Dev button (debug builds and the web preview) still opens the dev menu, which
   gains "Touch probe" (ADR 0004).

## Consequences
- No secret or repository setting is required for the Phase 1 boxes. The two keystore secrets
  are optional; they only make APK updates install in place.
- The APK is a public build of the engine binary, so it always ships with
  `THIRD_PARTY_LICENSES.txt` in the artifact and the release, and `assets/CREDITS.md` names the
  Godot logo as the debug launcher icon.
- The Android job adds about 126 MB to the Actions cache and a few minutes per CI run. A cache
  hit is logged as in the `verify` job.
- A Godot or runner-image bump re-checks the build-tools selection, the template hash and the
  manifest checks.
- Phase 6 replaces this preset's signing with the release keystore and switches to the Gradle
  build for the AdMob plugin. The release package id is `dk.appcode.rts` (ADR 0006), and the `.dev` id
  stays separate so both can be installed side by side.

## Amendment (2026-10-11, P18 CI run)
Two facts above were corrected by the first real export
(https://github.com/WackeySSL/rts-mobile/actions/runs/38118498895):
- Godot 4.7.2 writes `screenOrientation` 11 (`userLandscape`) for the project's
  `sensor_landscape`, not 6. `scripts/export-android.sh` checks for 11.
- The Android job uses one combined cache entry (editor, web and Android debug templates) of
  about 222 MB, not an extra 126 MB next to the web cache.
- Godot picked `build-tools/36.0.0/apksigner` (target SDK 36) from the runner image and read
  `JAVA_HOME` and `ANDROID_HOME` from the environment; no editor settings had to be written.

## Amendment (2026-10-11, P19)
- The rolling pre-release is published by the job `android-dev-release` in `ci.yml` through
  `scripts/ci/publish-dev-release.sh`. It runs only on a push to `refs/heads/main` of the
  repository itself (never for pull requests, forks or `workflow_dispatch`), after
  `android-debug-apk`, with `contents: write` on that job only and its own concurrency group.
- It reuses the APK artifact of the same run, deletes and recreates the `android-dev-latest`
  pre-release so the tag moves to the new commit (a few seconds of 404 on the stable URL), and
  then checks that the stable URL serves the same SHA-256. A re-run of an older main run does
  not roll the release back to an older commit.
- The release notes name the commit and whether the stable debug key signed the APK.
- `scripts/ci/test-publish-dev-release.sh` tests the script offline against a stub `gh` and
  `curl`; `tests/project/test_ci_workflow.gd` pins the job condition and permissions.
- The repository setting "Immutable releases" must stay off, or recreating the tag is refused.
