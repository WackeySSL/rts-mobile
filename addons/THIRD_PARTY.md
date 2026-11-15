# Third-party addons

## gdUnit4

| Field | Value |
| --- | --- |
| Name | gdUnit4 (unit test framework for Godot) |
| Version | 6.2.2 |
| Tag | `v6.2.2` |
| Tag commit | `0127a55f4543dfc24746f6e5c7ba6f94105d51f2` |
| Source | https://github.com/godot-gdunit-labs/gdUnit4 |
| Licence | MIT, Copyright (c) 2023 Mike Schulze (`addons/gdUnit4/LICENSE`) |
| Location | `addons/gdUnit4/` |
| Used for | `tests/` (run headless by `scripts/run-tests.sh`) |

The editor plugin is not enabled in `project.godot`. The command line runner does not need it.
The Web export preset excludes `addons/gdUnit4/*` and `tests/*`.

### How it was vendored

This is the upstream AssetLib export (`addons/gdUnit4` without `test/` and without the agent
files `AGENTS.md` and `CLAUDE.md`), 272 files. Do not `cp -R` a clone: that would bring in
`test/` and a `CLAUDE.md`.

```bash
git clone --depth 1 --branch v6.2.2 https://github.com/godot-gdunit-labs/gdUnit4.git <scratch>
git -C <scratch> rev-parse HEAD   # must print 0127a55f4543dfc24746f6e5c7ba6f94105d51f2
git -C <scratch> archive --format=tar HEAD addons/gdUnit4 | tar -x -C <repo>
```

Upstream ignores `*.gd.uid`, so it ships none. One `godot --headless --path . --import` generated
the 236 `*.gd.uid` and 8 `*.png.import` files that are committed next to the sources. They keep
`git status` clean after a fresh clone is imported.

### Notes

- Upstream states Godot 4.5 to 4.7.1. It is verified on 4.7.2 on macOS (Phase 0); Ubuntu is
  first exercised by CI. If a Godot bump breaks it, re-run the spike before changing the pin
  (ADR 0002).
- `addons/gdUnit4` does not pass `gdformat` or `gdlint`, so `scripts/verify.sh` checks only
  `game`, `tests` and `scenes`.
- Upgrade only through a new ADR.

## Poing Studios AdMob plugin

| Field | Value |
| --- | --- |
| Name | godot-admob-plugin (AdMob for Godot, Android and iOS) |
| Version | 5.1.0 |
| Tag | `v5.1.0` |
| Tag commit | `615974e9f66921a54e3c71c33db0856bdbf19d13` |
| Source | https://github.com/poingstudios/godot-admob-plugin |
| Licence | MIT, Copyright (c) 2020-present Poing Studios (`addons/admob/LICENSE`, `docs/licenses/poing-godot-admob-5.1.0/LICENSE.txt`) |
| Location | `addons/admob/` (editor part, vendored); `addons/admob/android/` (Android libraries, fetched, git-ignored) |
| Used for | the ads behind `game/ads/AdService.gd` (ADR 0039); the `Android internal` AAB (ADR 0040) |

The editor part is a minimal vendoring of the release asset `poing-godot-admob-v5.1.0.zip` (SHA-256
`8c53ff52719edf6a81cc7d32a9cdaad2d9e11693c85faca25008a1c19355726f`) with two local patches, described in
`addons/admob/PATCHES.md`: the Godot 4.7.2 static initializer, and our own placeholder SVGs instead of five upstream
images. `tests/project/test_admob_vendor.gd` pins the SHA-256 of every vendored file in
`tests/project/admob_vendor_manifest.txt`, which is plain `sha256sum` output: `sha256sum -c
tests/project/admob_vendor_manifest.txt` checks it, and this regenerates it after a deliberate change (git-ignored
import outputs, the fetched folders, `PATCHES.md` and the placeholders are not pinned):

```bash
find addons/admob -type f -not -path 'addons/admob/android/*' -not -path 'addons/admob/ios/*' \
  -not -path 'addons/admob/downloads/*' -not -path addons/admob/PATCHES.md \
  -not -path 'addons/admob/assets/placeholder_*' -not -name '*.translation' \
  | LC_ALL=C sort | xargs sha256sum > tests/project/admob_vendor_manifest.txt
```

The Android libraries come from `android-template-v4.7.2.zip` of the same tag through
`scripts/ci/install-android-plugins.sh` (SHA-256 pinned). The Gradle build pulls the Google Mobile Ads SDK from
Google's Maven by the coordinates the plugin's export script names:
`com.google.android.libraries.ads.mobile.sdk:ads-mobile-sdk:1.4.0` and `androidx.constraintlayout:constraintlayout:2.2.0`.
Whether Google's SDK terms need an in-game notice is not decided here; it moves to P410b, which builds the AAB.

The plugin stays disabled in `project.godot`, so the `Android` and `Android perf` presets export unchanged (they
exclude `addons/admob/*`); the AAB export enables it for one run (P410b). The Web preset excludes `addons/admob/*`
too. Upgrade only through a new ADR.

### Does Google's SDK need an in-game notice? (P410b, Phase 5 item 10)

**To confirm.** The Google Mobile Ads SDK terms live on developers.google.com, which the cloud session's network
blocks (`getaddrinfo ENOTFOUND`), so the answer could not be read on 2026-11-15. Pages to read, by the person
with access: https://developers.google.com/admob/terms (AdMob terms and the SDK's terms of use) and
https://developers.google.com/admob/android/quick-start. Until then:
- The plugin's own licence (Poing Studios, `addons/admob/LICENSE`, copy in `docs/licenses/poing-godot-admob-5.1.0/`)
  goes into `THIRD_PARTY_LICENSES.txt` and the Licences screen (P410's licence lines, Phase 5).
- Google's SDK is proprietary and arrives as a Gradle dependency (the AARs pull it from Google's Maven); no
  licence text of it is vendored. Nothing in this repository shows that Google asks for an in-game notice.
- The `android-aab` job prints the final manifest permissions, and the AAB's merged licence files can be listed in
  its log once it has run; if the terms ask for a notice, add it to `scripts/export-android.sh`'s notice and the
  Licences screen.
