extends GdUnitTestSuite
## IntroPlayer and the consent form (Michael, 2026-11-19: the dev APK hung at boot on the test
## consent form, its Accept dead to a finger). A tap always stops the intro's motion; while consent
## runs the intro does not keep the tap, so a form drawn above it gets it too. Taps go through the
## viewport as a finger's do (TouchEvents), never into `_input` directly.

const MENU_PATH: String = "res://scenes/menu/main_menu.tscn"
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")

var _rig: IntroRig = IntroRig.new()
var _size: Vector2 = Vector2(ScreenSizes.ALL[0])
var _window_size_before: Vector2i
var _ump: FakeUmp = null


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	var profile: UiMetrics = _profile_with_window(Vector2i(_size))
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	_rig.setup(self, load(MENU_PATH) as PackedScene, _size)
	_ump = null


func after_test() -> void:
	if _ump != null:
		_ump.close_unchanged()
	_rig.teardown(self)
	UiScale.clear_override()


## The fake consent call of the dev APK: the info update, then the form, then its answer.
func _consent_through_form() -> bool:
	_ump.update_info(false)
	_ump.show_form()
	await _ump.form_dismissed
	return _ump.can_request_ads()


func test_accept_on_the_consent_form_takes_a_finger_while_the_intro_runs() -> void:
	_ump = FakeUmp.new()
	_ump.consent_required = true
	_ump.auto_close = false
	_ump.draw_placeholders = true
	_ump.host = _rig.host
	var player: IntroPlayer = _rig.make(self, _size, false, false, _consent_through_form)
	_rig.at(player, 0)
	var accept: Button = _form_button(&"Accept")
	assert_object(accept).override_failure_message("the form is drawn").is_not_null()
	assert_bool(player.consent_done()).is_false()
	var dismissed: Array[bool] = [false]
	_ump.form_dismissed.connect(func() -> void: dismissed[0] = true)
	_tap(accept.get_global_rect().get_center())
	await get_tree().process_frame
	assert_bool(dismissed[0]).override_failure_message("Accept took the tap").is_true()
	assert_bool(_ump.can_request_ads()).is_true()
	await get_tree().process_frame
	assert_bool(player.consent_done()).is_true()


func test_a_tap_while_consent_runs_still_stops_the_intro_motion() -> void:
	var player: IntroPlayer = _rig.make(self, _size, false, true)
	_rig.at(player, 0)
	assert_bool(player.consent_done()).is_false()
	assert_int(player.phase).is_equal(IntroPlayer.Phase.DRIVE)
	_tap(_size * 0.5)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.SETTLED)


func test_a_tap_after_consent_still_skips_the_intro() -> void:
	var player: IntroPlayer = _rig.make(self, _size)
	_rig.at(player, 0)
	assert_bool(player.consent_done()).is_true()
	assert_int(player.phase).is_equal(IntroPlayer.Phase.DRIVE)
	_tap(_size * 0.5)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.SETTLED)


func _tap(at_base: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, at_base)
	TouchEvents.release(get_viewport(), 0, at_base)


func _form_button(caption: StringName) -> Button:
	for child: Node in _rig.host.get_children():
		if child is FakeConsentForm:
			return child.find_child(String(caption), true, false) as Button
	return null


func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	return null
