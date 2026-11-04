extends "res://tests/view/support/damage_suite.gd"
## The `Anim` and the `Head` at KRITISK, the write queue and the hook of a building that dies (plan
## P159, ADR 0028 section 8, ADR 0029 sections 3 and 8). Fixtures: support/damage_suite.gd.

const SpyRuins: GDScript = preload("res://tests/view/support/spy_ruins.gd")


func test_the_anim_runs_at_kritisk_when_the_sheet_says_run() -> void:
	_open(_pair(), {"anim": true, "anim_kritisk": true})
	_centre_camera(1)
	_hit(1, 20)
	var anim: Sprite2D = _layer.building(1).get_node("Anim")
	assert_bool(anim.visible).is_true()
	var seen: Dictionary[Rect2, bool] = {}
	for step: int in 40:
		Dmg.Rig.see(_runner.snapshot, 1, [])
		_runner.snapshot.tick = step
		_layer._process(0.0)
		seen[anim.region_rect] = true
	assert_bool(anim.visible).is_true()
	assert_int(seen.size()).is_greater(1)  # It still turns.


func test_the_anim_is_hidden_at_kritisk_when_the_sheet_says_hide_and_runs_at_skadet() -> void:
	_open(_pair(), {"anim": true, "anim_kritisk": false})
	_centre_camera(1)
	var anim: Sprite2D = _layer.building(1).get_node("Anim")
	_hit(1, 50)  # SKADET: runs.
	assert_bool(anim.visible).is_true()
	_layer.camera = null  # No loop frames to count among the stage's writes.
	var before: int = _layer.life_writes()
	_hit(1, 10)  # KRITISK: one visibility write, on top of the stage's four (1 -> 2).
	assert_bool(anim.visible).is_false()
	assert_int(_layer.life_writes() - before).is_equal(5)
	_layer.camera = _camera
	for step: int in 40:  # The loop's frame changes do not show it again.
		_runner.snapshot.tick = step * 3
		_layer._process(0.0)
	assert_bool(anim.visible).is_false()
	assert_bool(_patch(1).visible).is_true()
	_hit(1, 50)  # Back to SKADET (a later repair): shown and running.
	assert_bool(anim.visible).is_true()


func test_a_sheet_that_says_nothing_about_the_anim_hides_it_at_kritisk() -> void:
	_open(_pair(), {"anim": true})  # A plain sheet has no `anim_kritisk`: P163's default is hide.
	_hit(1, 50)
	assert_bool(_layer.building(1).get_node("Anim").visible).is_true()
	_hit(1, 10)
	assert_bool(_layer.building(1).get_node("Anim").visible).is_false()


func test_a_defence_head_stays_at_every_stage() -> void:
	_life = (load("res://data/life_settings.tres") as LifeSettings).duplicate() as LifeSettings
	_life.sweep_frames = 0  # The idle sweep moves the head's frame; this test is about the stage.
	_open(_pair(), {"anim": true, "head": true, "anim_kritisk": false})
	var head: Sprite2D = _layer.building(1).get_node("Head")
	var before: Rect2 = head.region_rect
	for percent: int in [66, 10, 90]:
		_hit(1, percent)
		assert_bool(head.visible).is_true()
		assert_that(head.region_rect).is_equal(before)


# --- The write queue ---


func test_the_stage_writes_cost_5_5_and_4() -> void:
	assert_int(BuildingDamage.cost(0, 1, false)).is_equal(5)
	assert_int(BuildingDamage.cost(0, 2, false)).is_equal(5)
	assert_int(BuildingDamage.cost(1, 2, false)).is_equal(4)
	assert_int(BuildingDamage.cost(0, 2, true)).is_equal(6)  # The Anim's visibility is one more.
	assert_int(BuildingDamage.cost(1, 2, true)).is_equal(5)
	assert_int(BuildingDamage.cost(2, 0, true)).is_equal(4)
	_open(_pair())
	var start: int = _layer.life_writes()
	_hit(1, 66)
	assert_int(_layer.life_writes() - start).is_equal(5)
	_hit(1, 10)
	assert_int(_layer.life_writes() - start).is_equal(9)
	_hit(2, 10)
	assert_int(_layer.life_writes() - start).is_equal(14)


func test_a_burst_of_40_buildings_is_applied_4_a_frame_oldest_first() -> void:
	_open(_grid(40))
	var ids: PackedInt32Array = _runner.snapshot.unit_id.duplicate()
	for id: int in ids:
		Dmg.set_hp(_runner, id, 66)
	_runner.run_ticks(1)
	var start: int = _layer.life_writes()
	var shown: Dictionary[int, bool] = {}
	for frame: int in 10:
		_layer._process(0.0)
		var now: int = 0
		for id: int in ids:
			if _patch(id).visible:
				now += 1
				shown[id] = true
		assert_int(now).override_failure_message("frame %d" % frame).is_equal(4 * (frame + 1))
		assert_int(_layer.life_writes() - start).is_equal(20 * (frame + 1))
		for at: int in 4 * (frame + 1):  # The oldest first: ascending ids.
			assert_bool(_patch(ids[at]).visible).is_true()
	_layer._process(0.0)
	assert_int(_layer.life_writes() - start).is_equal(200)  # Nothing more: all 40 done.


func test_a_burst_never_passes_the_building_share_in_a_frame() -> void:
	_open(_grid(30))
	for id: int in _runner.snapshot.unit_id:
		Dmg.set_hp(_runner, id, 10)
	_runner.run_ticks(1)
	var last: int = _layer.life_writes()
	for frame: int in 8:
		_layer._process(0.0)
		assert_int(_layer.life_writes() - last).is_less_equal(_layer.life.damage_building_writes)
		last = _layer.life_writes()


func test_the_same_snapshots_give_the_same_regions_on_two_runs() -> void:
	var runs: Array[Array] = []
	for run: int in 2:
		_open(_grid(12))
		for id: int in _runner.snapshot.unit_id:
			Dmg.set_hp(_runner, id, 66 if id % 2 == 0 else 20)
		_runner.run_ticks(1)
		for frame: int in 5:
			_layer._process(0.0)
		var regions: Array[Rect2] = []
		for id: int in _runner.snapshot.unit_id:
			regions.append_array([_body(id).region_rect, _patch(id).region_rect])
			regions.append_array([Rect2(_body(id).offset, _patch(id).offset)])
		runs.append(regions)
		_layer.queue_free()
		_sort.queue_free()
	assert_array(runs[0]).is_equal(runs[1])


func test_reduced_effects_keep_the_stages() -> void:
	_open(_pair())
	var reduced: LifeSettings = _layer.life.duplicate() as LifeSettings
	reduced.reduced = true
	_layer.life = reduced
	_hit(1, 10)
	_check_stage(1, 2)


# --- The ruin hook ---


func test_a_shown_building_that_dies_goes_to_the_ruin_hook_and_is_freed_with_its_crater() -> void:
	_open(_pair())
	_layer.decals.crater_texture = ImageTexture.create_from_image(
		Image.create(8, 4, false, Image.FORMAT_RGBA8)
	)
	var spy: BuildingRuins = SpyRuins.new()
	spy.setup(_sort, _layer.decals)
	_layer._ruins = spy
	var node: Node2D = _layer.building(1)
	var nodes: int = _sort.get_child_count()
	_runner.world.hp[_runner.world.index_of(1)] = 0
	_runner.run_ticks(1)
	_layer._process(0.0)
	assert_array(_calls(spy)).is_equal([[1, _runner.snapshot.tick, false, false]])
	assert_int(_layer.decals.crater_count()).is_equal(1)
	assert_int(_sort.get_child_count()).is_equal(nodes - 1)
	assert_object(_layer.building(1)).is_null()
	await await_idle_frame()
	assert_bool(is_instance_valid(node)).is_false()


func test_a_site_that_dies_is_handed_over_as_a_site_and_a_cancel_as_cancelled() -> void:
	_open(_pair() + [[1, 22, 4], [2, 22, 14]])  # Spares: the match goes on.
	var spy: BuildingRuins = SpyRuins.new()
	spy.setup(_sort, _layer.decals)
	_layer._ruins = spy
	_runner.world.build_left[0] = 100000
	_runner.run_ticks(1)  # The layer notes it is a site.
	_runner.world.hp[0] = 0
	_runner.run_ticks(1)
	_runner.world.build_left[0] = Production.CANCELLED  # Building 2 is row 0 now.
	_runner.world.hp[0] = 0
	_runner.run_ticks(1)
	assert_int(_calls(spy).size()).is_equal(2)
	assert_array(_calls(spy)[0].slice(0, 1)).is_equal([1])
	assert_bool(_calls(spy)[0][2]).is_true()
	assert_bool(_calls(spy)[0][3]).is_false()
	assert_bool(_calls(spy)[1][2]).is_false()
	assert_bool(_calls(spy)[1][3]).is_true()


func test_a_hidden_building_that_dies_is_freed_without_the_hook_or_a_crater() -> void:
	_open(_pair(), {}, 1.0, false)
	Dmg.Rig.see(_runner.snapshot, 1, [])
	_layer._process(0.0)
	var spy: BuildingRuins = SpyRuins.new()
	spy.setup(_sort, _layer.decals)
	_layer._ruins = spy
	_runner.world.hp[_runner.world.index_of(2)] = 0
	_runner.run_ticks(1)
	_layer._process(0.0)
	assert_int(_calls(spy).size()).is_equal(0)
	assert_int(_layer.decals.crater_count()).is_equal(0)
	assert_object(_layer.building(2)).is_null()


func _calls(spy: BuildingRuins) -> Array:
	return spy.get("calls")


func _drain(frames: int) -> void:
	for frame: int in frames:
		_layer._process(0.0)


func test_a_building_that_dies_while_queued_leaves_the_queue_with_no_stale_write() -> void:
	_open(_grid(40))
	var ids: PackedInt32Array = _runner.snapshot.unit_id.duplicate()
	for id: int in ids:
		Dmg.set_hp(_runner, id, 66)
	_runner.run_ticks(1)
	var start: int = _layer.life_writes()
	_layer._process(0.0)  # Four are written, the rest wait.
	_runner.world.hp[_runner.world.index_of(ids[39])] = 0  # The last in the queue dies.
	_runner.run_ticks(1)
	await await_idle_frame()  # Its node is freed.
	_drain(12)
	assert_int(_layer.life_writes() - start).is_equal(39 * 5)
	assert_int(_layer._stage_queue.size()).is_equal(0)
	for id: int in ids.slice(0, 39):
		assert_bool(_patch(id).visible).is_true()


func test_a_new_match_drops_the_queue() -> void:
	_open(_grid(40))
	for id: int in _runner.snapshot.unit_id:
		Dmg.set_hp(_runner, id, 66)
	_runner.run_ticks(1)
	_layer._process(0.0)
	_runner.start()  # Another match serial: the 36 that waited belong to the old one.
	_layer._process(0.0)
	await await_idle_frame()
	var writes: int = _layer.life_writes()
	assert_int(_layer._stage_queue.size()).is_equal(0)
	_drain(12)
	assert_int(_layer.life_writes()).is_equal(writes)
	assert_int(_layer.building_count()).is_equal(40)  # The new match's own entries, none queued.
