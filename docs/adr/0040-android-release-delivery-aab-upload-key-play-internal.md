# ADR 0040: Android delivery: a signed AAB on every push to `main`, to Play internal testing

**In short, for Michael:** after each merge to `main`, GitHub builds the Play version of Treadline
(`dk.appcode.rts`), signs it with an upload key that only GitHub holds, and sends it to Google
Play's internal testing track, where your phone installs it from the Play Store. Google keeps the
real app signing key (Play App Signing). A few steps only you can do in Play Console and AdMob come
first; the plan lists them (M1-M11). The dev and perf APKs stay as they are.

Status: **proposed, 2026-11-15**. Written by the architect (row P400, branch
`claude/p400-phase6-plan`, base `main` at a2204d2) with the plan
`docs/plans/2026-11-15-phase-6.md`. Fix 1 the same day: the lead's docs lens. **Answered by
Michael on 2026-11-15** (in chat, through the Phase 6 lead): all A, so the plan's questions 8, 10,
12 and 13 are decided as written below (Play App Signing with his upload key and backup; the real
App ID with Google's test units in internal builds; an upload on every merge to `main`;
versionCode from the commit count). The status stays proposed until the main lead accepts it when
merging P400; P400b writes the acceptance notes. AppCode ApS already has a Play organisation
account (Michael, 2026-11-15; plan M1 done).

Amends (dated notes in P400b, after acceptance):
- ADR 0005's Consequences ("Phase 6 replaces this preset's signing with the release keystore and
  switches to the Gradle build for the AdMob plugin"): the debug preset `Android` and the
  `Android perf` preset keep their non-Gradle build, signing and `.dev` id; a new preset does the
  Play build (§1). ADR 0005 §6's consent rule applies to `android-internal.yml`: Michael gave it
  on 2026-11-15 (answer 12 A: upload every merge to `main` to internal testing); the PR still
  merges on his word.
- ADR 0013's "Not covered" note on godotengine/godot #123712 (a 4.7.2 shutdown crash after an
  export with AdMob and gdUnit4 installed): P410 is the row that watches for it (§4).
- `.claude/agents/release-engineer.md` says "sign the AAB with the release keystore from
  secrets" (§3 signs with an upload key; Google holds the app key) and "versionCode comes from the
  run number" (§6 chooses another source). Michael chose both (answer 13 A); the lead changes the
  agent file to the plan's draft text, pending Michael's yes to the text. Agents never edit it.

## Context
- `export_presets.cfg` has `Web`, `Android` (debug, `dk.appcode.rts.dev`, non-Gradle) and
  `Android perf` (release template, `.dev` id, generated key). `scripts/export-android.sh` builds
  APKs only and checks them (library bytes, libc++, ELF, licences, manifest).
- `ci.yml` builds the debug and perf APKs and publishes two rolling pre-releases. No workflow
  holds a store key; `android-internal.yml` does not exist.
- Plugins need Godot's Gradle build (`mobile-development` skill, §1); an AAB, mandatory for new
  Play apps, needs it too. `/android/build/` is already git-ignored.
- ADR 0006 fixes the release id `dk.appcode.rts` and the title "Treadline: Offline RTS". Play locks
  the id at the first upload, internal testing included.
- Cloud sessions cannot reach Google's Maven: their proxy refuses `dl.google.com` (ADR 0005,
  Context), which serves it. So Gradle exports run in CI only.

## Decision

### 1. A fourth preset, `Android internal`
`dk.appcode.rts`, name "Treadline", Gradle build on, export format AAB, `arm64-v8a` only, custom
feature `play` (ADR 0039 §2's AdMob mode), the AdMob and billing plugins on, permissions vibrate
and internet (and what the plugins merge: `AD_ID`, `BILLING`, network state; P410 lists the final
manifest). The exclude filter is the debug preset's (never `native/*`). No keystore value in the
file (`test_export_presets.gd` already pins that). The Web preset excludes `addons/admob/*` and
the billing plugin's folder. With the plugins enabled in the project, `Android` and `Android perf`
must still export unchanged (no plugin, no Gradle): **to confirm in P410**; if not, their
`exclude_filter` gains the plugin folders, pinned in `test_export_presets.gd`.

### 2. The Gradle template and the plugins, by pin
- CI installs Godot 4.7.2's Gradle template into `android/build/` from the export templates
  (the command line switch is **to confirm in P410**); it is never committed.
- `scripts/ci/install-android-plugins.sh` fetches the Poing Android libraries and the billing AAR
  by URL, version and SHA-256 (the godot-cpp pattern); the editor parts are vendored under
  `addons/` with a `addons/THIRD_PARTY.md` row each (version, tag, commit, licence). Upgrades only
  through a new ADR.
- Gradle's caches use `actions/cache` keyed on the template version and the plugin pins.

### 3. Play App Signing and the upload key
- Google holds the app signing key (Play App Signing, answer 8 A). Michael makes an **upload key**
  himself (`keytool`, RSA 2048) and keeps a backup offline. Store and key password are the same: the
  `mobile-development` skill (§1) says Godot's preset needs that ("keystore and key passwords must
  currently match"); **to confirm in P412**.
- CI holds only the upload key, in the GitHub environment `play-internal`, whose deployment rule
  allows `main` only: `ANDROID_UPLOAD_KEYSTORE_BASE64`, `ANDROID_UPLOAD_KEYSTORE_PASSWORD`,
  `ANDROID_UPLOAD_KEY_ALIAS`. The job decodes it with `umask 077` into `$RUNNER_TEMP`, passes it
  through `GODOT_ANDROID_KEYSTORE_RELEASE_{PATH,USER,PASSWORD}` and deletes it in an
  `if: always()` step. Secrets reach scripts by `env:` only, never `${{ }}` inside `run:`.
- Pull requests never see the key: their AAB check signs with a key generated for the run.

### 4. `export-android.sh --aab`
A new flag; every existing flag and exit code stays. It exports `Android internal` with
`--export-release`, then checks: the bundle is not empty; `jarsigner -verify` passes;
`base/lib/arm64-v8a/` holds the engine, the kernels library CI built (its bytes) and
`libc++_shared.so`, and no other ABI; the native libraries' LOAD segments are 16 KB aligned (Play's
rule for Android 15 targets; the pinned NDK's default, to confirm); the manifest names
`dk.appcode.rts`, no `debuggable`, the permissions of §1 and `screenOrientation` 13; no `tests/` or
`addons/gdUnit4/` path; the licences notice; no ad unit ID other than Google's test units unless
`--real-ad-ids` is passed (Phase 7). The log scan watches for #123712. The AAB's manifest is in
proto format, so the manifest checks read it with `bundletool dump manifest` (bundletool pinned by
version and SHA-256), or with `aapt2` after a proto conversion: the tool is **to confirm in P410**.

### 5. `android-internal.yml`
- **Triggers:** `push` to `main` of the repository itself, and `workflow_dispatch` on `main`.
  Phase 7 adds `workflow_call` for `release.yml`. A new workflow cannot be dispatched before it is
  on `main` (to confirm), so P412 proves the build before merge through `ci.yml`'s PR job
  (`android-aab`, P410) or a temporary `push` trigger on `claude/p412-*` with a generated key,
  removed before merge.
- **Job `aab`** (`contents: read`, environment `play-internal`, because a job reads an
  environment's secrets only when it names the environment): native release library, templates,
  the Gradle template, plugins, the AAB, the clean-tree check, the artifact (AAB and
  `THIRD_PARTY_LICENSES.txt`, 14 days), a job summary (size, SHA-256, versionCode, versionName).
- **Job `upload`** (`needs: aab`, environment `play-internal`, concurrency `play-internal`, no
  cancel): uploads to the `internal` track with the service-account JSON
  (`PLAY_SERVICE_ACCOUNT_JSON`) through a third-party action pinned by commit SHA
  (`r0adkll/upload-google-play` is the candidate, **to confirm in P413**), release notes = commit
  SHA and subject. While Play still treats the app as a draft it accepts only `status: draft`
  releases, and Michael rolls them out in the console (**to confirm in P413**).
- **Ad IDs:** Google's test ad units always. The AdMob App ID: Michael's real one from
  `ADMOB_APP_ID_ANDROID` (Michael's answer 10 A), because UMP's form and app-ads.txt are expected to
  need the real app (**to confirm in P404/P405**). The SDK reads the App ID from the manifest, so it
  must reach the manifest at build time (the plugin's export option or a manifest step: **to confirm
  in P410/P410b**); `ad_ids.cfg` carries unit IDs only, and P414 depends on P410's finding. Real ad
  unit IDs come only with Phase 7's `release.yml`, through `scripts/ci/write-ad-ids.sh`. Until
  Michael's yes to the CLAUDE.md and `admob-policy` texts (plan P400b), the internal build uses
  Google's test App ID as well.
- **Where the secrets live:** the upload key, `PLAY_SERVICE_ACCOUNT_JSON` and
  `ADMOB_APP_ID_ANDROID` in the environment `play-internal`; the real unit IDs
  (`ADMOB_BANNER_ID_ANDROID`, `ADMOB_INTERSTITIAL_ID_ANDROID`, `ADMOB_REWARDED_ID_ANDROID`) in an
  environment `play-release` that only Phase 7's `release.yml` names.
- `tests/project/test_ci_workflow.gd` pins triggers, permissions, the environment, the
  key-delete step and that no secret is read in a `run:` line.
- A secret that is missing fails the job with its name in the error; there is no fallback.

### 6. versionCode and versionName
- **versionCode = 10 × (commits on `main` up to the built commit) + channel** (0 internal, 1
  release), from `scripts/ci/version-code.sh` (`fetch-depth: 0`). It is shared by every workflow,
  so Phase 7's `release.yml` (which calls this workflow as a reusable one) can never collide with
  or fall below an internal build of an earlier commit.
- Not `github.run_number`: a called workflow sees the caller's run number, so `release.yml`'s 1,
  2, 3 would fall below the internal builds; a renamed workflow starts at 1 again.
- A re-run of the same commit gives the same code. Play refuses it, and the job reports "already
  uploaded" as a notice, not a failure, when the bundle on Play is that commit's.
- **versionName** `0.6.<commit count>` for internal builds; Phase 7's version input replaces it.

### 7. `scripts/ci/write-ad-ids.sh`
Reads `ADMOB_*` by `env:`, checks each format, writes `ad_ids.cfg` (git-ignored, packed only by
the Play preset's include filter) and nothing else; its offline test builds its fake IDs at run
time, so no ID literal enters the repository. It writes ad unit IDs only (the App ID takes §5's
build-time path). In Phase 6 it is built and tested; Phase 7's `release.yml` is its first user.

### 8. Not covered
iOS (`ios-testflight.yml`), `release.yml`, the production track and store texts: Phase 7.

## Consequences
- Every merge to `main` costs one more Android build (Gradle, about 10-15 minutes, a guess) and
  one Play upload. The debug and perf APKs keep their fast non-Gradle path.
- The applicationId `dk.appcode.rts` is locked by M5's first upload.
- Losing the upload key is recoverable (Play support resets it); losing the app signing key is
  not, which is why Google holds it.

## Alternatives considered
- **All Android builds on Gradle:** the dev APK would carry the SDK too, but every PR would pay the
  Gradle time, and the perf gate would change under ADR 0012. Not now.
- **Self-managed app signing key in CI:** a leak could not be repaired. Rejected.
- **Workload identity federation instead of a JSON key:** keyless, but more Google Cloud setup for
  Michael. A later upgrade.
