extends GdUnitTestSuite
## The shipped scenarios at scale (plan P48). The perf arena is played once, for 600 ticks of seed
## 42 through MatchLoop, and sampled at the start of every tick (tick 0 included); the cases read
## what that one run saw. A second, shorter run sends both armies over the ridge, because the
## shipped orders hold each side at a firing line (the pace the gate needs) and so cross it very
## little. The two maps and the controls scenario are read as data.
## Authoring rule (fog, P46b): these cases use the data units, whose acquire range never exceeds
## their sight (P27b), and nothing here engages a target beyond what they acquire, so the vision
## checks of P46b leave them green; the last case pins the ranges that rule leans on.

const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const CONTROLS_PATH: String = "res://data/scenarios/controls_test.tres"
const SEED: int = 42
const TICKS: int = 600
## The 26 x 15 tile window centred on tile (32, 32), as test_defs_data keeps it, in milli-tiles. The
## bounds are inclusive, and the maxima sit 500 inside the window so that a camera on the tile
## corner still sees every unit.
const WINDOW_MIN: Vector2i = Vector2i(19500, 25000)
const WINDOW_MAX: Vector2i = Vector2i(45000, 39500)
## The heavy window the phone gate needs (ADR 0012 section 4): heavy_rigs rows for heavy_frames_min
## frames of the gate's 60 fps, which the case reads from the gate and turns into ticks.
const GATE_PATH: String = "res://data/dev/perf_gate.tres"
const GATE_FPS: int = 60
const MIN_DEATHS: int = 10
## The ridge is the rock of columns 31 and 32: x 31000 up to 33000. Its gaps by tile row, numbered
## 0 to 2 from the north.
const RIDGE_FROM_X: int = 31000
const RIDGE_TO_X: int = 33000
const GAP_OF_ROW: Dictionary[int, int] = {26: 0, 27: 0, 31: 1, 32: 1, 33: 1, 37: 2, 38: 2}
## How far from the ridge a sample counts as beside it, in milli-tiles.
const BESIDE: int = 3000
## The shipped opening orders: each side attack-moves to a firing line two tiles before the ridge,
## on its own side, and holds there.
const FIRING_LINES: Array[Vector2i] = [Vector2i(29, 32), Vector2i(34, 32)]
## The rush: the P27c orders, each side to the other side's spawn centre.
const RUSH: Array[Vector2i] = [Vector2i(39, 32), Vector2i(24, 32)]
const RUSH_TICKS: int = 450
## The controls map's test area, tiles x 6..37 and y 8..28.
const TEST_AREA: Rect2i = Rect2i(6, 8, 32, 21)

var _run: Run


## What a played match leaves, sampled before each tick. An engine base class, so it may sit inside
## this file (P56c).
class Run:
	extends RefCounted
	## Unit samples: the sum of the units alive at the start of every tick.
	var samples: int = 0
	## Per tick from 0, the rows with their centre inside the window.
	var rows_in_window: PackedInt32Array = PackedInt32Array()
	## Samples with the centre on a tile the unit's class cannot enter.
	var blocked: int = 0
	## Samples with the centre in the ridge's columns, and those not on a gap row.
	var in_ridge: int = 0
	var off_gap: int = 0
	## Samples within BESIDE of the ridge, on either side.
	var near_ridge: int = 0
	## Crossings per gap, and those whose last row inside the ridge was no gap row.
	var crossings: PackedInt32Array = PackedInt32Array([0, 0, 0])
	var unmapped: int = 0
	var alive_end: int = 0
	var overflow: int = 0


func before() -> void:
	_run = _play(load(ARENA_PATH) as ScenarioDef, TICKS)


func test_the_arena_starts_with_150_units_75_per_player_with_ids_in_spawn_order() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = _world(scenario)
	assert_int(world.unit_count()).is_equal(150)
	assert_array([world.owner.count(1), world.owner.count(2)]).is_equal([75, 75])
	var row: int = 0
	for spawn: SpawnDef in scenario.spawns:
		for _k: int in spawn.count:
			assert_int(world.unit_id[row]).is_equal(row + 1)
			assert_int(world.owner[row]).is_equal(spawn.owner)
			assert_int(world.type_index[row]).is_equal(world.type_ids.find(spawn.unit.type_id))
			row += 1
	assert_int(row).is_equal(150)
	# Player 1 takes ids 1-75 (30 tanks, 27 rifle squads, 18 rocket squads), then player 2.
	assert_array([world.owner[0], world.owner[74], world.owner[75], world.owner[149]]).is_equal(
		[1, 1, 2, 2]
	)
	assert_int(world.type_index.slice(0, 75).count(0)).is_equal(30)


func test_each_player_gets_one_opening_order_at_tick_0_and_none_after() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = _world(scenario)
	var orders: ScenarioOrders = ScenarioOrders.create(scenario)
	assert_int(orders.order_count()).is_equal(2)
	var out: Array[Command] = []
	orders.collect(world, out)
	assert_int(out.size()).is_equal(2)
	for index: int in 2:
		var player: int = index + 1
		var command: Command = out[index]
		assert_array([command.player_id, command.type]).is_equal([player, Command.Type.ATTACK_MOVE])
		assert_array([command.target_x, command.target_y]).is_equal(
			[FIRING_LINES[index].x * 1000 + 500, FIRING_LINES[index].y * 1000 + 500]
		)
		var movers: PackedInt32Array = PackedInt32Array()
		for row: int in world.unit_count():
			if world.owner[row] == player:
				movers.append(world.unit_id[row])
		assert_int(movers.size()).is_equal(75)
		assert_array(command.unit_ids).is_equal(movers)
	var later: Array[Command] = []
	for tick: int in range(1, TICKS + 1):
		world.tick = tick
		orders.collect(world, later)
	assert_int(later.size()).is_equal(0)


## Each side holds a firing line two tiles before the ridge, on its own side and on open ground,
## mirror images about the middle of the ridge.
func test_the_opening_orders_send_each_side_to_its_firing_line_before_the_ridge() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = _world(scenario)
	for order: OrderDef in scenario.orders:
		var line: Vector2i = FIRING_LINES[order.player - 1]
		assert_that(order.target_tile).is_equal(line)
		assert_int(order.tick).is_equal(0)
		for move_class: int in World.MoveClass.size():
			assert_bool(world.is_passable(line.y * world.map_cols + line.x, move_class)).is_true()
	assert_int(FIRING_LINES[0].x + FIRING_LINES[1].x).is_equal(63)
	assert_bool(FIRING_LINES[0].x < 31 and FIRING_LINES[1].x > 32).is_true()


func test_no_unit_centre_stands_on_a_blocked_tile_for_600_ticks() -> void:
	assert_int(_run.rows_in_window.size()).is_equal(TICKS + 1)
	assert_int(_run.blocked).is_equal(0)
	# Not vacuous, whatever the pace of the fight: every one of the 150 units is sampled for at
	# least 60 ticks (the armies meet later than that), and thousands of samples are beside the ridge.
	assert_int(_run.samples).is_greater(150 * 60)
	assert_int(_run.near_ridge).is_greater(5_000)


## The ridge itself, read from the map the world holds: columns 31 and 32 are rock, shut to every
## movement class, on every row but the gap rows, where both tiles are open. A fourth opening (or a
## closed gap) fails here, whether or not any unit ever walks through it.
@warning_ignore("integer_division")
func test_the_ridge_is_rock_on_every_row_but_the_gap_rows() -> void:
	var world: World = _world(load(ARENA_PATH) as ScenarioDef)
	var wrong: Array[Vector2i] = []
	for y: int in world.map_rows:
		for x: int in range(RIDGE_FROM_X / 1000, RIDGE_TO_X / 1000):
			for move_class: int in World.MoveClass.size():
				var open: bool = world.is_passable(y * world.map_cols + x, move_class)
				if open != GAP_OF_ROW.has(y):
					wrong.append(Vector2i(x, y))
	assert_array(wrong).is_empty()


func test_units_cross_the_ridge_only_through_the_three_gaps() -> void:
	assert_int(_run.off_gap).is_equal(0)
	assert_int(_run.unmapped).is_equal(0)
	assert_int(_run.near_ridge).is_greater(0)


## Both armies sent over the ridge (the P27c orders) go through the gaps, and all three gaps are
## used: the map and the movement hold at arena scale, whatever the shipped orders do.
func test_an_army_sent_across_the_ridge_goes_only_through_the_three_gaps() -> void:
	var run: Run = _play(_scenario_with_orders(RUSH), RUSH_TICKS)
	assert_int(run.blocked).is_equal(0)
	assert_int(run.in_ridge).is_greater(0)
	assert_int(run.off_gap).is_equal(0)
	assert_int(run.unmapped).is_equal(0)
	for gap: int in 3:
		assert_int(run.crossings[gap]).override_failure_message("gap %d" % gap).is_greater(0)


func test_at_least_10_units_die_by_tick_600_and_no_projectile_is_lost() -> void:
	assert_int(150 - _run.alive_end).is_greater_equal(MIN_DEATHS)
	assert_int(_run.overflow).is_equal(0)


## The rows inside the 26 x 15 window: at least heavy_rigs of the 150 (135) for the ticks that
## heavy_frames_min frames take (600 frames at 60 fps are 150 ticks), in a row. Both numbers are the
## gate's own, so a retuned gate moves this case with it.
@warning_ignore("integer_division")
func test_the_window_holds_the_gates_heavy_rows_for_its_heavy_ticks_in_a_row() -> void:
	var gate: PerfGateDef = load(GATE_PATH) as PerfGateDef
	var heavy_rows: int = gate.heavy_rigs
	var heavy_ticks: int = (gate.heavy_frames_min * Sim.TICK_RATE + GATE_FPS - 1) / GATE_FPS
	assert_int(_run.rows_in_window[0]).is_equal(150)
	var longest: int = 0
	var current: int = 0
	for rows: int in _run.rows_in_window:
		current = current + 1 if rows >= heavy_rows else 0
		longest = maxi(longest, current)
	(
		assert_int(longest)
		. override_failure_message("%d rows for %d ticks" % [heavy_rows, heavy_ticks])
		. is_greater_equal(heavy_ticks)
	)


func test_both_maps_pass_validate_and_have_their_sizes() -> void:
	var maps: Dictionary[String, Vector2i] = {
		"res://data/maps/perf_arena.tres": Vector2i(64, 64),
		"res://data/maps/controls_test.tres": Vector2i(48, 48),
	}
	for path: String in maps:
		var map: MapDef = load(path) as MapDef
		assert_array(map.validate()).override_failure_message(path).is_empty()
		assert_that(map.size_tiles()).override_failure_message(path).is_equal(maps[path])
	var arena: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var controls: ScenarioDef = load(CONTROLS_PATH) as ScenarioDef
	assert_str(arena.map.resource_path).is_equal("res://data/maps/perf_arena.tres")
	assert_str(controls.map.resource_path).is_equal("res://data/maps/controls_test.tres")


## No blocked tile in tiles x 6..37, y 8..28 for any movement class (rock, water and scrub all stay
## out of it), which covers every target whose resulting positions an earlier test asserts; the
## spawns are unchanged and each spawn tile is open for its unit's class.
func test_the_controls_test_area_is_open_and_every_spawn_tile_is_passable() -> void:
	var scenario: ScenarioDef = load(CONTROLS_PATH) as ScenarioDef
	var world: World = _world(scenario)
	var shut: Array[Vector2i] = []
	for y: int in range(TEST_AREA.position.y, TEST_AREA.end.y):
		for x: int in range(TEST_AREA.position.x, TEST_AREA.end.x):
			for move_class: int in World.MoveClass.size():
				if not world.is_passable(y * world.map_cols + x, move_class):
					shut.append(Vector2i(x, y))
	assert_array(shut).is_empty()
	var problems: Array[String] = []
	for row: int in world.unit_count():
		var cell: int = world.cell_of(world.pos_x[row], world.pos_y[row])
		var move_class: int = world.type_move_class[world.type_index[row]]
		if not world.is_passable(cell, move_class):
			problems.append("unit %d on cell %d" % [world.unit_id[row], cell])
	assert_int(world.unit_count()).is_equal(40)
	assert_array(problems).is_empty()


## Authoring rule (fog, P46b): acquire never exceeds sight, and a weapon reaches no farther than its
## unit acquires, so a case that engages a target within the weapon range of a data unit also has
## it in sight.
func test_the_data_units_acquire_within_sight_and_fire_within_acquire() -> void:
	var world: World = _world(load(ARENA_PATH) as ScenarioDef)
	assert_int(world.type_ids.size()).is_equal(3)
	for type: int in world.type_ids.size():
		var weapon: int = world.type_weapon[type]
		assert_int(weapon).is_greater_equal(0)
		assert_int(world.weapon_range[weapon]).is_less_equal(world.type_acquire[type])
		assert_int(world.type_acquire[type]).is_less_equal(world.type_sight[type])


## The match of `scenario`: the world with the jitter of seed 42, stepped through the loop with no
## command beyond the scenario's own orders.
func _play(scenario: ScenarioDef, ticks: int) -> Run:
	var world: World = _world(scenario)
	var loop: MatchLoop = MatchLoop.create(scenario, ARENA_PATH, SEED, world)
	var run: Run = Run.new()
	var no_commands: Array[Command] = []
	var side_of: Dictionary[int, int] = {}
	var ridge_row: Dictionary[int, int] = {}
	for tick: int in ticks + 1:
		_sample(world, run, side_of, ridge_row)
		if tick < ticks:
			loop.step(world, no_commands)
	run.alive_end = world.unit_count()
	run.overflow = world.projectile_overflow
	return run


## One look at the match before a tick. The positions and the tables are read once into locals.
@warning_ignore("integer_division")
func _sample(
	world: World, run: Run, side_of: Dictionary[int, int], ridge_row: Dictionary[int, int]
) -> void:
	var count: int = world.unit_count()
	var xs: PackedInt32Array = world.pos_x
	var ys: PackedInt32Array = world.pos_y
	var ids: PackedInt32Array = world.unit_id
	var types: PackedInt32Array = world.type_index
	var classes: PackedInt32Array = world.type_move_class
	var in_window: int = 0
	for row: int in count:
		var x: int = xs[row]
		var y: int = ys[row]
		if x >= WINDOW_MIN.x and y >= WINDOW_MIN.y and x <= WINDOW_MAX.x and y <= WINDOW_MAX.y:
			in_window += 1
		if not world.is_passable(world.cell_of(x, y), classes[types[row]]):
			run.blocked += 1
		if x >= RIDGE_FROM_X - BESIDE and x < RIDGE_TO_X + BESIDE:
			run.near_ridge += 1
		var id: int = ids[row]
		if x >= RIDGE_FROM_X and x < RIDGE_TO_X:
			run.in_ridge += 1
			ridge_row[id] = y / 1000
			if not GAP_OF_ROW.has(y / 1000):
				run.off_gap += 1
		# A unit that changed sides went through the ridge's columns in between (a tick moves a
		# unit far less than their 2000 milli), so the last row it was seen there is its gap.
		var side: int = 0 if x < 32000 else 1
		if side_of.get(id, side) != side:
			var gap: int = GAP_OF_ROW.get(ridge_row.get(id, -1), -1)
			if gap < 0:
				run.unmapped += 1
			else:
				run.crossings[gap] += 1
		side_of[id] = side
	run.samples += count
	run.rows_in_window.append(in_window)


func _world(scenario: ScenarioDef) -> World:
	return World.from_scenario(scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))


## The arena with its two orders aimed at `targets` (player 1's tile, then player 2's) instead. The
## loaded resources are shared, so none is written: the copy has new orders of its own.
func _scenario_with_orders(targets: Array[Vector2i]) -> ScenarioDef:
	var source: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var copy: ScenarioDef = ScenarioDef.new()
	copy.map_size_tiles = source.map_size_tiles
	copy.local_player = source.local_player
	copy.camera_start_tile = source.camera_start_tile
	copy.spawns = source.spawns
	copy.map = source.map
	copy.rules = source.rules
	copy.player_count = source.player_count
	for order: OrderDef in source.orders:
		var moved: OrderDef = OrderDef.new()
		moved.tick = order.tick
		moved.player = order.player
		moved.type = order.type
		moved.target_tile = targets[order.player - 1]
		copy.orders.append(moved)
	return copy
