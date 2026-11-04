extends "res://tests/view/support/damage_fx_suite.gd"
## The numbers and the order of the damage particles (plan P148, ADR 0029 sections 6 and 13): the
## smoke cap held by the default data, the glow pass first, the quiet ambient emitters, `reduced`,
## and `FxRing` itself (the slot, the plan, the mirror). Fixture: support/damage_fx_suite.gd.

const AIR: String = "res://game/view/AirFx.gd"


func before_test() -> void:
	_open([[1, 4, 4], [1, 12, 4], [1, 20, 4], [1, 4, 12]])


func test_the_default_numbers_hold_every_stage_under_the_smoke_cap() -> void:
	var cap: int = DATA.damage_smoke_cap
	assert_int(cap).is_equal(30)
	var lines: PackedInt32Array = DATA.damage_burning_points
	var stages: Dictionary = {&"smoke": lines[0], &"soot": lines[1]}
	for puff: StringName in stages:
		var live: int = ceili(float(DATA.damage_life_ms[puff]) / float(DATA.damage_emit_ms[puff]))
		var note: String = "%s: %d points x %d live" % [puff, stages[puff], live]
		assert_int(stages[puff] * live).override_failure_message(note).is_less_equal(cap)
	# The defaults are lower than the cap, so the rings fit the frame budget (ADR 0029 section 6).
	assert_int(lines[1] * ceili(2000.0 / 400.0)).is_equal(15)
	assert_int(lines[0] * ceili(2000.0 / 500.0)).is_equal(4)
	assert_int(DATA.damage_slots).is_equal(80)
	assert_int(DATA.damage_burning_points.size()).is_equal(2)
	assert_int(DATA.damage_burning_points[0]).is_less(DATA.damage_burning_points[1])


func test_every_glow_is_drawn_before_the_clouds_and_the_clouds_before_the_flames() -> void:
	# The call order in `_draw`: every ring's glow, the ambient ring, then every ring's clouds, then
	# every ring's flames and sparks.
	var text: String = FileAccess.get_file_as_string(AIR)
	var body: String = text.substr(text.find("func _draw()"), 1800)
	var glow: int = body.find("ring.draw(self, _atlas, FxRing.GLOW)")
	var ambient: int = body.find("draw_texture_rect_region")
	var rest: int = body.find("range(FxRing.CLOUD, FxRing.PASSES)")
	assert_int(glow).is_greater(-1)
	assert_int(ambient).is_greater(glow)
	assert_int(rest).is_greater(ambient)


func test_a_real_frame_paints_each_pass_exactly_its_planned_quads_by_kind() -> void:
	_only(1)
	_hp(1, 20)
	_only(1)
	_run(START, START + 60)
	Rig.at(_runner, START + 59, 0.5)
	_air.set_process(true)  # The engine's own frame plans and draws.
	await await_idle_frame()
	_air.set_process(false)
	var ring: FxRing = _air.damage().ring
	var by_pass: Array[int] = [0, 0, 0]
	var pass_of: Dictionary = {
		DamageFx.K_GLOW: FxRing.GLOW,
		DamageFx.K_SMOKE: FxRing.CLOUD,
		DamageFx.K_SOOT: FxRing.CLOUD,
		DamageFx.K_EXHAUST: FxRing.CLOUD,
	}
	for index: int in ring.quad_count():
		by_pass[pass_of.get(ring.quad_kind(index), FxRing.FLAME)] += 1
	for pass_index: int in FxRing.PASSES:
		var note: String = "pass %d" % pass_index
		assert_int(by_pass[pass_index]).override_failure_message(note).is_greater(0)
		assert_int(ring.planned(pass_index)).override_failure_message(note).is_equal(
			by_pass[pass_index]
		)
		assert_int(ring.drawn(pass_index)).override_failure_message(note).is_equal(
			by_pass[pass_index]
		)


func test_an_ambient_emitter_goes_quiet_from_the_stage_of_its_sheet_and_not_before() -> void:
	_only(1)
	var smoke: Vector2 = _spot(1, 0)
	for percent: int in [100, 60, 20]:
		_hp(1, percent)
		_only(1)
		_air._empty()
		_run(START, START + 60)
		var stage: int = BuildingDamage.stage_of(
			_runner.snapshot.hp[0],
			_runner.snapshot.type_max_hp[_runner.snapshot.type_index[0]],
			DATA.building_stage_percent
		)
		var puffs: int = 0
		for slot: int in _air.slot_count():
			puffs += 1 if _air.puff_at(slot).distance_to(smoke) < 0.01 else 0
		var note: String = "stage %d" % stage
		assert_bool(puffs > 0).override_failure_message(note).is_equal(stage < QUIET)


func test_an_empty_emitter_quiet_reads_as_all_zeros_and_never_stops_an_emitter() -> void:
	_open([[1, 4, 4]], [])
	assert_int(_def.emitter_quiet.size()).is_equal(0)
	_only(1)
	_hp(1, 10)
	_only(1)
	_run(START, START + 60)
	var puffs: int = 0
	for slot: int in _air.slot_count():
		puffs += 1 if _air.puff_at(slot).distance_to(_spot(1, 0)) < 0.01 else 0
	assert_int(puffs).is_greater(0)


func test_reduced_keeps_smoke_fire_and_glow_drops_sparks_and_the_switch_leaves_puffs_alive(
) -> void:
	_open([[1, 4, 4]], [0, 0, 0, 0, 0])  # The ambient smoke never goes quiet here.
	_only(1)
	_hp(1, 20)
	_only(1)
	_run(START, START + 60)
	assert_int(_count("spark")).is_greater(0)
	assert_int(_air.slot_count()).is_greater(0)
	var before: int = _air.damage().ring.count()
	_life.reduced = true
	_frame(START + 59, 0.0)
	assert_int(_air.slot_count()).is_equal(0)  # The ambient ring empties.
	assert_int(_air.damage().ring.count()).is_equal(before)  # The damage puffs live out.
	assert_int(_air.damage().ring.quad_count()).is_greater(0)
	_air.damage().clear()
	_run(START + 60, START + 150)
	assert_int(_count("spark")).is_equal(0)
	assert_int(_count("soot")).is_greater(0)
	assert_int(_count("fire_big")).is_greater(0)
	assert_int(_count("glow_strong")).is_greater(0)
	assert_int(_air.slot_count()).is_equal(0)  # No ambient birth either.


func test_ring_keeps_the_newest_puffs_and_plans_the_life_the_motion_and_the_fade_of_a_style(
) -> void:
	var ring: FxRing = FxRing.new()
	ring.setup([&"smoke", &"jet"], 2)
	ring.set_style(0, 0, 1000.0, 20.0, 10.0, Vector2(1.0, 2.0), 0.5, 0.0)
	ring.set_style(1, 1, 600.0, 0.0, 0.0, Vector2.ONE, 1.0, 300.0)
	ring.size_to(3)
	for born: int in 5:
		ring.add(0, Vector2(float(born), 0.0), float(born) * 100.0, 0)
	assert_int(ring.count()).is_equal(3)
	assert_float(ring.puff_born(0) + ring.puff_born(1) + ring.puff_born(2)).is_equal(900.0)
	ring.plan(500.0)  # Ages 100, 200, 300 ms of 1000: the newest is the youngest, drawn last.
	assert_int(ring.quad_count()).is_equal(3)
	var smoke: Rect2i = LifeRegions.region(&"smoke", 0)
	var anchor: Vector2 = LifeRegions.ANCHOR[&"smoke"]
	var t: float = 0.1  # The puff of age 100 ms (born 400): the last quad.
	var grow: float = lerpf(1.0, 2.0, t)
	var rect: Rect2 = ring.quad_rect(2)
	assert_vector(rect.size).is_equal_approx(Vector2(smoke.size) * grow, Vector2(0.001, 0.001))
	assert_vector(rect.position).is_equal_approx(
		Vector2(4.0 + 10.0 * t - anchor.x * grow, -20.0 * t - anchor.y * grow), Vector2(0.01, 0.01)
	)
	assert_float(ring.quad_alpha(2)).is_equal_approx(0.5 * (1.0 - t), 0.0001)
	ring.plan(1300.0)  # Past the life of the older two.
	assert_int(ring.quad_count()).is_equal(1)
	# A flame holds its alpha for `hold`, then fades over the rest of its life; a jet drawn mirrored
	# has its anchor on the right edge of its box.
	ring.clear()
	ring.add(1, Vector2(100.0, 50.0), 0.0, 0, 1)
	ring.add(1, Vector2(100.0, 50.0), 0.0, 0, 0)
	ring.plan(150.0)
	assert_float(ring.quad_alpha(0)).is_equal_approx(1.0, 0.0001)
	ring.plan(450.0)
	assert_float(ring.quad_alpha(0)).is_equal_approx(0.5, 0.0001)
	var jet: Vector2 = LifeRegions.ANCHOR[&"jet"]
	var size: Vector2 = Vector2(LifeRegions.region(&"jet", 0).size)
	assert_bool(ring.quad_flipped(0)).is_true()
	assert_bool(ring.quad_flipped(1)).is_false()
	assert_float(ring.quad_rect(0).position.x).is_equal_approx(100.0 - (size.x - jet.x), 0.001)
	assert_float(ring.quad_rect(1).position.x).is_equal_approx(100.0 - jet.x, 0.001)
	# A kind that may not be mirrored ignores the request.
	ring.clear()
	ring.add(0, Vector2.ZERO, 0.0, 0, 1)
	assert_int(ring.count()).is_equal(1)
	ring.plan(10.0)
	assert_bool(ring.quad_flipped(0)).is_false()


func test_a_long_burn_makes_no_node_and_no_object_after_the_first_puffs() -> void:
	for id: int in [1, 2, 3]:
		_hp(id, 10)
	var tick: int = START
	for step: int in 120:  # Warm-up: the ring fills, the tables are made.
		Rig.deliver(_runner, PackedInt32Array(), tick)
		_air._process(0.0)
		tick += 1
	var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes: int = _air.get_child_count() + get_child_count()
	var most: int = 0
	for step: int in 400:
		Rig.deliver(_runner, PackedInt32Array(), tick)
		for frame: int in 4:
			Rig.at(_runner, tick, 0.25 * float(frame))
			_air._process(0.0)
			most = maxi(most, _air.damage().ring.quad_count())
		tick += 1
	assert_int(int(Performance.get_monitor(Performance.OBJECT_COUNT))).is_equal(objects)
	assert_int(_air.get_child_count() + get_child_count()).is_equal(nodes)
	assert_int(most).is_between(1, DATA.damage_slots)
