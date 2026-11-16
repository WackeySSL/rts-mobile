# Local patches to the vendored AdMob plugin

Upstream: Poing Studios godot-admob-plugin, https://github.com/poingstudios/godot-admob-plugin
Tag `v5.1.0`, commit `615974e9f66921a54e3c71c33db0856bdbf19d13`. Editor part taken from the release asset
`poing-godot-admob-v5.1.0.zip`, SHA-256 `8c53ff52719edf6a81cc7d32a9cdaad2d9e11693c85faca25008a1c19355726f`
(https://github.com/poingstudios/godot-admob-plugin/releases/download/v5.1.0/poing-godot-admob-v5.1.0.zip).
Not vendored: `csharp/`, `docs/`, `skills/`, `gdscript/sample/`, every upstream image, font and sound under
`assets/`, and the Android part (`scripts/ci/install-android-plugins.sh` fetches it by SHA-256).
`tests/project/test_admob_vendor.gd` pins the SHA-256 of every vendored file (the manifest is
`tests/project/admob_vendor_manifest.txt`), so any change here must be made on purpose.

## Patch 1: Godot 4.7.2 static initializer (Michael, 2026-11-15)
File: `internal/exporters/base_export_plugin.gd`, line 50.

    upstream v5.1.0:  static var KNOWN_LIBS: Array[String] = ["ads"] + MEDIATION_LIBS
    patched:          static var KNOWN_LIBS := ["ads"] + MEDIATION_LIBS

In Godot 4.7.2 the upstream line fails ("Trying to assign an array of type "Array" to a variable of type
"Array[String]"", at the static initializer), so the editor plugin never registers. The patched line is the one
in upstream master (commit `4dc9144`, nightly `v5.2.0-nightly.4dc91441`):
https://raw.githubusercontent.com/poingstudios/godot-admob-plugin/master/platforms/godot_editor/addons/admob/internal/exporters/base_export_plugin.gd
Removal: when a release (expected 5.1.1) contains that line, vendor that release, drop this patch and its
entry in the test's patched-file list.

## Patch 2: placeholder images (Michael, 2026-11-15)
Upstream's mock ads preload five third-party images. They are not vendored. The `preload` and `load` paths in
`internal/mock/` name our own placeholder SVGs in `addons/admob/assets/` instead (drawn by art-director, listed in
`assets/CREDITS.md`):

| Upstream file | Placeholder | Size | Stands for |
| --- | --- | --- | --- |
| `flood_it_icon.svg` | `placeholder_app_icon.svg` | 64 x 64 | the advertised app's icon in the mock ads |
| `google_play_icon.svg` | `placeholder_store_icon.svg` | 24 x 24 | the store badge in the mock rewarded ads |
| `icon-120.png` | `placeholder_ad_logo.svg` | 120 x 120 | the AdMob logo in the mock ad frames |
| `format-interstitial.svg` | `placeholder_format_interstitial.svg` | 184 x 144 | the interstitial format preview |
| `format-rewarded-interstitial.svg` | `placeholder_format_rewarded.svg` | 184 x 144 | the rewarded format preview |

Patched files: `internal/mock/mock_ad_view_plugin.gd`, `mock_app_open_ad_plugin.gd`,
`mock_interstitial_ad_plugin.gd`, `mock_native_overlay_ad_plugin.gd`, `mock_rewarded_ad_plugin.gd`,
`mock_rewarded_interstitial_ad_plugin.gd`. Removal: never, unless upstream drops the images.

## Not enabled
The plugin stays out of `[editor_plugins]` in `project.godot`: enabled, its Android export plugin raises an error
on every non-Gradle Android export (`Android`, `Android perf`) and a headless editor start would download binaries
without a pin. `export-android.sh --aab` enables it for one run (P410b).
