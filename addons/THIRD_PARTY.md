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
images. `tests/project/test_admob_vendor.gd` pins the SHA-256 of every vendored file. The Android libraries come from
`android-template-v4.7.2.zip` of the same tag through `scripts/ci/install-android-plugins.sh` (SHA-256 pinned); the
Gradle build pulls the Google Mobile Ads SDK 1.4.0 from Google's Maven.

The plugin stays disabled in `project.godot`, so the `Android` and `Android perf` presets export unchanged; the AAB
export enables it for one run (P410b). The Web preset excludes `addons/admob/*`. Upgrade only through a new ADR.
