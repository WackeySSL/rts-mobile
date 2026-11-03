extends "res://tests/ui/support/attack_suite.gd"
## The attack cues' detection (plan P123, ADR 0025 section 8), in the main scene: a SHOT, an IMPACT
## or a DIED on an own row outside the view raises one cue; the area and the interval are exact; two
## fronts hit in turn raise two cues; a steady attack keeps one cue up; a new match clears them; the
## rim wedge and the scope's ping point the way the screen does.


func test_a_hit_on_a_unit_out_of_view_raises_one_cue_with_a_toast() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	assert_bool(_toast.visible).is_false()
	_hit(_unit, _far())
	assert_bool(_cues.active).is_true()
	assert_str(_cues.title).is_equal("UNITS UNDER ATTACK")
	assert_bool(_toast.visible).is_true()
	var labels: Array[Node] = _toast.find_children("*", "Label", true, false)
	assert_str((labels[1] as Label).text).is_equal("Tap to jump there")


func test_a_building_is_named_and_an_impact_counts_like_a_shot() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	_tick([World.Event.IMPACT, 1, _far().x, _far().y, _building, 0, 0, 0])
	var snap: MatchSnapshot = _runner.snapshot
	var type_name: String = snap.type_names[snap.type_index[snap.index_of(_building)]]
	assert_str(_cues.title).is_equal(type_name.to_upper() + " UNDER ATTACK")


func test_no_cue_for_a_hit_in_view_an_enemy_row_or_a_missing_target() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	_hit(_unit, Vector2i(HOME.x * 1000 + 500, HOME.y * 1000 + 500))  # In view.
	_hit(_enemy, _far())
	_hit(0, _far())  # An impact on the ground has no target.
	_hit(987654, _far())  # A row that is gone.
	assert_bool(_cues.active).is_false()


## A lethal hit leaves a DIED and no row (the snapshot is published after REMOVE): it cues too,
## with the name of the building that fell. Not an enemy's death, not one in view, and not a
## construction site the player cancelled.
func test_the_death_of_an_own_row_out_of_view_cues_with_its_name() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	var far: Vector2i = _far()
	_tick([World.Event.DIED, 777, far.x, far.y, _unit_type, 2, 0, 0])  # An enemy's.
	_tick([World.Event.DIED, 777, 11500, 7500, _unit_type, 1, 0, 0])  # In view.
	_tick([World.Event.DIED, 777, far.x, far.y, _building_type, 1, 1, 0])  # A cancelled site.
	assert_bool(_cues.active).is_false()
	_tick([World.Event.DIED, 777, far.x, far.y, _unit_type, 1, 0, 0])
	assert_str(_cues.title).is_equal("UNITS UNDER ATTACK")
	_cues.advance(_feed.state.settings.attack_cue_ms + 1.0)
	_tick([World.Event.DIED, 778, far.x, far.y, _building_type, 1, 0, 0])
	var type_name: String = _runner.snapshot.type_names[_building_type]
	assert_str(_cues.title).is_equal(type_name.to_upper() + " UNDER ATTACK")


func test_a_repeat_in_the_area_raises_none_and_one_elsewhere_replaces() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	var settings: InputSettings = _feed.state.settings
	var reach: int = settings.attack_cue_area_tiles * 1000
	_hit(_unit, _far())
	var first: Vector2 = _cues.point
	_hit(_unit, _far() + Vector2i(reach - 500, 0))  # Just inside the area.
	assert_vector(_cues.point).is_equal(first)
	var aside: Vector2i = _far() + Vector2i(reach + 500, 0)
	_hit(_unit, aside)  # Just outside it.
	assert_vector(_cues.point).is_not_equal(first)
	# Within the interval the area stays quiet; after it, the same area raises again.
	var second: Vector2 = _cues.point
	_hit(_unit, aside + Vector2i(1000, 0))
	assert_vector(_cues.point).is_equal(second)
	_cues.advance(settings.attack_cue_ms + 1.0)
	_hit(_unit, aside + Vector2i(1000, 0))
	assert_bool(_cues.active).is_true()
	assert_vector(_cues.point).is_not_equal(second)


## The area and the interval are exact: a hit at the reach is another area; one at the interval is
## after it.
func test_the_area_and_the_interval_are_exact() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	var settings: InputSettings = _feed.state.settings
	var reach: int = settings.attack_cue_area_tiles * 1000
	_hit(_unit, _far())
	var first: Vector2 = _cues.point
	_hit(_unit, _far() + Vector2i(reach - 1, 0))
	assert_vector(_cues.point).is_equal(first)  # One milli-tile inside: the same area.
	_hit(_unit, _far() + Vector2i(reach, 0))
	assert_vector(_cues.point).is_not_equal(first)  # Exactly the reach: another.
	var second: Vector2 = _cues.point
	_cues.advance(settings.attack_cue_ms - 1.0)
	_hit(_unit, _far() + Vector2i(reach, 0))
	assert_bool(_cues.active).is_true()  # One ms short of the interval: a repeat, it keeps the cue.
	assert_float(_cues.remaining_ms()).is_equal(float(settings.attack_toast_ms))
	_cues.advance(float(settings.attack_toast_ms))  # The cue runs out.
	assert_bool(_cues.active).is_false()
	_hit(_unit, _far() + Vector2i(reach, 0))  # Exactly the interval after the cue: it raises.
	assert_bool(_cues.active).is_true()
	assert_vector(_cues.point).is_equal(second)


## Two fronts hit in turn: each raises one cue; the shown cue is not swapped on every hit.
func test_two_areas_hit_in_turn_raise_two_cues_and_the_shown_one_stays() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	var front_b: Vector2i = _far() + Vector2i(40000, 0)
	var emitted: int = _emitted
	for round: int in 4:
		_hit(_unit, _far())
		_hit(_unit, front_b)
		_cues.advance(100.0)
	assert_int(_emitted - emitted).is_equal(2)  # A, then B; no swap after.
	assert_vector(_cues.point).is_equal(IsoProjection.ground_to_px(front_b.x, front_b.y))


## A new match clears the cue and the areas it remembers.
func test_a_new_match_clears_the_cue_and_the_areas() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	_hit(_unit, _far())
	assert_bool(_cues.active).is_true()
	_runner.snapshot.match_serial += 1
	_tick([])
	assert_bool(_cues.active).is_false()
	_hit(_unit, _far())  # The same area, at once: a new match has no memory of it.
	assert_bool(_cues.active).is_true()


func test_a_steady_attack_keeps_the_cue_shown_on_every_frame() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	var emitted: int = -1
	for step: int in 150:  # Ten seconds of ticks at 15 Hz, a hit in each.
		_cues.advance(1000.0 / 15.0)
		if step > 0:
			assert_bool(_cues.active).override_failure_message("frame %d" % step).is_true()
		_hit(_unit, _far())
		if step == 0:
			emitted = _emitted
	assert_int(_emitted).is_equal(emitted)  # One cue, never replaced or dropped.


func test_the_cue_ends_after_attack_toast_ms() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	var ms: float = float(_feed.state.settings.attack_toast_ms)
	_hit(_unit, _far())
	_cues.advance(ms - 1.0)
	assert_bool(_toast.visible).is_true()
	_cues.advance(2.0)
	assert_bool(_cues.active).is_false()
	assert_bool(_toast.visible).is_false()


## The rim wedge points the way the screen does, in both orientations, in three directions each:
## the offset on the scope has the angle of the hit from the camera's centre, and the scope redraws.
func test_the_rim_wedge_points_the_way_the_screen_does_in_both_orientations() -> void:
	for size: Vector2i in [ScreenSizes.LANDSCAPE[0], ScreenSizes.PORTRAIT[0]]:
		await _open(size)
		var centre: Vector2i = IsoProjection.px_to_ground(_camera.position)
		for step: Vector2i in [Vector2i(-40000, 0), Vector2i(40000, 0), Vector2i(0, -40000)]:
			_cues.dismiss()
			var draws: int = _scope.draw_count()
			_hit(_unit, centre + step)
			await _settle()
			var why: String = "%s, step %s" % [size, step]
			assert_int(_scope.draw_count()).override_failure_message(why).is_greater(draws)
			assert_bool(_scope.cue_on_rim()).override_failure_message(why).is_true()
			var want: Vector2 = _cues.point - _camera.position
			var offset: Vector2 = _scope.cue_offset()
			assert_float(offset.angle()).override_failure_message(why).is_equal_approx(
				want.angle(), 0.01
			)
			assert_bool(signf(offset.x) == signf(want.x)).override_failure_message(why).is_true()
			assert_bool(signf(offset.y) == signf(want.y)).override_failure_message(why).is_true()
		_cues.dismiss()
		assert_vector(_scope.cue_offset()).is_equal(Vector2.ZERO)


## A hit out of view but inside the scope's radius is a ring on the scope, not a wedge.
func test_a_hit_inside_the_scope_is_a_ping_not_a_wedge() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	var centre: Vector2i = IsoProjection.px_to_ground(_camera.position)
	# 14 tiles south-east and south-west at once: straight down, 448 px, past a 720 px view's edge.
	_hit(_unit, centre + Vector2i(14000, 14000))
	await _settle()
	assert_bool(_cues.active).is_true()
	assert_bool(_scope.cue_on_rim()).is_false()
	assert_float(_scope.cue_offset().length()).is_greater(0.0)
	assert_float(_scope.cue_offset().length()).is_less(_scope.size.x * 0.5)
