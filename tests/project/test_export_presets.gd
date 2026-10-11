extends GdUnitTestSuite
## Pins the Android debug preset (ADR 0005 section 1, ADR 0006). A wrong value still exports
## without any error: another package id installs next to the Play build, a second ABI doubles
## the APK, a keystore value in the file leaks a secret. scripts/export-android.sh checks the
## result in CI; this test catches the edit before that.

const PRESETS: String = "res://export_presets.cfg"
const SECTION: String = "preset.1"
const OPTIONS: String = "preset.1.options"


func _config() -> ConfigFile:
	var config: ConfigFile = ConfigFile.new()
	assert_int(config.load(PRESETS)).is_equal(OK)
	return config


func test_preset_identity() -> void:
	var config: ConfigFile = _config()
	assert_str(config.get_value(SECTION, "name")).is_equal("Android")
	assert_str(config.get_value(SECTION, "platform")).is_equal("Android")
	assert_str(config.get_value(SECTION, "export_path")).is_equal(
		"build/android/rts-mobile-debug.apk"
	)
	# A debug build enables the dev menu through OS.is_debug_build() (ADR 0005 section 1).
	assert_str(config.get_value(SECTION, "custom_features")).is_empty()
	# Test code and the test runner never ship (same filter as the Web preset).
	assert_str(config.get_value(SECTION, "exclude_filter")).is_equal("tests/*, addons/gdUnit4/*")
	assert_str(config.get_value("preset.0", "exclude_filter")).is_equal(
		config.get_value(SECTION, "exclude_filter")
	)


func test_application_identity() -> void:
	var config: ConfigFile = _config()
	assert_str(config.get_value(OPTIONS, "package/unique_name")).is_equal("dk.appcode.rts.dev")
	assert_str(config.get_value(OPTIONS, "package/name")).is_equal("Treadline dev")
	assert_bool(config.get_value(OPTIONS, "package/signed")).is_true()
	assert_int(config.get_value(OPTIONS, "version/code")).is_equal(1)


func test_non_gradle_arm64_only() -> void:
	var config: ConfigFile = _config()
	assert_bool(config.get_value(OPTIONS, "gradle_build/use_gradle_build")).is_false()
	assert_bool(config.get_value(OPTIONS, "architectures/arm64-v8a")).is_true()
	assert_bool(config.get_value(OPTIONS, "architectures/armeabi-v7a")).is_false()
	assert_bool(config.get_value(OPTIONS, "architectures/x86")).is_false()
	assert_bool(config.get_value(OPTIONS, "architectures/x86_64")).is_false()


func test_vibrate_permission_for_haptics() -> void:
	assert_bool(_config().get_value(OPTIONS, "permissions/vibrate")).is_true()


func test_no_keystore_value_in_the_file() -> void:
	var config: ConfigFile = _config()
	var keys: PackedStringArray = config.get_section_keys(OPTIONS)
	for key: String in keys:
		assert_bool(key.begins_with("keystore/")).is_false()
