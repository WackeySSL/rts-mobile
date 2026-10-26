extends GdUnitTestSuite
## The free harvester of a placed refinery (plan row P73b, ADR 0018 sections 3 and 5): it appears at
## the dock in SEEK with `home` set to the refinery, the walk of the exit rule takes over when the
## dock is closed, and at `unit_cap` mobile rows, with a full row table or with no open ring tile
## the refinery comes without one, with nothing held or owed. `place_rig.gd` has the world: a 3x3
## refinery at tile (6, 5) has its dock at tile (7, 8). A replay-style run closes the suite.

const Rig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const PlaceRig: GDScript = preload("res://tests/sim/support/place_rig.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const ROCK: int = 2  # The index of '#' in GridWorld.GROUND.
const DOCK_CENTRE: Vector2i = Vector2i(7500, 8500)


## The base world with a refinery ready at the head of player 1's STRUCTURES queue.
func _ready_world(rock: Array = []) -> World:
	var world: World = PlaceRig.world(rock)
	PlaceRig.ready(world, "refinery")
	return world


## Places the ready refinery at the spot and returns its id.
func _place(world: World) -> int:
	Rig.step(world, [PlaceRig.place(PlaceRig.SPOT.x, PlaceRig.SPOT.y)])
	var rows: Array[int] = Rig.rows_of(world, 1, "refinery")
	return world.unit_id[rows[rows.size() - 1]]


## The rows of player 1's harvesters whose home is the building `id`.
func _homed(world: World, id: int) -> Array[int]:
	var found: Array[int] = []
	for row: int in Rig.rows_of(world, 1, "harvester"):
		if world.home[row] == id:
			found.append(row)
	return found


## `count` unarmed harvesters of `player` in the south east, a tile apart and far from everything
## else (player 1's on row 14, player 2's on row 12), so that nothing fights, overlaps a footprint
## or blocks a ring tile.
func _fill(world: World, player: int, count: int) -> void:
	for index: int in count:
		world.add_unit(
			player,
			Worlds.type_of(world, "harvester"),
			14500 + index * 1000,
			14500 - (player - 1) * 2000
		)


func test_the_refinery_comes_with_a_harvester_at_the_dock_in_seek_with_home_set() -> void:
	var world: World = _ready_world()
	var id: int = _place(world)
	var rows: Array[int] = _homed(world, id)
	assert_array(rows).has_size(1)
	var row: int = rows[0]
	assert_array([world.owner[row], world.harvest_mode[row]]).is_equal([1, World.HarvestMode.SEEK])
	assert_array([world.cargo[row], world.harvest_slot[row], world.order[row]]).is_equal(
		[0, -1, World.Order.IDLE]
	)
	assert_array([world.pos_x[row], world.pos_y[row]]).is_equal([DOCK_CENTRE.x, DOCK_CENTRE.y])
	assert_int(world.hp[row]).is_equal(world.type_max_hp[world.type_index[row]])
	# The building's record first, then the harvester's; the build counts, the free unit does not.
	var harvester: int = Worlds.type_of(world, "harvester")
	var refinery: int = Worlds.type_of(world, "refinery")
	(
		assert_array(world.events)
		. is_equal(
			[
				World.Event.SPAWNED,
				id,
				7500,
				6500,
				refinery,
				1,
				0,
				0,
				World.Event.SPAWNED,
				world.unit_id[row],
				7500,
				8500,
				harvester,
				1,
				0,
				0,
			]
		)
	)
	assert_array([world.stat_built[1], world.dropped_commands, world.spawn_refused]).is_equal(
		[1, 0, 0]
	)
	assert_int(ProductionSpawn.mobile_rows(world, 1)).is_equal(1)
	assert_int(world.stats[World.Stat.EXIT_SCANNED]).is_equal(1)
	# The refinery's own row carries no home, and the other refinery's harvesters are not this one's.
	assert_int(world.home[world.index_of(id)]).is_equal(0)
	assert_array(_homed(world, Rig.REFINERY)).is_empty()


## The dock is closed to the harvester's class: the walk of the exit rule goes on clockwise from it,
## past the closed tile to the next open one of the ring (tile (6, 8), the second scanned).
func test_a_closed_dock_hands_the_harvester_to_the_next_open_ring_tile() -> void:
	var world: World = _ready_world([Vector2i(7, 8)])
	var id: int = _place(world)
	var rows: Array[int] = _homed(world, id)
	assert_array(rows).has_size(1)
	assert_array([world.pos_x[rows[0]], world.pos_y[rows[0]]]).is_equal([6500, 8500])
	assert_int(world.stats[World.Stat.EXIT_SCANNED]).is_equal(2)


## A ring with no open tile leaves the refinery without a harvester: it is placed, and nothing is
## owed when a tile opens later.
func test_a_refinery_with_no_open_ring_tile_comes_without_a_harvester() -> void:
	var ring: Array[Vector2i] = []
	for at: int in ProductionSpawn.ring_length(Vector2i(3, 3)):
		ring.append(ProductionSpawn.ring_tile(PlaceRig.SPOT, Vector2i(3, 3), at))
	var world: World = _ready_world(ring)
	var id: int = _place(world)
	assert_int(world.index_of(id)).is_greater_equal(0)
	assert_array([world.stat_built[1], world.dropped_commands]).is_equal([1, 0])
	assert_int(world.stats[World.Stat.EXIT_SCANNED]).is_equal(ring.size())
	# No harvester, so no `home` is written anywhere: the refinery's own stays 0.
	assert_int(world.home[world.index_of(id)]).is_equal(0)
	world.set_terrain(8 * Rig.COLS + 7, 0)
	Rig.run(world, 60)
	assert_array(Rig.rows_of(world, 1, "harvester")).is_empty()


## ADR 0018 section 3: a side never has more than `unit_cap` mobile rows. The free harvester is one
## of them, so one below the cap it fills the last place and at the cap it is left out. Only the
## placing player's rows count, and nothing is owed afterwards: a unit that dies later does not
## bring the harvester back.
func test_the_free_harvester_counts_against_the_unit_cap() -> void:
	# unit_cap, own mobile rows, the enemy's mobile rows, whether the harvester comes.
	var cases: Array[Array] = [
		[3, 2, 0, true],
		[3, 2, 5, true],
		[3, 3, 0, false],
		[3, 4, 0, false],
	]
	for case: Array in cases:
		var label: String = str(case)
		var world: World = PlaceRig.world()
		world.unit_cap = case[0]
		_fill(world, 1, case[1])
		_fill(world, 2, case[2])
		PlaceRig.ready(world, "refinery")
		var id: int = _place(world)
		var expected: int = case[1] + (1 if case[3] else 0)
		assert_int(_homed(world, id).size()).override_failure_message(label).is_equal(
			1 if case[3] else 0
		)
		assert_int(ProductionSpawn.mobile_rows(world, 1)).override_failure_message(label).is_equal(
			expected
		)
		assert_array([world.stat_built[1], world.spawn_refused, world.dropped_commands]).is_equal(
			[1, 0, 0]
		)
		assert_int(world.queue_count[PlaceRig.queue()]).is_equal(0)
		if case[3]:
			continue
		var filler: int = Rig.rows_of(world, 1, "harvester")[0]
		world.hp[filler] = 0
		Rig.run(world, 60)
		assert_int(ProductionSpawn.mobile_rows(world, 1)).override_failure_message(label).is_equal(
			expected - 1
		)
		assert_array(_homed(world, id)).override_failure_message(label).is_empty()


## A full row table: with one free row the building takes it and the refinery comes without a
## harvester (a hold, not a refusal: `spawn_refused` stays 0); with none the building is refused,
## the command is dropped and the head stays ready, so a later PLACE can build it.
func test_the_free_harvester_needs_a_free_row_and_the_building_needs_one_too() -> void:
	var world: World = _ready_world()
	var rows: int = world.unit_count()
	world.max_rows = rows + 1
	var id: int = _place(world)
	assert_int(world.unit_count()).is_equal(rows + 1)
	assert_array(_homed(world, id)).is_empty()
	assert_array([world.stat_built[1], world.spawn_refused, world.dropped_commands]).is_equal(
		[1, 0, 0]
	)
	var full: World = _ready_world()
	full.max_rows = full.unit_count()
	var open: Array[int] = Worlds.costs_at(full, 5 * Rig.COLS + 6)
	Rig.step(full, [PlaceRig.place(PlaceRig.SPOT.x, PlaceRig.SPOT.y)])
	assert_array([full.dropped_commands, full.spawn_refused, full.stat_built[1]]).is_equal(
		[1, 1, 0]
	)
	assert_int(full.queue_count[PlaceRig.queue()]).is_equal(1)
	assert_array(Worlds.costs_at(full, 5 * Rig.COLS + 6)).is_equal(open)
	full.max_rows += 2
	Rig.step(full, [PlaceRig.place(PlaceRig.SPOT.x, PlaceRig.SPOT.y)])
	assert_array([full.dropped_commands, full.stat_built[1]]).is_equal([1, 1])


## The rule reads the type tables, not a name: a building with no free unit gives none, one whose
## dock is (0, 0), the tile that means "none", gives none, and a dock with a free unit gives it at
## that dock.
func test_the_free_unit_comes_from_the_free_unit_and_the_dock_of_the_type() -> void:
	var world: World = PlaceRig.world()
	var plant: int = Worlds.type_of(world, "power_plant")
	var harvester: int = Worlds.type_of(world, "harvester")
	PlaceRig.ready(world, "power_plant")
	world.type_free_unit[plant] = harvester
	Rig.step(world, [PlaceRig.place(6, 5)])
	assert_array([world.stat_built[1], ProductionSpawn.mobile_rows(world, 1)]).is_equal([1, 0])
	world.type_dock_x[plant] = 1
	world.type_dock_y[plant] = 2
	PlaceRig.ready(world, "power_plant")
	Rig.step(world, [PlaceRig.place(6, 8)])
	var plants: Array[int] = Rig.rows_of(world, 1, "power_plant")
	var made: Array[int] = _homed(world, world.unit_id[plants[plants.size() - 1]])
	assert_array(made).has_size(1)
	assert_array([world.pos_x[made[0]], world.pos_y[made[0]]]).is_equal([7500, 10500])
	assert_int(world.harvest_mode[made[0]]).is_equal(World.HarvestMode.SEEK)


## The same commands on the same data give the same checkpoints, the same rows and a harvester;
## a world that was not given them differs (MatchLoop is the tick driver of a replay).
func test_queue_and_place_are_deterministic_over_a_replay_style_run() -> void:
	var hashes: Array[PackedInt64Array] = []
	var finals: Array[PackedInt32Array] = []
	for _attempt: int in 2:
		var world: World = PlaceRig.world()
		var ticks: int = PlaceRig.build_ticks(world, "refinery")
		var loop: MatchLoop = MatchLoop.create(null, "", 1, world)
		for tick: int in ticks + 90:
			var commands: Array[Command] = []
			if tick == 0:
				commands.append(Rig.queue(world, 1, "refinery"))
			elif tick == ticks:
				commands.append(PlaceRig.place(PlaceRig.SPOT.x, PlaceRig.SPOT.y))
			loop.step(world, commands)
		hashes.append(loop.replay.checkpoint_hashes)
		finals.append(world.unit_id)
		assert_int(world.stat_built[1]).is_equal(1)
		assert_int(Rig.rows_of(world, 1, "harvester").size()).is_equal(1)
		assert_int(world.dropped_commands).is_equal(0)
	assert_array(hashes[0]).is_equal(hashes[1])
	assert_array(finals[0]).is_equal(finals[1])
	assert_int(finals[0].size()).is_equal(6 + 2)
	var idle: World = PlaceRig.world()
	var loop: MatchLoop = MatchLoop.create(null, "", 1, idle)
	for _tick: int in PlaceRig.build_ticks(idle, "refinery") + 90:
		loop.step(idle, [])
	assert_array(loop.replay.checkpoint_hashes).is_not_equal(hashes[0])
