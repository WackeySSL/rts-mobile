extends GdUnitTestSuite
## The economy line in the build drawer's head (plan P120d, ADR 0025 sections 3 and 5), in the main
## scene at every profile of both orientations: while the drawer is open the pill folds and the
## head shows the credits with "+N/min" and the power bar, the low-power look and the flash chip as
## the pill has them; the head stays 48 dp high and the line's text fits it; a value that did not
## change writes nothing. The match is paused, so only the snapshots a test writes are on show.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
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
		assert_float(head.size.y).override_failure_message(why).is_less_equal(48.0 * dp + 1.0)
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
	for i: int in 5:
		_line._process(0.016)
		await await_idle_frame()
	assert_int(credits.writes).is_equal(before_credits)
	assert_int(numbers.writes).is_equal(before_numbers)


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
