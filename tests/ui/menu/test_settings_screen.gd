extends GdUnitTestSuite
## The Settings screen (plan P526) at the six sizes of ADR 0015 section 6: 48 dp rows inside the
## safe area, the foot slot at the safe bottom; each switch saves and reloads; the Privacy row
## follows the consent service and its tap awaits the form; Developer is gated; a route nobody
## registered leaves its button disabled; and the screen names no ad call but the privacy ones.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const SAVE_SCRIPT: String = "res://game/meta/save_service.gd"
const SOURCES: Array[String] = [
	"res://game/ui/menu/SettingsScreen.gd", "res://game/ui/menu/MenuPrefs.gd"
]
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")
const AdBandAsserts: GDScript = preload("res://tests/ui/support/ad_band_asserts.gd")
const TOLERANCE_PX: float = 0.5
## The ad calls the screen must not make (the two privacy calls are the only ones it may).
const AD_CALLS: String = (
	"show_banner|hide_banner|maybe_show_interstitial|show_rewarded|rewarded_ready|"
	+ "purchase_remove_ads|restore_purchases|ensure_consent|take_start_credits_bonus|"
	+ "grant_start_credits_bonus|note_match_completed|banner_height"
)


## A consent service that answers `required` and keeps its form open until `release`.
class FakeAds:
	extends Node
	signal release
	var required: bool = false
	var opened: int = 0
	var closed: int = 0

	func is_privacy_options_required() -> bool:
		return required

	func show_privacy_options() -> void:
		opened += 1
		await release
		closed += 1


## A route factory as a plain method: a lambda is refused by the route table.
class ScreenMaker:
	extends RefCounted
	var made: int = 0

	func make() -> MenuScreen:
		made += 1
		return MenuScreen.new()


## An audio service that records the steps it is given.
class FakeAudio:
	extends Node
	var settings: AudioSettings = AudioSettings.new()
	var steps: Dictionary = {&"Music": 7, &"Sfx": 10}
	var sound_sets: Array[int] = []

	func get_step(bus: StringName) -> int:
		return steps.get(bus, 0)

	func set_step(bus: StringName, step: int) -> void:
		steps[bus] = step

	func set_sound_step(step: int) -> void:
		sound_sets.append(step)
		steps[&"Sfx"] = step


var _window_size_before: Vector2i
var _quit_on_go_back_before: bool = true
var _menu: Control
var _stack: MenuStack
var _screen: SettingsScreen
var _routes: MenuRoutes
var _ads: FakeAds
var _audio: FakeAudio
var _dev: Array[bool] = [true]
var _dev_opened: Array[int] = [0]
var _in_match: Array[bool] = [false]
var _service: Node
var _harness: RefCounted


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_quit_on_go_back_before = get_tree().quit_on_go_back
	PrefsRig.begin()
	_routes = MenuRoutes.new()
	_ads = FakeAds.new()
	_audio = FakeAudio.new()
	_dev[0] = true
	_dev_opened[0] = 0
	_in_match[0] = false


func after_test() -> void:
	get_tree().quit_on_go_back = _quit_on_go_back_before
	UiScale.clear_override()
	_close()
	if is_instance_valid(_ads):
		_ads.free()
	if is_instance_valid(_audio):
		_audio.free()
	if is_instance_valid(_service):
		_service.free()
	if _harness != null:
		_harness.dispose()
		_harness = null
	PrefsRig.end()


func test_rows_and_slot_hold_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size))
		var label: String = str(size)
		var safe: Rect2 = UiScale.safe_rect_base()
		var floor_px: float = UiScale.dp(48.0) - TOLERANCE_PX
		assert_bool(safe.grow(TOLERANCE_PX).encloses(_screen.scroll.get_global_rect())).is_true()
		var column: Rect2 = _screen.column.get_global_rect()
		assert_float(column.position.x).override_failure_message(label).is_greater_equal(
			safe.position.x - TOLERANCE_PX
		)
		assert_float(column.end.x).override_failure_message(label).is_less_equal(
			safe.end.x + TOLERANCE_PX
		)
		var rows: int = 0
		for child: Node in _screen.column.get_children():
			var control: Control = child as Control
			if control is Label or not control.visible:
				continue
			rows += 1
			(
				assert_float(control.get_global_rect().size.y)
				. override_failure_message("%s %s" % [label, control.name])
				. is_greater_equal(floor_px)
			)
		assert_int(rows).override_failure_message(label).is_greater_equal(5)
		for slider: HSlider in [_screen.sound_slider, _screen.music_slider]:
			(
				assert_float(slider.get_global_rect().size.y)
				. override_failure_message(label)
				. is_greater_equal(floor_px)
			)
		for toggle: Button in [_screen.vibration_toggle, _screen.reduced_toggle]:
			(
				assert_float(toggle.get_global_rect().size.y)
				. override_failure_message(label)
				. is_greater_equal(floor_px)
			)
			assert_bool(toggle.text in ["ON", "OFF"]).is_true()
		var slot: AdBannerSlot = _screen.slot
		assert_bool(slot.has_band()).is_false()
		assert_float(slot.size.y).override_failure_message(label).is_equal_approx(0.0, 0.01)
		assert_float(slot.get_global_rect().end.y).override_failure_message(label).is_equal_approx(
			safe.end.y, TOLERANCE_PX
		)
		assert_bool(_screen.purchase_slot.visible).is_false()
		assert_float(_screen.purchase_slot.size.y).is_equal_approx(0.0, 0.01)
		_close()
		UiScale.clear_override()


func test_a_hosted_band_lines_up_at_the_safe_bottom_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size))
		var band: AdBannerBand = _real_band()
		assert_bool(_screen.slot.host(band)).is_true()
		await await_idle_frame()
		await await_idle_frame()
		AdBandAsserts.assert_lines_up(
			self, band, _service, _screen.scroll, band.gap_dp(), str(size)
		)
		_close()
		UiScale.clear_override()


func test_sliders_save_apply_and_reload() -> void:
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]))
	assert_int(int(_screen.music_slider.value)).is_equal(7)  # Nothing saved: the service's step.
	assert_int(int(_screen.sound_slider.value)).is_equal(10)
	assert_float(_screen.sound_slider.max_value).is_equal(10.0)
	_screen.sound_slider.value = 3.0
	_screen.music_slider.value = 0.0
	assert_array(_audio.sound_sets).is_equal([3])
	assert_int(_audio.steps[&"Music"]).is_equal(0)
	_flush()
	assert_int(_saved_on_disk("settings", "sound_step")).is_equal(3)
	assert_int(_saved_on_disk("settings", "music_step")).is_equal(0)
	_close()
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]))
	assert_int(int(_screen.sound_slider.value)).is_equal(3)
	assert_int(int(_screen.music_slider.value)).is_equal(0)
	var other: FakeAudio = auto_free(FakeAudio.new())
	MenuPrefs.apply_audio(other)
	assert_array(other.sound_sets).is_equal([3])
	assert_int(other.steps[&"Music"]).is_equal(0)


func test_vibration_and_reduced_effects_save_and_reload() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	assert_bool(_screen.vibration_toggle.button_pressed).is_true()
	assert_str(_screen.vibration_toggle.text).is_equal("ON")
	assert_bool(_screen.reduced_toggle.button_pressed).is_false()
	assert_str(_screen.reduced_toggle.text).is_equal("OFF")
	_screen.vibration_toggle.button_pressed = false
	_screen.reduced_toggle.button_pressed = true
	assert_str(_screen.vibration_toggle.text).is_equal("OFF")
	assert_str(_screen.reduced_toggle.text).is_equal("ON")
	assert_bool(HudPrefs.haptics_enabled()).is_false()
	assert_bool(MenuPrefs.reduced_effects()).is_true()
	_flush()
	assert_bool(_saved_on_disk("hud", "haptics")).is_false()
	assert_bool(_saved_on_disk("settings", "reduced")).is_true()
	_close()
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	assert_bool(_screen.vibration_toggle.button_pressed).is_false()
	assert_bool(_screen.reduced_toggle.button_pressed).is_true()


func test_the_privacy_row_shows_only_when_required_and_its_tap_awaits_the_form() -> void:
	_ads.required = false
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]))
	assert_bool(_screen.privacy_button.visible).is_false()
	_close()
	_ads.required = true
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]))
	assert_bool(_screen.privacy_button.visible).is_true()
	assert_float(_screen.privacy_button.get_global_rect().size.y).is_greater_equal(
		UiScale.dp(48.0) - TOLERANCE_PX
	)
	_screen.privacy_button.pressed.emit()
	_screen.privacy_button.pressed.emit()  # A second tap while the form is open does nothing.
	assert_int(_ads.opened).is_equal(1)
	assert_int(_ads.closed).is_equal(0)
	_ads.required = false  # The choice made in the form.
	_ads.release.emit()
	await await_idle_frame()
	assert_int(_ads.closed).is_equal(1)
	assert_bool(_screen.privacy_button.visible).is_false()


func test_developer_shows_only_in_dev_builds() -> void:
	_dev[0] = false
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	assert_object(_button("DEVELOPER")).is_null()
	_close()
	_dev[0] = true
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	var button: Button = _button("DEVELOPER")
	assert_object(button).is_not_null()
	assert_bool(button.disabled).is_false()
	assert_float(button.get_global_rect().size.y).is_greater_equal(UiScale.dp(48.0) - TOLERANCE_PX)
	button.pressed.emit()
	assert_int(_dev_opened[0]).is_equal(1)


func test_unregistered_routes_leave_their_buttons_disabled_and_a_registered_one_opens() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	for text: String in ["REPLAY TUTORIAL", "HOW TO PLAY", "LICENCES"]:
		assert_bool(_button(text).disabled).override_failure_message(text).is_true()
	var maker: ScreenMaker = ScreenMaker.new()  # A method, never a lambda (P524b).
	_routes.register(MenuRoutes.LICENCES, Callable(maker, "make"))
	assert_bool(_button("LICENCES").disabled).is_false()
	assert_bool(_button("REPLAY TUTORIAL").disabled).is_true()
	_button("LICENCES").pressed.emit()
	await await_idle_frame()
	assert_int(maker.made).is_equal(1)


func test_the_app_registers_the_settings_route() -> void:
	var routes: MenuRoutes = MenuRoutes.new()
	MenuRoutesDefaults.register(routes)
	assert_bool(routes.has(MenuRoutes.SETTINGS)).is_true()
	var screen: MenuScreen = routes.make(MenuRoutes.SETTINGS)
	assert_object(screen).is_instanceof(SettingsScreen)
	screen.free()


func test_the_screen_names_no_ad_call_but_the_privacy_ones() -> void:
	var pattern: RegEx = RegEx.create_from_string("\\b(" + AD_CALLS + ")\\b")
	for path: String in SOURCES:
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			(
				assert_object(pattern.search(line))
				. override_failure_message("%s: %s" % [path, line])
				. is_null()
			)
	var source: String = FileAccess.get_file_as_string(SOURCES[0])
	assert_bool(source.contains("is_privacy_options_required")).is_true()
	assert_bool(source.contains('await ad_service.call("show_privacy_options")')).is_true()


func _open(profile: UiMetrics) -> void:
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	_screen = SettingsScreen.new()
	_screen.routes = _routes
	_screen.ad_service = _ads
	_screen.audio = _audio
	_screen.dev_enabled = func() -> bool: return _dev[0]
	_screen.in_match = func() -> bool: return _in_match[0]
	_screen.open_dev = func() -> void: _dev_opened[0] += 1
	_stack.push(_screen)
	for _frame: int in range(3):
		await await_idle_frame()


func _close() -> void:
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null


func _button(text: String) -> Button:
	for child: Node in _screen.column.get_children():
		if child is Button and (child as Button).text == text:
			return child as Button
	return null


func _flush() -> void:
	assert_int(SaveService.flush()).is_equal(OK)


## What a fresh service reads from the file on disk (not the live one's memory).
func _saved_on_disk(section: String, key: String) -> Variant:
	var fresh: Node = auto_free((load(SAVE_SCRIPT) as GDScript).new())
	fresh.call("set_path_override", PrefsRig.path())
	add_child(fresh)
	return (fresh.call("get_section", section) as Dictionary).get(key)


## A real band with the fake ad service injected; its "Test ad" strip stands for the banner.
func _real_band() -> AdBannerBand:
	if not is_instance_valid(_service):
		_harness = (load("res://tests/ads/ad_service_harness.gd") as GDScript).new()
		_service = _harness.make(true)
		_service.fake_auto_close = false
		add_child(_service)
	var band: AdBannerBand = AdBannerBand.new()
	band.service = _service
	return band


func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	return null


func test_the_purchase_slot_shows_with_a_visible_child_and_is_0_tall_without() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	var slot: VBoxContainer = _screen.purchase_slot
	assert_str(String(slot.name)).is_equal("PurchaseSlot")
	var child: Control = Control.new()
	child.custom_minimum_size = Vector2(10.0, 60.0)
	slot.add_child(child)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(slot.visible).is_true()
	assert_float(slot.size.y).is_greater_equal(60.0)
	child.visible = false
	await await_idle_frame()
	assert_bool(slot.visible).is_false()
	child.visible = true
	await await_idle_frame()
	assert_bool(slot.visible).is_true()
	slot.remove_child(child)
	child.free()
	await await_idle_frame()
	assert_bool(slot.visible).is_false()


func test_saved_steps_out_of_range_are_clamped() -> void:
	MenuPrefs.set_sound_step(15)
	MenuPrefs.set_music_step(-2)
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]))
	assert_int(int(_screen.sound_slider.value)).is_equal(10)
	assert_int(int(_screen.music_slider.value)).is_equal(0)


func test_freeing_the_screen_during_the_privacy_await_is_safe() -> void:
	_ads.required = true
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]))
	_screen.privacy_button.pressed.emit()
	assert_int(_ads.opened).is_equal(1)
	_close()  # Frees the screen and its stack while the form is open.
	_ads.release.emit()
	await await_idle_frame()
	assert_int(_ads.closed).is_equal(1)


func test_menu_flow_applies_the_saved_steps_to_the_audio_service() -> void:
	var audio: Node = get_tree().root.get_node("AudioService")
	var music_before: int = audio.call("get_step", &"Music")
	var sound_before: int = audio.call("get_step", &"Sfx")
	MenuPrefs.set_music_step(3)
	MenuPrefs.set_sound_step(4)
	var flow: Node = (load("res://game/ui/menu/menu_flow_service.gd") as GDScript).new()
	add_child(flow)  # Its _ready is the boot path.
	assert_int(audio.call("get_step", &"Music")).is_equal(3)
	assert_int(audio.call("get_step", &"Sfx")).is_equal(4)
	remove_child(flow)
	flow.free()
	audio.call("set_step", &"Music", music_before)
	audio.call("set_sound_step", sound_before)


func test_in_a_match_neither_the_privacy_row_nor_the_purchase_slot_is_built() -> void:
	_ads.required = true
	_in_match[0] = true
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]))
	assert_object(_screen.privacy_button).is_null()
	assert_object(_screen.purchase_slot).is_null()
	assert_object(_screen.column.find_child("PurchaseSlot", false, false)).is_null()
	assert_bool(_button("PRIVACY OPTIONS") == null).is_true()
	assert_object(_screen.sound_slider).is_not_null()  # The plain settings stay.
	assert_object(_button("HOW TO PLAY")).is_not_null()
	_close()
	_in_match[0] = false  # From the main menu both are built again.
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]))
	assert_bool(_screen.privacy_button.visible).is_true()
	assert_object(_screen.purchase_slot).is_not_null()


func test_the_default_match_check_asks_the_menu_flow() -> void:
	var screen: SettingsScreen = auto_free(SettingsScreen.new())
	assert_bool(screen.in_match.call()).is_equal(MenuFlow.current_runner() != null)
