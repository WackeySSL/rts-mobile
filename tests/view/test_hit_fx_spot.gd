extends "res://tests/view/support/hit_fx_suite.gd"
## The place of the flash, the view rect and a death in the tick (plan P166): the flash is the
## event point, lifted and moved by the hash, inside the middle of the frame box.
## Fixture: support/hit_fx_suite.gd (Barracks 1 to 8 on a crafted sheet, all shown).


func test_the_flash_of_an_impact_is_the_lifted_event_point_moved_by_the_hash() -> void:
	var pinned: int = 0
	var here: Vector2i = Rig.position_of(_runner, 1) + Vector2i(250, 120)
	for id: int in range(1, 61):
		_hit_at(Effects.impact(here, SHELL, id, 1))
		var want: Array = _restate(id, here, SHELL, 1)
		assert_vector(_flash_spot()).override_failure_message("id %d" % id).is_equal_approx(
			want[0], Vector2(0.01, 0.01)
		)
		pinned += 1 if want[1] else 0
	assert_int(pinned).override_failure_message("ids the clamp left alone").is_greater(4)


func test_the_flash_of_a_rifle_shot_is_its_target_point_not_the_shooters() -> void:
	var pinned: int = 0
	var here: Vector2i = Rig.position_of(_runner, 1)
	var shooter_at: Vector2i = here + Vector2i(300, -200)
	var target_at: Vector2i = here + Vector2i(-100, 150)
	for shooter: int in range(1, 61):
		_hit_at(Effects.shot(shooter_at, target_at, RIFLE, shooter, 1))
		var want: Array = _restate(LifeClock.mix(shooter, START), target_at, RIFLE, 1)
		(
			assert_vector(_flash_spot())
			. override_failure_message("shooter %d" % shooter)
			. is_equal_approx(want[0], Vector2(0.01, 0.01))
		)
		pinned += 1 if want[1] else 0
	assert_int(pinned).override_failure_message("ids the clamp left alone").is_greater(4)


func test_hits_out_of_view_draw_nothing_and_do_not_push_out_the_ones_in_view() -> void:
	_camera.zoom = Vector2(4.0, 4.0)
	_camera.position = _centre(1)
	var view: Rect2 = _camera.visible_world_rect().grow(BuildingLayer.ANIM_MARGIN_PX)
	assert_bool(view.has_point(_centre(1))).is_true()
	var events: PackedInt32Array = _impact(1, 1)  # In view, first: the oldest if nothing is culled.
	for id: int in [3, 6, 7]:
		assert_bool(view.has_point(_centre(id))).override_failure_message("%d" % id).is_false()
		events.append_array(_impact(10 + id, id))
	_hit_at(events)
	assert_int(_of(HitFx.Style.FLASH)).is_equal(1)
	assert_int(_of(HitFx.Style.CHIP)).is_equal(IMPACT_CHIPS[0])


func test_a_death_in_the_tick_compacts_the_rows_and_the_hit_still_lands_on_its_building() -> void:
	# main.tscn's order: the hit layer ticks before BuildingLayer, so `row_of` is the first sync of
	# the tick. Building 1 (row 0) dies through the sim while building 2 is hit: 2 moves to row 0.
	_runner.ticked.disconnect(_buildings._on_ticked)
	_runner.ticked.disconnect(_air._on_ticked)
	_runner.ticked.connect(_inject)
	_runner.ticked.connect(_air._on_ticked)
	_runner.ticked.connect(_buildings._on_ticked)
	_inject_target = 2
	_camera.position = _centre(2)
	var world: World = _runner.world
	world.hp[world.index_of(1)] = 0
	_ring().clear()
	_runner.run_ticks(1)
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(snap.index_of(1)).is_equal(-1)
	assert_int(snap.index_of(2)).is_equal(0)
	assert_int(_buildings.row_of(1)).is_equal(-1)
	assert_int(_buildings.row_of(2)).is_equal(0)
	assert_int(_of(HitFx.Style.FLASH)).is_equal(1)
	var box: Rect2 = _buildings.frame_box(0)
	var inner: Rect2 = Rect2(box.get_center() - box.size * 0.25, box.size * 0.5)
	assert_bool(inner.grow(0.01).has_point(_flash_spot())).is_true()
	# And a hit on a building that is already gone (no row) draws nothing.
	_inject_target = 1
	_ring().clear()
	_runner.run_ticks(1)
	assert_int(_ring().count()).is_equal(0)
