extends GdUnitTestSuite
## Every tappable thing is at least UiScale.dp(48) on each axis, at every test profile (ADR 0004
## section 3; supersedes the 120 base px rule of ADR 0002 section 6). Each scene is added to the
## tree at the profile's window size, with the profile as the UiScale override.

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const MIN_DP: float = 48.0
const TOLERANCE_PX: float = 0.5
## The paths come from DevRoutes, so a moved or mistyped scene fails here instead of being skipped.
const REQUIRED_SCENES: Array[String] = [
	DevRoutes.MAIN_SCENE,
	DevRoutes.DEV_MENU_SCENE,
	DevRoutes.ART_GALLERY_SCENE,
	DevRoutes.TOUCH_PROBE_SCENE,
]

var _window_size_before: Vector2i


func before() -> void:
	assert_bool(UiScale.has_override()).override_failure_message("override leaked").is_false()
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()


func test_required_scenes_exist() -> void:
	for path: String in REQUIRED_SCENES:
		assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()


func test_every_visible_button_is_at_least_dp_48_at_every_profile() -> void:
	var too_small: Array[String] = []
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	for profile_name: StringName in profiles:
		var profile: UiMetrics = profiles[profile_name]
		UiScale.set_override(profile)
		get_window().size = profile.window_size
		await await_idle_frame()
		var min_px: float = UiScale.dp(MIN_DP) - TOLERANCE_PX
		for path: String in REQUIRED_SCENES:
			var root: Node = (load(path) as PackedScene).instantiate()
			add_child(root)
			await await_idle_frame()
			var found: Array[Node] = root.find_children("*", "BaseButton", true, false)
			var buttons: Array = found.filter(
				func(b: BaseButton) -> bool: return b.is_visible_in_tree()
			)
			var none_message: String = "no visible button in %s" % path
			assert_array(buttons).override_failure_message(none_message).is_not_empty()
			for button: BaseButton in buttons:
				if button.size.x < min_px or button.size.y < min_px:
					var where: String = "%s at %s" % [path, profile_name]
					too_small.append(
						"%s: %s is %s, needs %.1f" % [where, button.name, button.size, min_px]
					)
			remove_child(root)
			root.free()
	assert_array(too_small).is_empty()
