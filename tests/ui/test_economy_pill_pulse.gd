extends GdUnitTestSuite
## The economy pill's low-power pulse (plan P89, ADR 0025 section 3): on low power the pill's own
## drawing (the whole plate and edge) and the warning triangle breathe between white and the pill
## type's `pulse_dim` colour in PULSE_STEPS steps over PULSE_MS, through `self_modulate` so that
## the word and the numbers stay full. The tint is written only when the step changes, a long frame
## wraps, and the wave starts over when power is enough again. Frame time only: the sim is not
## asked.

const SENTINEL: Color = Color(0.123, 0.5, 0.5, 0.77)

var _pill: EconomyPill


func before_test() -> void:
	_pill = auto_free(EconomyPill.new())
	_pill.theme = load("res://game/ui/theme.tres")
	_pill.set_process(false)
	add_child(_pill)


## The alpha of the pill type's `pulse_dim` colour, the dimmest step.
func _dimmest() -> float:
	return _pill.get_theme_color(&"pulse_dim", EconomyPill.VARIATION).a


func _glyph() -> TextureRect:
	return _pill._power_glyph


func test_it_is_full_and_still_while_power_is_enough() -> void:
	for frame: int in 30:
		_pill._pulse(100.0)
	assert_float(_pill.self_modulate.a).is_equal(1.0)
	assert_float(_glyph().self_modulate.a).is_equal(1.0)
	assert_int(_pill.pulse_step()).is_equal(0)


func test_it_breathes_on_low_power_between_full_and_the_dimmest_step() -> void:
	_pill._low = true
	var lowest: float = 1.0
	var highest: float = 0.0
	for frame: int in int(EconomyPill.PULSE_MS / 20.0):
		_pill._pulse(20.0)
		lowest = minf(lowest, _pill.self_modulate.a)
		highest = maxf(highest, _pill.self_modulate.a)
	assert_float(lowest).is_equal_approx(_dimmest(), 0.001)
	assert_float(highest).is_equal(1.0)


## Border and triangle pulse; the word, the numbers and the bar are not touched.
func test_only_the_border_and_the_triangle_pulse_not_the_word() -> void:
	_pill._low = true
	_pill._pulse(EconomyPill.PULSE_MS / 2.0)
	assert_float(_pill.self_modulate.a).is_equal_approx(_dimmest(), 0.001)
	assert_float(_glyph().self_modulate.a).is_equal_approx(_dimmest(), 0.001)
	assert_that(_pill.self_modulate.r).is_equal(1.0)  # White: not tinted by the text token.
	for node_name: String in ["PowerWord", "PowerText", "PowerBar", "PowerTap"]:
		var node: CanvasItem = _pill.find_child(node_name, true, false)
		assert_that(node.modulate).override_failure_message(node_name).is_equal(Color.WHITE)
		assert_that(node.self_modulate).override_failure_message(node_name).is_equal(Color.WHITE)


## A node is written only when the step changes: a sentinel survives frames inside one step.
func test_the_tint_is_written_only_when_the_step_changes() -> void:
	_pill._low = true
	_pill._pulse(10.0)  # Step 0 still: the first step starts at 1/12 of the period.
	assert_int(_pill.pulse_step()).is_equal(0)
	_pill.self_modulate = SENTINEL
	_glyph().self_modulate = SENTINEL
	var kept: int = 0
	while _pill.pulse_step() == 0 and kept < 50:
		_pill._pulse(1.0)
		if _pill.pulse_step() == 0:
			assert_that(_pill.self_modulate).is_equal(SENTINEL)
			assert_that(_glyph().self_modulate).is_equal(SENTINEL)
			kept += 1
	assert_int(kept).is_greater(0)
	assert_int(_pill.pulse_step()).is_greater(0)
	assert_that(_pill.self_modulate).is_not_equal(SENTINEL)
	assert_that(_glyph().self_modulate).is_not_equal(SENTINEL)


func test_a_long_frame_wraps_into_the_period_and_stays_in_range() -> void:
	# 5000 ms and 1e6 ms land 800 and 400 ms into a 1400 ms period; 3.5 periods is the dimmest.
	var expected: Dictionary[float, int] = {5000.0: 5, 1e6: 3, EconomyPill.PULSE_MS * 3.5: 6}
	for ms: float in expected:
		_pill._low = true
		_pill._pulse(ms)
		assert_int(_pill.pulse_step()).override_failure_message(str(ms)).is_equal(expected[ms])
		assert_int(_pill.pulse_step()).is_between(0, EconomyPill.PULSE_STEPS)
		assert_float(_pill.self_modulate.a).is_between(_dimmest() - 0.001, 1.001)
		assert_float(_glyph().self_modulate.a).is_between(_dimmest() - 0.001, 1.001)
		_pill._low = false
		_pill._pulse(16.0)


func test_the_wave_starts_over_when_power_is_enough_again() -> void:
	_pill._low = true
	_pill._pulse(EconomyPill.PULSE_MS * 0.3)
	_pill._low = false
	_pill._pulse(16.0)
	assert_float(_pill.self_modulate.a).is_equal(1.0)
	assert_int(_pill.pulse_step()).is_equal(0)
	_pill._low = true
	_pill._pulse(EconomyPill.PULSE_MS / 2.0)  # From a restart this is the dimmest point.
	assert_int(_pill.pulse_step()).is_equal(EconomyPill.PULSE_STEPS)
	assert_float(_pill.self_modulate.a).is_equal_approx(_dimmest(), 0.001)


func test_it_returns_to_full_when_power_is_enough_again() -> void:
	_pill._low = true
	_pill._pulse(EconomyPill.PULSE_MS / 2.0)  # The dimmest point.
	assert_float(_pill.self_modulate.a).is_less(1.0)
	_pill._low = false
	_pill._pulse(16.0)
	assert_float(_pill.self_modulate.a).is_equal(1.0)
	assert_float(_glyph().self_modulate.a).is_equal(1.0)
	assert_int(_pill.pulse_step()).is_equal(0)
