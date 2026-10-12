extends GdUnitTestSuite
## Pins the Android debug preset (ADR 0005 section 1, ADR 0006). A wrong value still exports
## without an error: another package id installs next to the Play build, a second ABI doubles the
## APK, a keystore value in the file leaks a secret. scripts/export-android.sh checks the APK in
## CI; this test catches the edit before that.

const SECTION: String = "preset.1"
const OPTIONS: String = "preset.1.options"


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
	# PROBE ONLY (branch claude/p26s-perf-probe, never merged): this branch exports the Android
	# RELEASE template, where OS.is_debug_build() is false, so the dev menu (and with it the perf
	# probe) is reached through the custom feature instead. On main this is empty.
	assert_str(config.get_value(SECTION, "custom_features")).is_equal("dev_menu")
	# Test code and the test runner never ship (the Web preset has the same filter).
	assert_str(config.get_value(SECTION, "exclude_filter")).is_equal("tests/*, addons/gdUnit4/*")


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


## Spike P26n: the C++ extension (native/) has no wasm build, so the web pack must not carry the
## .gdextension; without it the web preview never tries to load a library it does not have, and the
## probe shows "C++ tick not available on this build" for mode 5 (which the cycle skips anyway, as
## the web build has no threads).
func test_web_preset_leaves_the_native_extension_out() -> void:
	var config: ConfigFile = _config()
	assert_str(config.get_value("preset.0", "name")).is_equal("Web")
	var filter: String = config.get_value("preset.0", "exclude_filter")
	assert_str(filter).contains("tests/*")
	assert_str(filter).contains("addons/gdUnit4/*")
	assert_str(filter).contains("native/*")
	assert_bool(config.get_value("preset.0.options", "variant/extensions_support")).is_false()
	# The Android preset keeps it: its pack carries the .gdextension and the arm64 library.
	assert_str(config.get_value(SECTION, "exclude_filter")).not_contains("native")
