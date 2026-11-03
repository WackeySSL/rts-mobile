extends GdUnitTestSuite
## The economy line in the build drawer's head (plan P120d, ADR 0025 sections 3 and 5), in the main
## scene at every profile of both orientations: while the drawer is open the pill folds and the
## head shows the credits with "+N/min" and the power bar, the low-power look and the flash chip as
## the pill has them; the head stays 48 dp high and the line's text fits it; a value that did not
## change writes nothing. The match is paused, so only the snapshots a test writes are on show.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _feed: HudStateFeed
var _pill: EconomyPill
var _line: EconomyLine
var _tick: int = 0
var _serial: int = 1


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	if is_instance_valid(_main):
		_main.free()
	UiScale.clear_override()


func test_the_pill_folds_and_the_head_shows_credits_income_and_power() -> void:
	for profile: StringName in _every_profile():
		await _open(profile)
		_publish(1234, 40, 11, 0)
		_publish(1234, 40, 11, 300, Sim.TICK_RATE * 2)
		_pill._process(2.0)
		assert_bool(_pill.visible).override_failure_message(str(profile)).is_true()
		_feed.state.open(HudState.Unfold.DRAWER)
		await _frames()
		var why: String = str(profile)
		assert_bool(_pill.visible).override_failure_message(why).is_false()
		assert_bool(_line.is_visible_in_tree()).override_failure_message(why).is_true()
		(
			assert_str(_text("CreditsNumber"))
			. override_failure_message("%s: %s" % [why, _text("CreditsNumber")])
			. is_equal("1234")
		)
		var income: Label = _line.find_child("Income", true, false) as Label
		assert_str(income.text).override_failure_message(why).is_equal("+300/min")
		assert_str(_text("PowerText")).override_failure_message(why).is_equal("11/40")
		var bar: ProgressBar = _line.find_child("PowerBar", true, false) as ProgressBar
		assert_float(bar.value).is_equal(11.0)
		_feed.state.close(HudState.Unfold.DRAWER)
		await _frames()
		assert_bool(_pill.visible).override_failure_message(why).is_true()


func test_the_head_stays_48_dp_and_the_line_fits_it_at_every_screen() -> void:
	for profile: StringName in _every_profile():
		await _open(profile)
		_publish(99999, 88, 88, 0)
		_publish(99999, 88, 88, 99999, Sim.TICK_RATE * 2)
		_feed.state.open(HudState.Unfold.DRAWER)
		await _frames()
		var why: String = str(profile)
		var head: Control = _main.find_child("Head", true, false) as Control
		var close: Control = head.get_node("Close") as Control
		var dp: float = UiScale.dp(1.0)
		# Upright the handle and its gap stand over the line: the head is that much taller.
		var handle_dp: float = BuildSidebar.HANDLE_DP.y + BuildSidebar.HANDLE_GAP_DP
		var head_dp: float = 48.0 + (handle_dp if HudLayout.is_portrait() else 0.0)
		assert_float(head.size.y).override_failure_message(why).is_less_equal(head_dp * dp + 1.0)
		var line: Rect2 = _line.get_global_rect()
		assert_float(line.size.y).override_failure_message(why).is_less_equal(head.size.y + 0.5)
		assert_float(line.end.x).override_failure_message(why).is_less_equal(
			close.global_position.x + 0.5
		)
		(
			assert_float(_line.get_combined_minimum_size().x)
			. override_failure_message(why)
			. is_less_equal(_line.size.x + 0.5)
		)
		(
			assert_float(_line.get_combined_minimum_size().y)
			. override_failure_message(why)
			. is_less_equal(head.size.y + 0.5)
		)
		assert_bool(_line.mouse_filter == Control.MOUSE_FILTER_IGNORE).is_true()
		var numbers: Control = _line.find_child("PowerText", true, false) as Control
		assert_bool(numbers.visible).override_failure_message(why + ": power text").is_true()
		var column: Control = _line.find_child("Credits", true, false) as Control
		assert_float(column.get_combined_minimum_size().x).is_less_equal(column.size.x + 0.5)
		var back: Rect2 = (_main.find_child("Backdrop", true, false) as Control).get_global_rect()
		assert_bool(back.grow(0.5).encloses(line)).override_failure_message(why).is_true()


func test_low_power_shows_the_red_edge_the_triangle_and_the_pulse_in_the_head() -> void:
	await _open(&"android_6in")
	_publish(500, 4, 9, 0)
	_feed.state.open(HudState.Unfold.DRAWER)
	await _frames()
	assert_bool(_line.is_low()).is_true()
	assert_str(String(_line.theme_type_variation)).is_equal("EconomyPillLow")
	var glyph: TextureRect = _line.find_child("PowerGlyph", true, false) as TextureRect
	assert_str(glyph.texture.resource_path).contains("glyph_low_power")
	_pill._process(0.7)
	await _frames()
	assert_int(_pill.pulse_step()).is_greater(0)
	assert_object(_line.self_modulate).is_equal(_pill.self_modulate)
	_publish(500, 40, 9, 0)
	await _frames()
	assert_bool(_line.is_low()).is_false()
	assert_str(String(_line.theme_type_variation)).is_equal("EconomyPill")


func test_a_spend_shows_the_chip_in_the_head_for_the_flash_time() -> void:
	await _open(&"android_6in")
	_publish(1000, 40, 11, 0)
	_pill._process(2.0)  # The flash of the first number is over.
	_feed.state.open(HudState.Unfold.DRAWER)
	await _frames()
	_publish(400, 40, 11, 0)
	await _frames()
	var chip: Control = _line.chip()
	assert_bool(chip.visible).is_true()
	assert_str(_chip_text()).is_equal("-600")
	_pill._process(2.0)  # Past economy_flash_ms.
	await _frames()
	assert_bool(chip.visible).is_false()
	assert_str(_text("CreditsNumber")).is_equal("400")


func test_nothing_is_written_at_rest() -> void:
	await _open(&"android_6in")
	_publish(1234, 40, 11, 0)
	_pill._process(2.0)
	_feed.state.open(HudState.Unfold.DRAWER)
	await _frames()
	var credits: DigitRow = _line.find_child("CreditsNumber", true, false) as DigitRow
	var numbers: DigitRow = _line.find_child("PowerText", true, false) as DigitRow
	var before_credits: int = credits.writes
	var before_numbers: int = numbers.writes
	var sets: Vector3i = Vector3i(_line.credits_sets, _line.income_sets, _line.power_sets)
	assert_int(sets.x).is_greater(0)
	for i: int in 5:
		_line._process(0.016)
		await await_idle_frame()
	assert_int(credits.writes).is_equal(before_credits)
	assert_int(numbers.writes).is_equal(before_numbers)
	# The line's own guards: a frame at rest does not even hand the same value on.
	assert_int(_line.credits_sets).is_equal(sets.x)
	assert_int(_line.income_sets).is_equal(sets.y)
	assert_int(_line.power_sets).is_equal(sets.z)


## The line runs only while the drawer shows it.
func test_the_line_runs_only_while_the_drawer_is_open() -> void:
	await _open(&"android_6in")
	assert_bool(_line.is_processing()).is_false()
	_feed.state.open(HudState.Unfold.DRAWER)
	await _frames()
	assert_bool(_line.is_processing()).is_true()
	_feed.state.close(HudState.Unfold.DRAWER)
	await _frames()
	assert_bool(_line.is_processing()).is_false()


## On the narrowest phone the power numbers still show beside "+9999/min" (P85c's rule: the numbers
## where they fit, else the bar and the bolt alone).
func test_the_power_numbers_show_beside_a_four_digit_income_on_the_smallest_phone() -> void:
	for profile: StringName in [&"web_phone_small", &"web_phone_portrait"]:
		await _open(profile)
		_publish(9999, 999, 999, 0)
		_publish(9999, 999, 999, 9999, Sim.TICK_RATE * 2)
		_pill._process(2.0)
		_feed.state.open(HudState.Unfold.DRAWER)
		await _frames()
		var income: Label = _line.find_child("Income", true, false) as Label
		assert_str(income.text).is_equal("+9999/min")
		var numbers: Control = _line.find_child("PowerText", true, false) as Control
		assert_bool(numbers.visible).override_failure_message(str(profile)).is_true()


## The pill is folded: a tap where its credits were opens no card.
func test_a_tap_on_the_folded_pill_opens_no_card() -> void:
	for profile: StringName in [&"android_6in", &"android_6in_portrait"]:
		await _open(profile)
		_publish(500, 40, 11, 0)
		var tap: Control = _pill.find_child("CreditsTap", true, false) as Control
		var at: Vector2 = tap.get_global_rect().get_center()
		_feed.state.open(HudState.Unfold.DRAWER)
		await _frames()
		assert_bool(tap.is_visible_in_tree()).is_false()
		TouchEvents.press(get_viewport(), 0, at)
		TouchEvents.release(get_viewport(), 0, at)
		await _frames()
		var card: Control = _main.get_node("Hud/EconomyCard") as Control
		assert_bool(card.visible).override_failure_message(str(profile)).is_false()
		assert_bool(_feed.state.is_open(HudState.Unfold.ECONOMY)).is_false()


## A turn with the drawer open: the pill stays folded and the line shows the same economy in the
## other layout; closing the drawer brings the pill back where a closed drawer has it there.
func test_a_turn_with_the_drawer_open_keeps_the_line_and_the_pill_consistent() -> void:
	await _open(&"android_6in_portrait")
	_publish(1234, 40, 11, 0)
	_pill._process(2.0)
	await _frames()
	var upright: Rect2 = _pill.get_global_rect()
	await _turn(&"android_6in")
	var sideways: Rect2 = _pill.get_global_rect()
	_feed.state.open(HudState.Unfold.DRAWER)
	await _frames()
	for profile: StringName in [&"android_6in_portrait", &"android_6in", &"android_6in_portrait"]:
		await _turn(profile)
		assert_bool(_pill.visible).override_failure_message(str(profile)).is_false()
		assert_bool(_line.is_visible_in_tree()).is_true()
		assert_str(_text("CreditsNumber")).is_equal("1234")
		assert_str(_text("PowerText")).is_equal("11/40")
		var head: Control = _main.find_child("Head", true, false) as Control
		assert_bool(head.get_global_rect().grow(0.5).encloses(_line.get_global_rect())).is_true()
	_feed.state.close(HudState.Unfold.DRAWER)
	await _frames()
	assert_bool(_pill.visible).is_true()
	assert_vector(_pill.get_global_rect().position).is_equal_approx(upright.position, Vector2.ONE)
	assert_vector(_pill.get_global_rect().size).is_equal_approx(upright.size, Vector2.ONE)
	await _turn(&"android_6in")
	assert_vector(_pill.get_global_rect().position).is_equal_approx(sideways.position, Vector2.ONE)


## Upright the handle is centred on the sheet and stands over the line, not on it; the flash chip is
## in the drawer's clip (not top-level) so the slide hides it with the rest.
func test_the_handle_is_centred_and_clear_of_the_line_and_the_chip_is_clipped() -> void:
	for profile: StringName in [&"android_6in_portrait", &"web_phone_portrait"]:
		await _open(profile)
		_feed.state.open(HudState.Unfold.DRAWER)
		await _frames()
		var handle: Control = _main.find_child("Handle", true, false) as Control
		var back: Rect2 = (_main.find_child("Backdrop", true, false) as Control).get_global_rect()
		assert_bool(handle.visible).is_true()
		var middle: float = handle.get_global_rect().get_center().x
		assert_float(middle).override_failure_message(str(profile)).is_equal_approx(
			back.get_center().x, 1.0
		)
		var line: Rect2 = _line.get_global_rect()
		assert_float(handle.get_global_rect().end.y).override_failure_message(str(profile)).is_less(
			line.position.y
		)
		var chip: Control = _line.chip()
		assert_bool(chip.top_level).is_false()
		assert_bool(_sidebar().is_ancestor_of(chip)).is_true()
		var tabs: Control = _main.find_child("Tabs", true, false) as Control
		_publish(1000, 40, 11, 0)
		_pill._process(2.0)
		_publish(400, 40, 11, 0)
		await _frames()
		assert_bool(chip.visible).is_true()
		# It draws after the tabs it hangs over, and lies inside the drawer.
		assert_bool(chip.is_greater_than(tabs)).override_failure_message(str(profile)).is_true()
		assert_bool(back.grow(0.5).encloses(chip.get_global_rect())).is_true()


func _sidebar() -> Control:
	return _main.get_node("Hud/BuildSidebar") as Control


func _turn(profile: StringName) -> void:
	var metrics: UiMetrics = UiProfiles.by_name(profile)
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await _frames()


func _text(node_name: String) -> String:
	return (_line.find_child(node_name, true, false) as DigitRow).text


func _chip_text() -> String:
	return (_line.chip().find_child("FlashText", true, false) as DigitRow).text


func _publish(credits: int, made: int, used: int, harvested: int, tick: int = -1) -> void:
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.credits = PackedInt32Array([0, credits, 0])
	snap.power_made = PackedInt32Array([0, made, 0])
	snap.power_used = PackedInt32Array([0, used, 0])
	snap.stat_harvested = PackedInt32Array([0, harvested, 0])
	_tick = _tick + 1 if tick < 0 else tick
	snap.tick = _tick
	snap.match_serial = _serial
	_runner.snapshot = snap
	_pill.refresh()


func _frames() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _every_profile() -> Array[StringName]:
	var names: Array[StringName] = []
	for profile: StringName in UiProfiles.all():
		names.append(profile)
	for profile: StringName in UiProfiles.portrait():
		names.append(profile)
	return names


func _open(profile: StringName) -> void:
	if is_instance_valid(_main):
		_main.free()
	var metrics: UiMetrics = UiProfiles.by_name(profile)
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	_runner = _main.get_node("MatchRunner")
	_pill = _main.get_node("Hud/EconomyPill")
	_feed = _main.get_node("Hud/HudStateFeed")
	_line = _main.find_child("Economy", true, false) as EconomyLine
	_tick = 0
