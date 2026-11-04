extends "res://tests/view/support/damage_suite.gd"
## The collapse of a shown building (plan P165, ADR 0029 sections 8 to 10): the timed sequence on
## the node, the crater, the cap, the fog rule, sites and cancelled sites and the sprite writes.
## The puffs are test_collapse_fx.gd's. Fixture: support/damage_suite.gd.

const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const TICK_MS: float = 1000.0 / 15.0


func before_test() -> void:
	_life = (load("res://data/life_settings.tres") as LifeSettings).duplicate() as LifeSettings


func _crater_art() -> void:
	_layer.decals.crater_texture = ImageTexture.create_from_image(
		Image.create(8, 4, false, Image.FORMAT_RGBA8)
	)


## Kills the buildings `ids` in one tick and returns the tick; the layer takes them over.
func _kill(ids: Array) -> int:
	for id: int in ids:
		_runner.world.hp[_runner.world.index_of(id)] = 0
	_runner.run_ticks(1)
	_layer._process(0.0)
	return _runner.snapshot.tick


## Draws a frame `ms` of match time after the DIED of tick `died`.
func _frame(died: int, ms: float) -> void:
	var ticks: float = LifeClock.tick_ms(died) + ms
	ticks = ticks * float(Sim.TICK_RATE) / 1000.0
	Rig.at(_runner, floori(ticks), ticks - floorf(ticks))
	_layer._process(0.0)


func _shadows() -> int:
	return _layer.decals.shadow_count()


func test_the_sequence_sink_hide_and_free_runs_on_match_time() -> void:
	_open(_pair() + [[1, 22, 4]], {"anim": true, "head": true})  # A spare keeps the match going.
	_crater_art()
	var node: Node2D = _layer.building(1)
	var body: Sprite2D = _body(1)
	var whole: Rect2 = body.region_rect
	var offset: float = body.offset.y
	var rise: float = -body.get_rect().position.y * body.scale.y  # The picture's height.
	var shadows: int = _shadows()
	var died: int = _kill([1])
	assert_object(_layer.building(1)).is_null()  # No pick, no bar, not in the rows.
	assert_object(node.get_parent()).is_same(_sort)  # No node at DIED, and this one stays.
	assert_bool(node.get_node("Anim").visible).is_false()  # At 0: the Anim and the Head go.
	assert_bool(node.get_node("Head").visible).is_false()
	assert_float(body.offset.y).is_equal(offset)  # The sink has not begun.
	_frame(died, 200.0)
	assert_that(body.region_rect).is_equal(whole)
	_frame(died, 270.0)  # Step 1 of 6 at 250 ms.
	var rows: float = whole.size.y - body.region_rect.size.y
	assert_float(rows).is_greater(0.0)
	assert_float(body.offset.y - offset).is_equal_approx(rows, 0.001)  # Down by the rows cut.
	_frame(died, 640.0)  # Step 6, to 60 % of the rise.
	var sunk: float = (whole.size.y - body.region_rect.size.y) * body.scale.y
	assert_float(sunk).is_equal_approx(rise * 0.6, body.scale.y)
	assert_bool(node.visible).is_true()
	assert_int(_shadows()).is_equal(shadows)
	_frame(died, 710.0)  # Hidden at 700 ms and the shadow removed.
	assert_bool(node.visible).is_false()
	assert_int(_shadows()).is_equal(shadows - 1)
	assert_object(node.get_parent()).is_same(_sort)
	_frame(died, 910.0)  # Freed at 900 ms.
	assert_object(node.get_parent()).is_null()
	assert_int(_layer.collapse().count()).is_equal(0)
	assert_int(_layer.decals.crater_count()).is_equal(1)


func test_the_crater_is_laid_at_the_died_and_scaled_by_the_type() -> void:
	_life.crater_scale_milli = {&"barracks": 1500}
	_open(_pair() + [[1, 22, 4]])
	_crater_art()
	_kill([1])
	var crater: Sprite2D = _layer.decals._craters.get_child(0)
	var default_scale: float = 2.0 * BuildingLayer.CRATER_MILLI_PER_TILE / 1500.0
	assert_float(crater.scale.x).is_equal_approx(default_scale * 1.5, 0.0001)
	assert_vector(crater.position).is_equal(_layer.collapse().node_of(1).position)


func test_a_cancelled_site_plays_nothing_and_leaves_no_crater() -> void:
	_open(_pair() + [[1, 22, 4]])
	_crater_art()
	var node: Node2D = _layer.building(1)
	var shadows: int = _shadows()
	_runner.world.build_left[_runner.world.index_of(1)] = Production.CANCELLED
	_kill([1])
	assert_int(_layer.collapse().count()).is_equal(0)
	assert_int(_layer.decals.crater_count()).is_equal(0)
	assert_int(_shadows()).is_equal(shadows - 1)
	assert_object(node.get_parent()).is_null()


func test_a_site_that_dies_collapses_like_a_building_and_ends_in_the_crater() -> void:
	_open(_pair() + [[1, 22, 4]])
	_crater_art()
	_runner.world.build_left[_runner.world.index_of(1)] = 100000
	_runner.run_ticks(1)  # The layer notes that it is a site.
	_layer._process(0.0)
	var died: int = _kill([1])
	assert_int(_layer.collapse().count()).is_equal(1)
	_frame(died, 270.0)
	assert_int(_layer.collapse().step_of(1)).is_equal(1)
	_frame(died, 910.0)
	assert_int(_layer.collapse().count()).is_equal(0)
	assert_int(_layer.decals.crater_count()).is_equal(1)


func test_a_building_that_died_unseen_gets_no_collapse_and_no_crater() -> void:
	_open(_pair(), {}, 1.0, false)
	Dmg.Rig.see(_runner.snapshot, 1, [])
	_layer._process(0.0)
	_crater_art()
	var nodes: int = _sort.get_child_count()
	_kill([2])
	assert_int(_layer.collapse().count()).is_equal(0)
	assert_int(_layer.decals.crater_count()).is_equal(0)
	assert_int(_sort.get_child_count()).is_equal(nodes - 1)


func test_the_seventeenth_collapse_ends_the_oldest_and_its_crater_stays() -> void:
	_open(_grid(18))
	_crater_art()
	var first: Node2D = _layer.building(1)
	var ids: Array = []
	for id: int in range(1, 18):
		ids.append(id)
	_kill(ids)
	assert_int(_layer.collapse().count()).is_equal(16)
	assert_object(first.get_parent()).is_null()  # The oldest was hidden and freed at once.
	assert_int(_layer.decals.crater_count()).is_equal(17)


func test_a_collapse_in_flight_is_dropped_with_the_match() -> void:
	_open(_pair() + [[1, 22, 4]])
	var node: Node2D = _layer.building(1)
	_kill([1])
	_runner.start()  # Another match.
	_layer._process(0.0)
	assert_int(_layer.collapse().count()).is_equal(0)
	assert_object(node.get_parent()).is_null()


func test_eight_buildings_killed_at_once_never_write_more_than_20_and_lose_no_step() -> void:
	_open(_grid(10))
	var ids: Array = [1, 2, 3, 4, 5, 6, 7, 8]
	var base: int = _layer.life_writes()
	var died: int = _kill(ids)
	var worst: int = 0
	var total: int = 0
	for frame: int in range(1, 50):  # Frames of 16 ms up to 800 ms.
		var before: int = _layer.life_writes()
		_frame(died, float(frame) * 16.0)
		worst = maxi(worst, _layer.life_writes() - before)
		total = _layer.life_writes() - base
		if frame == 44:  # 704 ms: every building waited its turn for the last step.
			for id: int in ids:
				assert_int(_layer.collapse().step_of(id)).is_equal(6)
	assert_int(worst).is_less_equal(20)
	assert_int(total).is_equal(8 * 28)  # 2 + 4 x 6 + 2 each: no step lost.


func test_a_starved_frame_writes_the_step_of_its_moment() -> void:
	_open(_pair() + [[1, 22, 4]])
	var died: int = _kill([1])
	_frame(died, 0.0)
	_frame(died, 640.0)  # Frames were skipped: it goes straight to step 6, one write of four.
	assert_int(_layer.collapse().step_of(1)).is_equal(6)


func test_two_runs_give_the_same_regions() -> void:
	var first: Array = _regions_over_time()
	var second: Array = _regions_over_time()
	assert_array(first).is_equal(second)
	assert_int(first.size()).is_greater(3)


func _regions_over_time() -> Array:
	_open(_pair() + [[1, 22, 4]], {"anim": true})
	var died: int = _kill([1])
	var seen: Array = []
	for ms: float in [0.0, 100.0, 270.0, 400.0, 640.0, 710.0]:
		_frame(died, ms)
		var node: Node2D = _layer.collapse().node_of(1)
		var body: Sprite2D = node.get_node("Body")
		seen.append([body.region_rect, body.offset.y, node.visible])
	return seen


func test_a_pause_freezes_the_sequence() -> void:
	_open(_pair() + [[1, 22, 4]])
	var died: int = _kill([1])
	_frame(died, 430.0)
	var body: Sprite2D = _layer.collapse().node_of(1).get_node("Body")
	var shown: Rect2 = body.region_rect
	for frame: int in 20:  # The clock does not move: the same tick and alpha.
		_layer._process(0.0)
	assert_that(body.region_rect).is_equal(shown)
	assert_int(_layer.collapse().step_of(1)).is_equal(3)


func test_a_collapsing_building_is_not_picked_and_leaves_the_selection() -> void:
	_open(_pair() + [[1, 22, 4]])
	_layer.set_selected(PackedInt32Array([1]))
	assert_bool(_layer.selected_ids().has(1)).is_true()
	_kill([1])
	assert_bool(_layer.selected_ids().has(1)).is_false()
	assert_int(_layer.building_count()).is_equal(2)


func test_collapses_leave_no_node_or_object_behind_after_warm_up() -> void:
	_open(_pair() + [[1, 22, 4]])
	var snap: MatchSnapshot = _runner.snapshot
	var type: int = snap.type_index[snap.index_of(1)]
	var at: Vector2i = Rig.position_of(_runner, 1)
	var before: Array = []
	for round_of: int in 30:
		if round_of == 10:
			before = _counts()
		var id: int = _runner.world.add_unit(1, type, at.x, at.y)
		_runner.run_ticks(1)
		_layer._process(0.0)
		var died: int = _kill([id])
		for ms: float in [0.0, 300.0, 500.0, 650.0, 710.0, 910.0]:
			_frame(died, ms)
		await await_idle_frame()  # The freed node goes at the end of the frame.
	assert_array(_counts()).is_equal(before)
	assert_int(_layer.collapse().count()).is_equal(0)
	assert_int(_layer.decals.shadow_count()).is_equal(3)


## Objects and nodes, less the craters, which stay for the match.
func _counts() -> Array:
	var craters: int = _layer.decals.crater_count()
	return [
		roundi(Performance.get_monitor(Performance.OBJECT_COUNT)) - craters,
		roundi(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - craters
	]


func test_the_patch_follows_the_body_down_without_a_gap_at_both_stages() -> void:
	for scale: float in SCALES:
		for percent: int in [50, 20]:  # SKADET, then KRITISK.
			_open(_pair() + [[1, 22, 4]], {}, scale)
			var rise: float = -_body(1).get_rect().position.y * _body(1).scale.y  # The intact picture's.
			_hit(1, percent)
			var body: Sprite2D = _body(1)
			var patch: Sprite2D = _patch(1)
			assert_bool(patch.visible).is_true()
			var foot: float = body.position.y + body.get_rect().end.y * body.scale.y
			var offset0: float = patch.offset.y
			var died: int = _kill([1])
			for ms: float in [0.0, 260.0, 330.0, 410.0, 480.0, 560.0, 640.0]:
				_frame(died, ms)
				var top: float = body.position.y + body.get_rect().position.y * body.scale.y
				var bottom: float = patch.position.y + patch.get_rect().end.y * patch.scale.y
				var note: String = "scale %s stage %d at %d ms" % [scale, percent, roundi(ms)]
				assert_float(bottom - top).override_failure_message(note).is_greater(0.0)
				assert_float(bottom).override_failure_message(note).is_less_equal(foot + 0.001)
			# The last step: the patch has gone down by the sink, within a body row.
			var moved: float = (patch.offset.y - offset0) * patch.scale.y
			var want: float = rise * float(_life.collapse_sink_percent) / 100.0
			var note: String = "scale %s stage %d" % [scale, percent]
			assert_float(want - moved).override_failure_message(note).is_between(
				-0.001, body.scale.y + 0.001
			)
			assert_int(_layer.collapse().step_of(1)).is_equal(6)


func test_collapse_writes_go_before_the_stage_queue() -> void:
	_open(_grid(40))
	var ids: PackedInt32Array = _runner.snapshot.unit_id.duplicate()
	var died: int = _kill([ids[0]])  # Its start is written in this frame.
	for id: int in ids.slice(1):
		Dmg.set_hp(_runner, id, 66)
	_runner.run_ticks(1)  # 39 stage changes of 5 writes wait in the queue.
	var before: int = _layer.life_writes()
	_frame(died, 270.0)  # The first sink step is due.
	assert_int(_layer.collapse().step_of(ids[0])).is_equal(1)
	assert_int(_layer.life_writes() - before).is_equal(4 + 15)  # 16 left: three stage changes.


func test_sixteen_collapses_on_short_frames_each_sink_before_the_hide_inside_the_budget() -> void:
	_open(_grid(18))
	var ids: Array = []
	for id: int in range(1, 17):
		ids.append(id)
	var died: int = _kill(ids)
	var worst: int = 0
	for frame: int in range(1, 22):  # Frames of 33 ms up to 693 ms.
		var before: int = _layer.life_writes()
		_frame(died, float(frame) * 33.0)
		worst = maxi(worst, _layer.life_writes() - before)
	assert_int(worst).is_less_equal(20)
	for id: int in ids:
		assert_int(_layer.collapse().step_of(id)).is_greater_equal(1)
