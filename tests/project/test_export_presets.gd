extends GdUnitTestSuite
## Pins the Android debug preset (ADR 0005 section 1, ADR 0006). A wrong value still exports
## without an error: another package id installs next to the Play build, a second ABI doubles the
## APK, a keystore value in the file leaks a secret. scripts/export-android.sh checks the APK in
## CI; this test catches the edit before that.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")

const SECTION: String = "preset.1"
const OPTIONS: String = "preset.1.options"

## Plan row P98: the Android presets ("Android" and "Android perf") name the game's own icon in the
## three launcher icon options, and the files they name are the SVGs of assets/art/svg/icon.
const ANDROID_PRESETS: Array[String] = ["preset.1", "preset.2", "preset.3"]
const MAIN_ICON: String = "launcher_icons/main_192x192"
const FOREGROUND_ICON: String = "launcher_icons/adaptive_foreground_432x432"
const BACKGROUND_ICON: String = "launcher_icons/adaptive_background_432x432"
const ICON_FILES: Dictionary[String, String] = {
	MAIN_ICON: "res://assets/art/svg/icon/app_icon.svg",
	FOREGROUND_ICON: "res://assets/art/svg/icon/icon_foreground.svg",
	BACKGROUND_ICON: "res://assets/art/svg/icon/icon_background.svg",
}

## Plan row P118b (P410b: and "Android internal"): every preset packs the OFL.txt of each font
## folder. export_filter all_resources leaves out a .txt file, so the include_filter names them;
## the SIL Open Font License asks for its text with every copy of the fonts. export-web.sh and
## export-android.sh look for each OFL.txt in the pack or the APK, and scripts/ci/font-notice.sh
## puts the same texts into THIRD_PARTY_LICENSES.txt beside the build.
const ALL_PRESETS: Array[String] = ["preset.0", "preset.1", "preset.2", "preset.3"]

## Plan row P410b (ADR 0040 section 1): the Play build.
const INTERNAL: String = "preset.3"
const INTERNAL_OPTIONS: String = "preset.3.options"
const FONT_DIR: String = "res://assets/art/fonts"
const OFL_NAME: String = "OFL.txt"
## A family folder that does not exist yet: the filter must cover it without an edit.
const FUTURE_OFL: String = "res://assets/art/fonts/some-future-family/OFL.txt"

## Plan row P529 (ADR 0043 section 7): the Licences screen shows godot-cpp's MIT text on exactly the
## builds that contain the kernels, read from this export feature tag. Tag set = native/ packed.
const KERNELS_TAG: String = "sim_kernels"
const LICENCE_FILES: Array[String] = [
	"res://assets/licenses/llvm-libc++/LICENSE.TXT",
	"res://assets/licenses/godot-cpp-4.5-stable/LICENSE.md",
	"res://assets/licenses/poing-godot-admob-5.1.0/LICENSE.txt",
	"res://assets/LICENSE.md",
	"res://assets/CREDITS.md",
]
const KERNELS_FILE: String = "res://native/sim_kernels.gdextension"

## The Play Store asks for a 512 px icon.
const MIN_MAIN_ICON_PX: int = 512
## An adaptive layer is 108 dp at 4x.
const LAYER_PX: int = 432


func _config() -> ConfigFile:
	var config: ConfigFile = ConfigFile.new()
	assert_int(config.load("res://export_presets.cfg")).is_equal(OK)
	return config


func test_preset_identity() -> void:
	var config: ConfigFile = _config()
	assert_str(config.get_value(SECTION, "name")).is_equal("Android")
	assert_str(config.get_value(SECTION, "platform")).is_equal("Android")
	assert_str(config.get_value(SECTION, "export_path")).is_equal(
		"build/android/rts-mobile-debug.apk"
	)
	# A debug build enables the dev menu through OS.is_debug_build(), not a custom feature; the one
	# feature is sim_kernels (plan P529, below).
	assert_str(config.get_value(SECTION, "custom_features")).is_equal(KERNELS_TAG)
	# Test code, the test runner and the AdMob plugin never ship in this non-Gradle APK (ADR 0040 §1).
	# Unlike the Web preset, never native/* (ADR 0013).
	assert_str(config.get_value(SECTION, "exclude_filter")).is_equal(
		"tests/*, addons/gdUnit4/*, addons/admob/*, assets/art/brand/*"
	)


## ADR 0013 section 7: the web preview runs the GDScript twins and packs no .gdextension, which
## Godot only warns about. scripts/export-web.sh checks the pack; this catches the edit first.
func test_web_preset_excludes_tests_native_and_addons() -> void:
	var config: ConfigFile = _config()
	assert_str(config.get_value("preset.0", "name")).is_equal("Web")
	assert_str(config.get_value("preset.0", "exclude_filter")).is_equal(
		"tests/*, addons/gdUnit4/*, addons/admob/*, native/*, assets/art/brand/*"
	)


## ADR 0015 section 7: the web preview turns with the phone. The PWA is off and its orientation is
## Any (0), so the exported page locks nothing; the project's orientation setting is not applied on
## the web, and a PWA manifest with an orientation would be the only thing that could lock it.
func test_web_preset_does_not_lock_the_orientation() -> void:
	var config: ConfigFile = _config()
	var options: String = "preset.0.options"
	assert_str(config.get_value("preset.0", "name")).is_equal("Web")
	assert_bool(config.get_value(options, "progressive_web_app/enabled")).is_false()
	assert_int(config.get_value(options, "progressive_web_app/orientation")).is_equal(0)


func test_app_identity_and_vibrate() -> void:
	var config: ConfigFile = _config()
	assert_str(config.get_value(OPTIONS, "package/unique_name")).is_equal("dk.appcode.rts.dev")
	assert_str(config.get_value(OPTIONS, "package/name")).is_equal("Treadline dev")
	assert_bool(config.get_value(OPTIONS, "package/signed")).is_true()
	assert_int(config.get_value(OPTIONS, "version/code")).is_equal(1)
	assert_bool(config.get_value(OPTIONS, "permissions/vibrate")).is_true()


func test_non_gradle_arm64_only() -> void:
	var config: ConfigFile = _config()
	assert_bool(config.get_value(OPTIONS, "gradle_build/use_gradle_build")).is_false()
	assert_bool(config.get_value(OPTIONS, "architectures/arm64-v8a")).is_true()
	assert_bool(config.get_value(OPTIONS, "architectures/armeabi-v7a")).is_false()
	assert_bool(config.get_value(OPTIONS, "architectures/x86")).is_false()
	assert_bool(config.get_value(OPTIONS, "architectures/x86_64")).is_false()


func test_no_keystore_value_in_the_file() -> void:
	var config: ConfigFile = _config()
	for section: String in ANDROID_PRESETS:
		for key: String in config.get_section_keys(section + ".options"):
			(
				assert_bool(key.begins_with("keystore/"))
				. override_failure_message("%s has the keystore option %s" % [section, key])
				. is_false()
			)


## The fourth preset is the Play build: the release package id, a Gradle AAB for arm64 only, the
## custom feature play, and the AdMob plugin left in the pack (the other presets exclude it). Test
## code and gdUnit4 stay out, and native/* never goes (ADR 0013): the kernels library must travel
## in the bundle. export-android.sh --aab and scripts/ci/check-aab.sh check the bundle itself.
func test_android_internal_preset_is_the_gradle_aab_play_build() -> void:
	var config: ConfigFile = _config()
	assert_str(config.get_value(INTERNAL, "name")).is_equal("Android internal")
	assert_str(config.get_value(INTERNAL, "platform")).is_equal("Android")
	assert_str(config.get_value(INTERNAL, "custom_features")).is_equal("play," + KERNELS_TAG)
	assert_str(config.get_value(INTERNAL, "export_path")).is_equal(
		"build/android/rts-mobile-internal.aab"
	)
	var exclude: String = config.get_value(INTERNAL, "exclude_filter")
	assert_str(exclude).is_equal("tests/*, addons/gdUnit4/*, assets/art/brand/*")
	assert_bool(_filter_matches(exclude, "res://addons/admob/admob.gd")).is_false()
	assert_bool(_filter_matches(exclude, "res://native/sim_kernels.gdextension")).is_false()
	assert_str(config.get_value(INTERNAL_OPTIONS, "package/unique_name")).is_equal("dk.appcode.rts")
	assert_str(config.get_value(INTERNAL_OPTIONS, "package/name")).is_equal("Treadline")
	assert_bool(config.get_value(INTERNAL_OPTIONS, "gradle_build/use_gradle_build")).is_true()
	assert_int(config.get_value(INTERNAL_OPTIONS, "gradle_build/export_format")).is_equal(1)
	assert_bool(config.get_value(INTERNAL_OPTIONS, "architectures/arm64-v8a")).is_true()
	for abi: String in ["armeabi-v7a", "x86", "x86_64"]:
		assert_bool(config.get_value(INTERNAL_OPTIONS, "architectures/" + abi)).is_false()
	assert_bool(config.get_value(INTERNAL_OPTIONS, "permissions/vibrate")).is_true()
	assert_bool(config.get_value(INTERNAL_OPTIONS, "permissions/internet")).is_true()
	# The debug presets stay as they were: no Gradle, no plugin in the pack.
	for section: String in ["preset.1", "preset.2"]:
		var gradle: bool = config.get_value(section + ".options", "gradle_build/use_gradle_build")
		assert_bool(gradle).is_false()
		assert_str(config.get_value(section, "exclude_filter")).contains("addons/admob/*")


func test_android_presets_name_the_three_icon_files() -> void:
	var config: ConfigFile = _config()
	for section: String in ANDROID_PRESETS:
		assert_str(config.get_value(section, "platform")).is_equal("Android")
		for option: String in ICON_FILES:
			var named: String = config.get_value(section + ".options", option, "")
			var where: String = "%s %s" % [section, option]
			assert_str(named).override_failure_message(where).is_equal(ICON_FILES[option])


func test_every_icon_file_a_preset_names_exists() -> void:
	var config: ConfigFile = _config()
	for section: String in ANDROID_PRESETS:
		for option: String in ICON_FILES:
			var path: String = config.get_value(section + ".options", option, "")
			var where: String = "%s %s '%s'" % [section, option, path]
			assert_bool(FileAccess.file_exists(path)).override_failure_message(where).is_true()


## The main icon is the 512 px store square; the option is named 192x192 because the exporter
## processes it down to the launcher sizes, so a larger source loses nothing.
func test_the_main_launcher_icon_loads_square_at_512_px_or_more() -> void:
	var config: ConfigFile = _config()
	for section: String in ANDROID_PRESETS:
		var path: String = config.get_value(section + ".options", MAIN_ICON, "")
		var size: Vector2i = _source_size(path)
		var where: String = "%s '%s' loads at %s" % [section, path, size]
		assert_int(size.x).override_failure_message(where).is_equal(size.y)
		assert_int(size.x).override_failure_message(where).is_greater_equal(MIN_MAIN_ICON_PX)


## A layer is 108 dp at 4x, and the foreground is drawn for the 288 px safe circle of that canvas
## (tests/art/test_app_icon.gd), so the file must be exactly the canvas the option names.
func test_the_adaptive_layers_load_at_432_px() -> void:
	var config: ConfigFile = _config()
	for section: String in ANDROID_PRESETS:
		for option: String in [FOREGROUND_ICON, BACKGROUND_ICON]:
			var path: String = config.get_value(section + ".options", option, "")
			var size: Vector2i = _source_size(path)
			var where: String = "%s '%s' loads at %s" % [section, path, size]
			assert_vector(size).override_failure_message(where).is_equal(
				Vector2i(LAYER_PX, LAYER_PX)
			)


## Plan row P98: the web preview's favicon (index.icon.png and the apple-touch icon) is the project
## icon instead of the page showing none. The PWA stays off; this option does not turn it on.
func test_web_preset_exports_the_project_icon_as_the_favicon() -> void:
	var config: ConfigFile = _config()
	assert_str(config.get_value("preset.0", "name")).is_equal("Web")
	assert_bool(config.get_value("preset.0.options", "html/export_icon")).is_true()


func test_every_preset_packs_the_ofl_text_of_each_font_folder() -> void:
	var config: ConfigFile = _config()
	var texts: Array[String] = FileScan.list_files(FONT_DIR, OFL_NAME)
	assert_int(texts.size()).is_greater_equal(2)  # Big Shoulders and Chakra Petch.
	texts.append(FUTURE_OFL)
	for section: String in ALL_PRESETS:
		var include: String = config.get_value(section, "include_filter", "")
		var exclude: String = config.get_value(section, "exclude_filter", "")
		for path: String in texts:
			var where: String = "%s packs %s" % [section, path]
			(
				assert_bool(_filter_matches(include, path))
				. override_failure_message(
					where + ": its include_filter '%s' does not match it" % include
				)
				. is_true()
			)
			(
				assert_bool(_filter_matches(exclude, path))
				. override_failure_message(where + ": its exclude_filter '%s' removes it" % exclude)
				. is_false()
			)


func test_the_sim_kernels_tag_is_set_on_exactly_the_presets_that_pack_native() -> void:
	var config: ConfigFile = _config()
	var tagged: int = 0
	for section: String in ALL_PRESETS:
		var features: PackedStringArray = (
			String(config.get_value(section, "custom_features", "")).split(",")
		)
		var has_tag: bool = false
		for feature: String in features:
			has_tag = has_tag or feature.strip_edges() == KERNELS_TAG
		var packs_native: bool = not _filter_matches(
			config.get_value(section, "exclude_filter", ""), KERNELS_FILE
		)
		var where: String = "%s: tag %s, packs native/ %s" % [section, has_tag, packs_native]
		assert_bool(has_tag).override_failure_message(where).is_equal(packs_native)
		tagged += 1 if has_tag else 0
	assert_int(tagged).is_equal(3)  # Both Android debug presets and the Play build; not Web.
	assert_str(config.get_value("preset.0", "custom_features")).not_contains(KERNELS_TAG)


## Follow-up of plan row P500d: nothing loads the brand SVGs at runtime (the splash is a PNG), so no
## preset packs them; the include_filter must not bring them back either.
func test_no_preset_packs_the_brand_svgs() -> void:
	var config: ConfigFile = _config()
	var brand: String = "res://assets/art/brand/appcode_mark_white.svg"
	assert_bool(FileAccess.file_exists(brand)).is_true()
	for section: String in ALL_PRESETS:
		var exclude: String = config.get_value(section, "exclude_filter", "")
		assert_bool(_filter_matches(exclude, brand)).override_failure_message(section).is_true()


## Plan row P529: every preset packs the licence texts the Licences screen reads (the .md and .txt
## files need the include_filter; all_resources leaves them out).
func test_every_preset_packs_the_licence_texts() -> void:
	var config: ConfigFile = _config()
	for section: String in ALL_PRESETS:
		var include: String = config.get_value(section, "include_filter", "")
		var exclude: String = config.get_value(section, "exclude_filter", "")
		for path: String in LICENCE_FILES:
			var where: String = "%s packs %s" % [section, path]
			assert_bool(_filter_matches(include, path)).override_failure_message(where).is_true()
			assert_bool(_filter_matches(exclude, path)).override_failure_message(where).is_false()


## A filter list: comma separated globs, taken from the project root unless one starts with res://
## or a star (the shape of the filters in this file). The real proof that the exporter packs the
## files is export-web.sh's and export-android.sh's look into the pack and the APK.
func _filter_matches(filters: String, path: String) -> bool:
	for entry: String in filters.split(","):
		var glob: String = entry.strip_edges()
		if glob.is_empty():
			continue
		if not glob.begins_with("res://") and not glob.begins_with("*"):
			glob = "res://" + glob
		if path.matchn(glob):
			return true
	return false


## The size of an icon file as the Android exporter reads it. The exporter's icon loader
## (EditorExportPlatform._load_icon_or_splash_image, called for every launcher icon option and the
## splash icon) loads the imported Texture2D and takes its image, so the file's .import settings
## (svg/scale, process/size_limit) decide the size; only when that fails does it fall back to the
## raw image loader. This loads the texture the same way. A missing or unreadable file gives a zero
## size.
func _source_size(path: String) -> Vector2i:
	if not ResourceLoader.exists(path):
		return Vector2i.ZERO
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		return Vector2i.ZERO
	var image: Image = texture.get_image()
	return Vector2i.ZERO if image == null else image.get_size()
