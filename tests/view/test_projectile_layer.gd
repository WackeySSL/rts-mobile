extends GdUnitTestSuite
## What ProjectileLayer plans and draws (plan P44a, assets/art/STYLE.md "Combat effects", ADR 0012
## sections 3 and 6): a live slot of the published snapshot as one atlas quad at the lerp of its two
## positions, turned along the move; the SHELL or ROCKET region by `weapon_ids[proj_weapon]`; a new
## slot (its `proj_id` differs from `prev_proj_id`) not drawn in its tick. Pixels cannot be read
## headless, so the tests read the layer's plan (`active_count`, `quad_*`), which `_draw` paints one
## for one (`drawn_count`), and `test_the_draw_code_paints_nothing_but_atlas_quads` reads the
## script.
## Exact cases write slots into the published snapshot, which ADR 0012 section 3 allows in SYNC
## mode; the others run the real sim: two light tanks 3 tiles apart on open grass fire at each other
## (flight time ceil(3000 / 600) = 5 ticks). The runner is not in the tree, so only the calls here
## move time: runner._process() moves the interpolation clock (a 1/60 s frame is alpha 0.25) and
## layer._process() draws a frame.

const SCRIPT_PATH: String = "res://game/view/ProjectileLayer.gd"
const ATLAS_PATH: String = "res://assets/art/svg/fx/effects_atlas.svg"
const MAIN_SCENE: String = "res://scenes/main.tscn"
## STYLE.md "Combat effects": the regions of the shell and the rocket in the atlas, in the px of
## the imported texture, and the size that the atlas keeps (typed again so a wrong layer fails).
const SHELL: Rect2 = Rect2(84.0, 60.0, 16.0, 8.0)
const ROCKET: Rect2 = Rect2(84.0, 72.0, 36.0, 12.0)
const ATLAS_SIZE: Vector2 = Vector2(176.0, 84.0)
const PX_PER_MILLI: float = 0.064  ## A tile is 64 px and 1000 milli-tiles.
const FRAME_QUARTER: float = 1.0 / 60.0  ## Seconds: a quarter of a 15 Hz tick.
const BASE_SIZE: Vector2i = Vector2i(1280, 720)
## The sizes every screen is tested at: base, 20:9 phone and 4:3 tablet.
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(2400, 1080), Vector2i(2048, 1536)]
## What each of them shows in base px (stretch canvas_items, aspect expand): 1280x720, 1600x720
## and 1280x960.
const VIEWS: Array[Vector2] = [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 960)]
## The lines of ProjectileLayer._draw: the painted count, then for each planned quad the transform
## that places and turns it and one atlas quad of its region, centred and as big as the region.
const DRAW_BODY: Array[String] = [
	"_drawn = 0",
	"var geometry: PackedFloat32Array = _geometry",
	"var kinds: PackedByteArray = _kinds",
	"for index: int in _quads:",
	"var at: int = index * FLOATS_PER_QUAD",
	"draw_set_transform(Vector2(geometry[at], geometry[at + 1]), geometry[at + 2])",
	"if kinds[index] == KIND_ROCKET:",
	"draw_texture_rect_region(_atlas, ROCKET_QUAD, ROCKET_REGION)",
	"else:",
	"draw_texture_rect_region(_atlas, SHELL_QUAD, SHELL_REGION)",
	"_drawn += 1",
]

var _window_size_before: Vector2i
var _runner: MatchRunner
var _layer: ProjectileLayer


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	get_window().size = BASE_SIZE
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = _duel()
	_runner.start()
	_layer = auto_free(ProjectileLayer.new())
	_layer.runner = _runner
	add_child(_layer)
	_layer.set_process(false)  # Frames come only from _frame().


func after_test() -> void:
	CommandQueue.clear()


func test_a_slot_is_drawn_at_the_lerp_of_its_two_positions_and_turned_along_the_move() -> void:
	_set_slot(3, 11, Vector2i(7000, 24000), Vector2i(10000, 20000))  # Up and to the right.
	_set_slot(5, 12, Vector2i(30000, 4000), Vector2i(27000, 4000))  # Due west.
	_set_slot(9, 13, Vector2i(2000, 1000), Vector2i(2000, 5000))  # Due south.
	_frame()  # Alpha 0: each stands at its previous position.
	assert_int(_layer.active_count()).is_equal(3)
	assert_array(_slots()).is_equal([3, 5, 9])
	assert_vector(_layer.quad_position(0)).is_equal_approx(
		Vector2(7000, 24000) * PX_PER_MILLI, _eps()
	)
	_runner._process(FRAME_QUARTER)
	assert_float(_runner.alpha()).is_equal(0.25)
	_frame()
	var expected: Array[Vector2] = [Vector2(7750, 23000), Vector2(29250, 4000), Vector2(2000, 2000)]
	var angles: Array[float] = [atan2(-4000.0, 3000.0), PI, PI / 2.0]
	for index: int in 3:
		var note: String = "quad %d" % index
		assert_vector(_layer.quad_position(index)).override_failure_message(note).is_equal_approx(
			expected[index] * PX_PER_MILLI, _eps()
		)
		assert_float(_layer.quad_angle(index)).override_failure_message(note).is_equal_approx(
			angles[index], 0.0001
		)
	_runner._process(FRAME_QUARTER)  # Alpha 0.5.
	_frame()
	assert_vector(_layer.quad_position(0)).is_equal_approx(
		Vector2(8500, 22000) * PX_PER_MILLI, _eps()
	)
	assert_vector(_layer.quad_position(1)).is_equal_approx(
		Vector2(28500, 4000) * PX_PER_MILLI, _eps()
	)


func test_the_drawn_count_is_the_live_slots_that_are_not_new() -> void:
	_set_slot(0, 21, Vector2i(1000, 1000), Vector2i(2000, 1000))  # Live for two ticks: drawn.
	_set_slot(1, 22, Vector2i(1000, 2000), Vector2i(2000, 2000))
	_runner.snapshot.prev_proj_id[1] = 0  # New: the slot was free a tick ago.
	_set_slot(2, 23, Vector2i(1000, 3000), Vector2i(2000, 3000))
	_runner.snapshot.prev_proj_id[2] = 9  # New: another shell had it, freed and launched again.
	_runner.snapshot.prev_proj_id[3] = 24  # Free now, in use before: a shell that just landed.
	_set_slot(4, 25, Vector2i(1000, 5000), Vector2i(2000, 5000), 1)  # An owner 1 shell: drawn.
	_set_slot(500, 26, Vector2i(1000, 6000), Vector2i(2000, 6000))  # The last slot is a slot.
	_frame()
	assert_int(_layer.active_count()).is_equal(3)
	assert_array(_slots()).is_equal([0, 4, 500])
	_set_slot(7, 27, Vector2i(1000, 7000), Vector2i(2000, 7000), 0)  # Owner 0, an armed neutral.
	_frame()
	assert_array(_slots()).is_equal([0, 4, 7, 500])


func test_a_new_slot_is_not_drawn_in_its_tick_and_is_drawn_from_the_next() -> void:
	var shot_tick: int = _run_to(World.Event.SHOT)
	assert_int(shot_tick).is_greater(0)
	var fresh: Array[int] = _new_slots()
	assert_int(fresh.size()).is_greater(0)  # The shell is in the snapshot, with no heading yet.
	_frame()
	assert_int(_layer.active_count()).is_equal(0)  # Nothing else is live: nothing is drawn.
	_runner.run_ticks(1)
	_frame()
	assert_array(_slots()).is_equal(_old_slots())  # Now it has moved once and is drawn.
	assert_int(_layer.active_count()).is_equal(fresh.size())
	var snap: MatchSnapshot = _runner.snapshot
	for index: int in _layer.active_count():
		var slot: int = _layer.quad_slot(index)
		var from: Vector2 = Vector2(snap.prev_proj_x[slot], snap.prev_proj_y[slot])
		var to: Vector2 = Vector2(snap.proj_x[slot], snap.proj_y[slot])
		assert_bool(to != from).is_true()
		assert_vector(_layer.quad_position(index)).is_equal_approx(from * PX_PER_MILLI, _eps())
		assert_float(_layer.quad_angle(index)).is_equal_approx((to - from).angle(), 0.0001)


func test_every_tick_of_a_fight_draws_exactly_the_live_slots_that_are_not_new() -> void:
	var saw_new: bool = false
	var saw_drawn: bool = false
	for _tick: int in 60:  # Two volleys: the second one's shells reuse the first one's slots.
		_runner.run_ticks(1)
		_frame()
		saw_new = saw_new or not _new_slots().is_empty()
		saw_drawn = saw_drawn or _layer.active_count() > 0
		assert_array(_slots()).is_equal(_old_slots())
	assert_bool(saw_new).is_true()
	assert_bool(saw_drawn).is_true()


func test_the_tick_a_shell_lands_its_slot_is_free_and_nothing_is_drawn_for_it() -> void:
	var drawn_ticks: Dictionary[int, int] = {}  # Projectile id -> snapshots it was drawn in.
	var landed: int = 0
	for _tick: int in 40:
		_runner.run_ticks(1)
		_frame()
		var snap: MatchSnapshot = _runner.snapshot
		for index: int in _layer.active_count():
			var id: int = snap.proj_id[_layer.quad_slot(index)]
			drawn_ticks[id] = drawn_ticks.get(id, 0) + 1
		var events: PackedInt32Array = snap.events
		for at: int in range(0, events.size(), World.EVENT_STRIDE):
			if events[at] != World.Event.IMPACT:
				continue
			var id: int = events[at + 1]
			assert_bool(snap.proj_id.has(id)).is_false()  # Its slot is free in this snapshot.
			assert_bool(drawn_ticks.has(id)).is_true()  # It was drawn on its way.
			# Launched in tick L (new, not drawn), flying in L + 1 to L + 4, landed in L + 5.
			assert_int(drawn_ticks[id]).is_equal(4)
			landed += 1
	assert_int(landed).is_greater(1)


func test_a_rocket_slot_draws_the_rocket_region_and_any_other_weapon_the_shell_region() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var by_name: Array[StringName] = [&"rocket", &"tank_cannon", &"rifle"]
	snap.weapon_ids = by_name
	_set_slot(0, 31, Vector2i(1000, 1000), Vector2i(2000, 1000), 1, 0)  # `rocket`.
	_set_slot(1, 32, Vector2i(1000, 2000), Vector2i(2000, 2000), 1, 1)  # `tank_cannon`.
	_set_slot(2, 33, Vector2i(1000, 3000), Vector2i(2000, 3000), 1, 2)  # `rifle`, not a shell.
	_set_slot(3, 34, Vector2i(1000, 4000), Vector2i(2000, 4000), 1, 7)  # Past the table.
	_frame()
	assert_array(_regions()).is_equal([ROCKET, SHELL, SHELL, SHELL])
	# The weapon is found by its id and not by a fixed index: the same slots, the table reordered.
	var reordered: Array[StringName] = [&"tank_cannon", &"rifle", &"rocket"]
	snap.weapon_ids = reordered  # Index 2 is the rocket now, and index 0 is not.
	_frame()
	assert_array(_regions()).is_equal([SHELL, SHELL, ROCKET, SHELL])
	var none: Array[StringName] = []
	snap.weapon_ids = none  # No weapon table: every slot is a shell, and nothing fails.
	_frame()
	assert_array(_regions()).is_equal([SHELL, SHELL, SHELL, SHELL])


func test_the_regions_are_the_shell_and_the_rocket_of_an_atlas_that_keeps_its_size() -> void:
	assert_that(ProjectileLayer.SHELL_REGION).is_equal(SHELL)
	assert_that(ProjectileLayer.ROCKET_REGION).is_equal(ROCKET)
	assert_str(ProjectileLayer.ATLAS_ART).is_equal(ATLAS_PATH)
	assert_str(_layer._atlas.resource_path).is_equal(ATLAS_PATH)  # The quads are cut from it.
	var atlas: Texture2D = load(ATLAS_PATH)
	assert_vector(atlas.get_size()).is_equal(ATLAS_SIZE)
	for region: Rect2 in [SHELL, ROCKET]:
		assert_bool(Rect2(Vector2.ZERO, ATLAS_SIZE).encloses(region)).is_true()
	# The quad is the size of its region in world px (16x8 and 36x12), centred on the shell.
	assert_that(ProjectileLayer.SHELL_QUAD).is_equal(Rect2(-8.0, -4.0, 16.0, 8.0))
	assert_that(ProjectileLayer.ROCKET_QUAD).is_equal(Rect2(-18.0, -6.0, 36.0, 12.0))
	assert_that(ProjectileLayer.SHELL_QUAD.size).is_equal(SHELL.size)
	assert_that(ProjectileLayer.ROCKET_QUAD.size).is_equal(ROCKET.size)
	assert_that(ProjectileLayer.SHELL_QUAD.get_center()).is_equal(Vector2.ZERO)
	assert_that(ProjectileLayer.ROCKET_QUAD.get_center()).is_equal(Vector2.ZERO)


func test_the_draw_code_paints_nothing_but_atlas_quads() -> void:
	# ADR 0011 section 3: one _draw(), atlas quads only. Pixels cannot be read headless, so the
	# script is: every draw call it makes is draw_texture_rect_region, after the draw_set_transform
	# that turns it (the shell and the rocket are turned, which a plain rect cannot be), and there
	# is one _draw().
	var source: String = ""
	for line: String in FileAccess.get_file_as_string(SCRIPT_PATH).split("\n"):
		source += line.get_slice("#", 0) + "\n"
	var calls: Array[String] = []
	var at: int = source.find("draw_")
	while at >= 0:
		var open: int = source.find("(", at)
		calls.append(source.substr(at, open - at))
		at = source.find("draw_", open)
	var quad: String = "draw_texture_rect_region"  # One call for each of the two regions.
	assert_array(calls).is_equal(["draw_set_transform", quad, quad])
	assert_int(source.count("func _draw()")).is_equal(1)
	# _draw is this loop and nothing else: one quad per planned quad, in the plan's order, centred
	# on its place and as big as its region.
	assert_array(_body_lines(source, "_draw")).is_equal(DRAW_BODY)


func test_draw_paints_every_planned_quad_and_none_once_the_last_slot_is_gone() -> void:
	await await_idle_frame()  # The first draw of the new layer is behind us.
	assert_int(_layer.drawn_count()).is_equal(0)
	_set_slot(0, 41, Vector2i(1000, 1000), Vector2i(2000, 1000))
	_set_slot(1, 42, Vector2i(1000, 2000), Vector2i(2000, 2000))
	_frame()
	await await_idle_frame()
	assert_int(_layer.drawn_count()).is_equal(2)
	_runner.snapshot.proj_id[1] = 0  # One lands: the old plan must not stay.
	_frame()
	await await_idle_frame()
	assert_int(_layer.drawn_count()).is_equal(1)
	_runner.snapshot.proj_id[0] = 0  # The last one lands: a frame with no quad redraws too.
	_frame()
	assert_int(_layer.active_count()).is_equal(0)
	await await_idle_frame()
	assert_int(_layer.drawn_count()).is_equal(0)


func test_a_full_pool_of_live_shells_is_planned_and_drawn_slot_for_slot() -> void:
	# The edge of P42b: a full pool (data/rules.tres, 512 slots) is live at once, and the plan must
	# hold one quad, with its three floats, for every slot of it. The even slots fire the shell
	# weapon and the odd ones the rocket; slot s goes from (10 s, 4 s) milli 100 east and 50 north.
	var snap: MatchSnapshot = _runner.snapshot
	var by_name: Array[StringName] = [&"tank_cannon", &"rocket"]
	snap.weapon_ids = by_name
	var pool: int = snap.proj_id.size()
	assert_int(pool).is_equal(_runner.world.max_projectiles)
	for slot: int in pool:
		var from: Vector2i = Vector2i(10 * slot, 4 * slot)
		_set_slot(slot, 100 + slot, from, from + Vector2i(100, -50), 1, slot % 2)
	_frame()
	assert_int(_layer.active_count()).is_equal(pool)
	var heading: float = atan2(-50.0, 100.0)
	var wrong: Array[int] = []  # The quads that are not their slot's own, so that one assertion
	for index: int in pool:  # covers all 512 of them.
		var expected: Vector2 = Vector2(10 * index, 4 * index) * PX_PER_MILLI
		if (
			_layer.quad_slot(index) != index
			or _layer.quad_position(index).distance_to(expected) > 0.01
			or absf(_layer.quad_angle(index) - heading) > 0.0001
			or _layer.quad_region(index) != (ROCKET if index % 2 == 1 else SHELL)
		):
			wrong.append(index)
	assert_array(wrong).is_empty()
	var last: int = pool - 1
	assert_int(_layer.quad_slot(last)).is_equal(last)
	assert_vector(_layer.quad_position(last)).is_equal_approx(
		Vector2(10 * last, 4 * last) * PX_PER_MILLI, _eps()
	)
	assert_float(_layer.quad_angle(last)).is_equal_approx(heading, 0.0001)
	await await_idle_frame()
	assert_int(_layer.drawn_count()).is_equal(pool)


func test_the_plan_grows_when_a_later_snapshot_has_more_slots_than_the_first() -> void:
	# The pool is fixed for a run, but a layer meets the snapshot of another run (other rules, so
	# another pool) and sizes its plan from the snapshot in front of it, not from the first it saw.
	var full: MatchSnapshot = _runner.snapshot
	_runner.snapshot = _small_snapshot(4, 3)
	_frame()
	assert_array(_slots()).is_equal([3])
	var live: Array[int] = [0, 1, 2, 3, 4, 100, 300, full.proj_id.size() - 1]
	_runner.snapshot = full  # 512 slots, of which these eight hold a shell.
	for slot: int in live:
		_set_slot(slot, 70 + slot, Vector2i(10 * slot, 0), Vector2i(10 * slot + 100, 0))
	_frame()
	assert_array(_slots()).is_equal(live)
	var last: int = live.size() - 1
	assert_vector(_layer.quad_position(last)).is_equal_approx(
		Vector2(10 * live[last], 0) * PX_PER_MILLI, _eps()
	)
	_runner.snapshot = _small_snapshot(4, 3)  # And back to a short table: it is not outgrown.
	_frame()
	assert_array(_slots()).is_equal([3])


func test_a_new_match_empties_the_layer_and_a_layer_without_a_snapshot_draws_nothing() -> void:
	_set_slot(0, 51, Vector2i(1000, 1000), Vector2i(2000, 1000))
	_frame()
	assert_int(_layer.active_count()).is_equal(1)
	var serial: int = _runner.snapshot.match_serial
	_runner.start()  # Another match: its slots are all free.
	assert_int(_runner.snapshot.match_serial).is_not_equal(serial)
	_frame()
	assert_int(_layer.active_count()).is_equal(0)
	_set_slot(0, 52, Vector2i(1000, 1000), Vector2i(2000, 1000))
	_frame()
	assert_int(_layer.active_count()).is_equal(1)
	_runner.snapshot = null  # A runner that has no snapshot: nothing, and no script error.
	_frame()
	assert_int(_layer.active_count()).is_equal(0)
	var bare: ProjectileLayer = auto_free(ProjectileLayer.new())
	add_child(bare)
	bare._process(0.0)  # And a layer with no runner at all.
	assert_int(bare.active_count()).is_equal(0)
	bare.runner = auto_free(MatchRunner.new())
	bare._process(0.0)
	assert_int(bare.active_count()).is_equal(0)


func test_frames_leave_no_new_objects_alive() -> void:
	_run_to(World.Event.SHOT)
	_runner.run_ticks(1)
	_frame()
	assert_int(_layer.active_count()).is_greater(0)
	await await_idle_frame()
	await await_idle_frame()  # The first idle frame leaves an object of the test runner behind.
	# Counts are read between the steps and asserted at the end: an assertion is an object too.
	var before: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for _frame_no: int in 20:
		_runner._process(0.002)  # Under one tick in all, so the snapshot stays.
		_layer._process(0.016)
	var after_frames: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	assert_int(_layer.active_count()).is_greater(0)
	assert_float(after_frames).is_equal(before)


func test_the_main_scene_has_the_layer_after_the_bars_at_z_120_in_world_space_at_every_size(
) -> void:
	var main: Node2D = auto_free(load(MAIN_SCENE).instantiate())
	add_child(main)
	var names: Array[StringName] = []
	for child: Node in main.get_children():
		names.append(child.name)
	var at: int = names.find(&"ProjectileLayer")
	assert_int(at).is_greater(names.find(&"HealthBarLayer"))
	assert_int(at).is_less(names.find(&"MarkerLayer"))
	var layer: ProjectileLayer = main.get_node("ProjectileLayer")
	var runner: MatchRunner = main.get_node("MatchRunner")
	var camera: RtsCamera = main.get_node("Camera")
	assert_int(layer.z_index).is_equal(120)
	assert_bool(layer.z_as_relative).is_false()
	assert_object(layer.runner).is_same(runner)
	runner.paused = true  # The scene's runner plays on its own: hold it while the snapshot is set.
	for at_size: int in SIZES.size():
		get_window().size = SIZES[at_size]
		await await_idle_frame()
		assert_vector(camera.get_viewport_rect().size).is_equal(VIEWS[at_size])
		camera.zoom = Vector2.ONE
		camera.centre_on(Vector2(1536, 1536))
		var snap: MatchSnapshot = runner.snapshot
		snap.proj_id[0] = 61
		snap.prev_proj_id[0] = 61
		snap.proj_x[0] = 24000  # The middle of the 48 x 48 map: 1536 px.
		snap.proj_y[0] = 24000
		snap.prev_proj_x[0] = 24000
		snap.prev_proj_y[0] = 24000
		layer._process(0.0)
		assert_int(layer.active_count()).is_equal(1)
		# A world layer: the shell on the middle of the map is seen where the camera looks.
		var seen: Vector2 = camera.world_to_screen(layer.to_global(layer.quad_position(0)))
		assert_vector(seen).is_equal_approx(VIEWS[at_size] * 0.5, Vector2(0.01, 0.01))


## A snapshot slot written for a view case: `slot` live with projectile id `id` of `owner_id`,
## going from `from` to `to` (milli-tiles), in the published snapshot and in the previous tick.
func _set_slot(
	slot: int, id: int, from: Vector2i, to: Vector2i, owner_id: int = 1, weapon: int = 0
) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.proj_id[slot] = id
	snap.prev_proj_id[slot] = id
	snap.proj_owner[slot] = owner_id
	snap.proj_weapon[slot] = weapon
	snap.prev_proj_x[slot] = from.x
	snap.prev_proj_y[slot] = from.y
	snap.proj_x[slot] = to.x
	snap.proj_y[slot] = to.y


## A snapshot of a pool of `slots` projectile slots (the other columns are empty), with slot `live`
## holding a shell that has flown for two ticks, 1000 milli east.
func _small_snapshot(slots: int, live: int) -> MatchSnapshot:
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.proj_id.resize(slots)
	snap.prev_proj_id.resize(slots)
	snap.proj_owner.resize(slots)
	snap.proj_weapon.resize(slots)
	snap.proj_x.resize(slots)
	snap.proj_y.resize(slots)
	snap.prev_proj_x.resize(slots)
	snap.prev_proj_y.resize(slots)
	snap.proj_id[live] = 9
	snap.prev_proj_id[live] = 9
	snap.proj_x[live] = 2000
	snap.prev_proj_x[live] = 1000
	return snap


func _frame() -> void:
	_layer._process(0.0)


func _eps() -> Vector2:
	return Vector2(0.001, 0.001)


## The projectile slot of each quad in the plan, and its region.
func _slots() -> Array[int]:
	var slots: Array[int] = []
	for index: int in _layer.active_count():
		slots.append(_layer.quad_slot(index))
	return slots


func _regions() -> Array[Rect2]:
	var regions: Array[Rect2] = []
	for index: int in _layer.active_count():
		regions.append(_layer.quad_region(index))
	return regions


## The slots that hold a shell in both the last snapshot and the one before (drawn), and those
## that hold one only in the last (new in the last tick).
func _old_slots() -> Array[int]:
	var snap: MatchSnapshot = _runner.snapshot
	var slots: Array[int] = []
	for slot: int in snap.proj_id.size():
		if snap.proj_id[slot] != 0 and snap.proj_id[slot] == snap.prev_proj_id[slot]:
			slots.append(slot)
	return slots


func _new_slots() -> Array[int]:
	var snap: MatchSnapshot = _runner.snapshot
	var slots: Array[int] = []
	for slot: int in snap.proj_id.size():
		if snap.proj_id[slot] != 0 and snap.proj_id[slot] != snap.prev_proj_id[slot]:
			slots.append(slot)
	return slots


## Plays ticks until the snapshot holds an event of `kind`; its tick, or 0 after 100 ticks.
func _run_to(kind: int) -> int:
	for _tick: int in 100:
		_runner.run_ticks(1)
		var events: PackedInt32Array = _runner.snapshot.events
		for at: int in range(0, events.size(), World.EVENT_STRIDE):
			if events[at] == kind:
				return _runner.snapshot.tick
	return 0


## Blue and red light tanks on tiles (10, 10) and (10, 13) of open grass: 3000 milli apart, inside
## the cannon's range of 4500, so they fire at each other from the first tick that picks a target.
func _duel() -> ScenarioDef:
	var scenario: ScenarioDef = ScenarioDef.new()
	var spawns: Array[SpawnDef] = []
	for side: int in 2:
		var spawn: SpawnDef = SpawnDef.new()
		spawn.owner = side + 1
		spawn.unit = load("res://data/units/light_tank.tres")
		spawn.count = 1
		spawn.origin_tile = Vector2i(10, 10 + 3 * side)
		spawns.append(spawn)
	scenario.spawns = spawns
	return scenario


## The trimmed lines of the body of `func <name>(` in `source`, up to the next top-level line.
func _body_lines(source: String, name: String) -> Array[String]:
	var lines: Array[String] = []
	var inside: bool = false
	for line: String in source.split("\n"):
		if line.begins_with("func %s(" % name):
			inside = true
		elif inside and not line.is_empty() and not line.begins_with("\t"):
			break
		elif inside and not line.strip_edges().is_empty():
			lines.append(line.strip_edges())
	return lines
