extends GdUnitTestSuite
## Pins the Phase 0 project.godot block (ADR 0002 sections 3 and 4). A wrong value changes
## rendering, scaling or touch behaviour without any error, so each one is asserted.

## ADR 0043 section 2: the app starts on the boot scene, which opens into the menu (P533). The
## match scene stays a file of its own, built by MenuFlow.
const BOOT_SCENE: String = "res://scenes/boot.tscn"
const MAIN_SCENE: String = "res://scenes/main.tscn"
## Plan row P98: the game's own icon, drawn in this repository (assets/art/svg/icon).
const APP_ICON: String = "res://assets/art/svg/icon/app_icon.svg"


func test_application() -> void:
	assert_str(_setting("application/config/name")).is_equal("rts-mobile")
	assert_str(_setting("application/run/main_scene")).is_equal(BOOT_SCENE)
	var features: PackedStringArray = _setting("application/config/features")
	assert_array(features).contains_exactly(["4.7", "GL Compatibility"])


func test_scene_files_exist() -> void:
	for path: String in [BOOT_SCENE, MAIN_SCENE, ArtIntro.SPLASH_PATH]:
		assert_bool(FileAccess.file_exists(path)).is_true()
		assert_bool(ResourceLoader.exists(path)).is_true()


## ADR 0043 section 1: the engine's boot splash is ours, the values of
## `ArtIntro.BOOT_SPLASH_SETTINGS` (the tool that draws the PNG owns them). Without them the Godot
## logo shows first.
func test_boot_splash_is_the_games_own() -> void:
	for key: String in ArtIntro.BOOT_SPLASH_SETTINGS:
		var want: Variant = ArtIntro.BOOT_SPLASH_SETTINGS[key]
		var got: Variant = _setting(key)
		if want is String and (want as String).begins_with("#"):
			assert_bool(got is Color).override_failure_message(key + " is not a Color").is_true()
			assert_str((got as Color).to_html(false).to_upper()).is_equal(
				(want as String).trim_prefix("#").to_upper()
			)
		else:
			assert_that(got).override_failure_message(key).is_equal(want)
	assert_str(_setting("application/boot_splash/image")).is_equal(ArtIntro.SPLASH_PATH)


## ADR 0043 section 4: Back is the game's to handle on every screen (the menu stack, the intro, the
## pause menu), so the engine must not quit the app on it.
func test_back_does_not_quit_the_app() -> void:
	assert_bool(_setting("application/config/quit_on_go_back")).is_false()
	assert_bool(get_tree().quit_on_go_back).is_false()


## The exports fall back to the project icon (the web favicon, an Android icon option left empty),
## so without this setting they ship Godot's logo.
func test_project_icon_is_the_app_icon() -> void:
	assert_str(_setting("application/config/icon")).is_equal(APP_ICON)


func test_project_icon_file_exists() -> void:
	assert_bool(FileAccess.file_exists(APP_ICON)).is_true()


func test_autoload_entries_use_res_paths() -> void:
	# The 4.7 editor rewrites these to uid:// when it saves the project. Revert such a change.
	assert_str(_setting("autoload/DetRng")).is_equal("*res://game/core/det_rng_service.gd")
	assert_str(_setting("autoload/CommandQueue")).is_equal(
		"*res://game/core/command_queue_service.gd"
	)
	# ADR 0015 section 2: the base size per orientation, for every scene.
	assert_str(_setting("autoload/UiOrientation")).is_equal(
		"*res://game/ui/ui_orientation_service.gd"
	)


func test_untyped_declarations_are_errors() -> void:
	assert_int(_setting("debug/gdscript/warnings/untyped_declaration")).is_equal(2)


func test_gdunit_fails_tests_on_push_error() -> void:
	assert_bool(_setting("gdunit4/report/godot/push_error")).is_true()


func test_display() -> void:
	assert_int(_setting("display/window/size/viewport_width")).is_equal(1280)
	assert_int(_setting("display/window/size/viewport_height")).is_equal(720)
	assert_str(_setting("display/window/stretch/mode")).is_equal("canvas_items")
	assert_str(_setting("display/window/stretch/aspect")).is_equal("expand")
	# 6 = sensor (ADR 0015 section 7); the Android manifest gets fullUser (13)
	assert_int(_setting("display/window/handheld/orientation")).is_equal(6)


func test_rendering_is_compatibility() -> void:
	assert_str(_setting("rendering/renderer/rendering_method")).is_equal("gl_compatibility")
	assert_str(_setting("rendering/renderer/rendering_method.mobile")).is_equal("gl_compatibility")
	# The Web preset needs this: with it off the export fails with a misleading template error.
	assert_bool(_setting("rendering/textures/vram_compression/import_etc2_astc")).is_true()


func test_touch_emulation() -> void:
	assert_bool(_setting("input_devices/pointing/emulate_touch_from_mouse")).is_true()
	assert_bool(_setting("input_devices/pointing/emulate_mouse_from_touch")).is_false()


## TouchInput reads raw touches (ADR 0004). With either setting on, Android would turn a long press
## into a right click or two fingers into pan and scale events. Neither is set: the default counts.
func test_android_does_not_turn_touches_into_other_events() -> void:
	for key: String in ["enable_long_press_as_right_click", "enable_pan_and_scale_gestures"]:
		var setting_name: String = "input_devices/pointing/android/" + key
		assert_bool(_setting(setting_name)).is_false()


## The version string the main menu shows (Michael, 2026-11-16). The Android export's version name
## and code are release work and not pinned here.
func test_the_version_string_is_beta_1() -> void:
	assert_str(_setting("application/config/version")).is_equal("Beta 1")


func _setting(setting_name: String) -> Variant:
	return ProjectSettings.get_setting(setting_name)
