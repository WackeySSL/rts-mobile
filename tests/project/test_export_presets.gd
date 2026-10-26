extends GdUnitTestSuite
## Pins the Android debug preset (ADR 0005 section 1, ADR 0006). A wrong value still exports
## without an error: another package id installs next to the Play build, a second ABI doubles the
## APK, a keystore value in the file leaks a secret. scripts/export-android.sh checks the APK in
## CI; this test catches the edit before that.

const SECTION: String = "preset.1"
const OPTIONS: String = "preset.1.options"

## Plan row P98: the Android presets ("Android" and "Android perf") name the game's own icon in the
## three launcher icon options, and the files they name are the SVGs of assets/art/svg/icon.
const ANDROID_PRESETS: Array[String] = ["preset.1", "preset.2"]
const MAIN_ICON: String = "launcher_icons/main_192x192"
const FOREGROUND_ICON: String = "launcher_icons/adaptive_foreground_432x432"
const BACKGROUND_ICON: String = "launcher_icons/adaptive_background_432x432"
const ICON_FILES: Dictionary[String, String] = {
	MAIN_ICON: "res://assets/art/svg/icon/app_icon.svg",
	FOREGROUND_ICON: "res://assets/art/svg/icon/icon_foreground.svg",
	BACKGROUND_ICON: "res://assets/art/svg/icon/icon_background.svg",
}
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
	# A debug build enables the dev menu through OS.is_debug_build(), not a custom feature.
	assert_str(config.get_value(SECTION, "custom_features")).is_empty()
	# Test code and the test runner never ship. Unlike the Web preset, never native/* (ADR 0013).
	assert_str(config.get_value(SECTION, "exclude_filter")).is_equal("tests/*, addons/gdUnit4/*")


## ADR 0013 section 7: the web preview runs the GDScript twins and packs no .gdextension, which
## Godot only warns about. scripts/export-web.sh checks the pack; this catches the edit first.
func test_web_preset_excludes_native() -> void:
	var config: ConfigFile = _config()
	assert_str(config.get_value("preset.0", "name")).is_equal("Web")
	assert_str(config.get_value("preset.0", "exclude_filter")).is_equal(
		"tests/*, addons/gdUnit4/*, native/*"
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
	for key: String in _config().get_section_keys(OPTIONS):
		assert_bool(key.begins_with("keystore/")).is_false()


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
