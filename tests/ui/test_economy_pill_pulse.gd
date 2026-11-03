extends GdUnitTestSuite
## The economy pill's low-power pulse (plan P89, ADR 0025 section 3): on low power the power area
## breathes between full alpha and the theme token pulse_dim in PULSE_STEPS steps over PULSE_MS,
## writes its tint only when the step changes, and is full again, with the wave restarted, when
## power is enough. Frame time only: the sim is not asked.

var _pill: EconomyPill


func before_test() -> void:
	_pill = auto_free(EconomyPill.new())
	_pill.theme = load("res://game/ui/theme.tres")
	_pill.set_process(false)
	add_child(_pill)


## The alpha of the theme's `pulse_dim` token, the dimmest step.
func _dimmest() -> float:
	return _pill.get_theme_color(&"pulse_dim", &"HudTokens").a


func _area() -> Control:
	return _pill._power_tap


func test_it_is_full_and_still_while_power_is_enough() -> void:
	for frame: int in 30:
		_pill._pulse(100.0)
	assert_float(_area().modulate.a).is_equal(1.0)
	assert_int(_pill.pulse_step()).is_equal(0)


func test_it_breathes_on_low_power_between_full_and_the_dimmest_step() -> void:
	_pill._low = true
	var lowest: float = 1.0
	var highest: float = 0.0
	for frame: int in int(EconomyPill.PULSE_MS / 20.0):
		_pill._pulse(20.0)
		lowest = minf(lowest, _area().modulate.a)
		highest = maxf(highest, _area().modulate.a)
	assert_float(lowest).is_equal_approx(_dimmest(), 0.001)
	assert_float(highest).is_equal(1.0)


func test_the_alpha_is_written_only_when_the_step_changes() -> void:
	_pill._low = true
	var steps: int = 0
	var last: int = _pill.pulse_step()
	for frame: int in 3 * int(EconomyPill.PULSE_MS / 10.0):  # Three periods in 10 ms frames.
		_pill._pulse(10.0)
		if _pill.pulse_step() != last:
			steps += 1
			last = _pill.pulse_step()
	# Up and down PULSE_STEPS steps each period, never one write a frame.
	assert_int(steps).is_less_equal(3 * 2 * EconomyPill.PULSE_STEPS)
	assert_int(steps).is_greater(0)


func test_it_returns_to_full_when_power_is_enough_again() -> void:
	_pill._low = true
	_pill._pulse(EconomyPill.PULSE_MS / 2.0)  # The dimmest point.
	assert_float(_area().modulate.a).is_less(1.0)
	_pill._low = false
	_pill._pulse(16.0)
	assert_float(_area().modulate.a).is_equal(1.0)
	assert_int(_pill.pulse_step()).is_equal(0)
