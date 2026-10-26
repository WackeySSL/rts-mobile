extends GdUnitTestSuite
## PLACE (plan row P73b, ADR 0017 sections 2 and 4, ADR 0018 section 5): a finished structure waits
## ready at the head of the STRUCTURES queue until it is placed or cancelled; PLACE builds it
## complete through `Placement.reason` at the tile that holds the point, and every failing reason,
## a head that is not ready, a payload, another player's queue and the `_playing` gate drop the
## command and count it with the head and the credits as they were. `place_rig.gd` has the world
## (the base world with player 1's headquarters) and takes every cost and tick count from the
## World's tables.

const Rig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const PlaceRig: GDScript = preload("res://tests/sim/support/place_rig.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const STRUCTURES: int = World.Tab.STRUCTURES
const OUTSIDE: int = Placement.Reason.OUTSIDE
const GROUND: int = Placement.Reason.GROUND
const OCCUPIED: int = Placement.Reason.OCCUPIED
const UNEXPLORED: int = Placement.Reason.UNEXPLORED
const TOO_FAR: int = Placement.Reason.TOO_FAR
const CAP: int = Placement.Reason.CAP


## The base world with player 1's power plant ready at the head of its STRUCTURES queue.
func _ready_world(rock: Array = []) -> World:
	var world: World = PlaceRig.world(rock)
	PlaceRig.ready(world, "power_plant")
	return world


## The head's goal in hundredths of a tick: what `queue_progress` holds while it is ready.
func _goal(world: World, id: String) -> int:
	return PlaceRig.build_ticks(world, id) * Production.PROGRESS_PER_TICK


## The state a dropped PLACE leaves: one more dropped command, no new row, the head still ready
## (the plant, at its goal), nothing paid or counted.
func _dropped(
	label: String, world: World, command: Command, col: int, line: int, expected: int
) -> void:
	var queue: int = PlaceRig.queue()
	var plant: int = Worlds.type_of(world, "power_plant")
	var rows: int = world.unit_count()
	var credits: int = world.credits[1]
	var dropped: int = world.dropped_commands
	(
		assert_int(PlaceRig.reason(world, "power_plant", col, line))
		. override_failure_message(label + " reason")
		. is_equal(expected)
	)
	Rig.step(world, [command])
	assert_int(world.dropped_commands).override_failure_message(label).is_equal(dropped + 1)
	assert_int(world.unit_count()).override_failure_message(label + " rows").is_equal(rows)
	(
		assert_array(
			[
				world.queue_count[queue],
				world.queue_progress[queue],
				world.credits[1],
				world.stat_built[1]
			]
		)
		. override_failure_message(label + " queue")
		. is_equal([1, _goal(world, "power_plant"), credits, 0])
	)
	assert_int(world.queue_type[queue * world.queue_slots]).is_equal(plant)


func test_a_ready_structure_waits_until_it_is_placed() -> void:
	var world: World = _ready_world()
	var queue: int = PlaceRig.queue()
	var plant: int = Worlds.type_of(world, "power_plant")
	var credits: int = world.credits[1]
	var rows: int = world.unit_count()
	assert_int(credits).is_equal(world.start_credits - PlaceRig.cost(world, "power_plant"))
	# A PLACE that fails, and then a long wait: the head is still there, ready, paid once.
	Rig.step(world, [PlaceRig.place(12, 12)])
	Rig.run(world, 200)
	assert_array([world.queue_count[queue], world.queue_progress[queue]]).is_equal(
		[1, _goal(world, "power_plant")]
	)
	assert_array(Rig.items(world, 1, STRUCTURES)).is_equal([plant])
	assert_array([world.credits[1], world.unit_count(), world.stat_built[1]]).is_equal(
		[credits, rows, 0]
	)
	assert_int(world.dropped_commands).is_equal(1)
	Rig.step(world, [PlaceRig.place(PlaceRig.SPOT.x, PlaceRig.SPOT.y)])
	assert_array([world.unit_count(), world.stat_built[1], world.dropped_commands]).is_equal(
		[rows + 1, 1, 1]
	)


## COMMANDS runs before PRODUCTION: the PLACE of the step that brings the head to its goal sees it
## one step short and is dropped; the same PLACE a step later builds.
func test_the_head_is_ready_on_the_step_after_its_last_tick() -> void:
	var world: World = PlaceRig.world()
	var ticks: int = PlaceRig.build_ticks(world, "power_plant")
	var queue: int = PlaceRig.queue()
	var rows: int = world.unit_count()
	Rig.step(world, [Rig.queue(world, 1, "power_plant")])
	Rig.run(world, ticks - 2)
	assert_int(world.queue_progress[queue]).is_equal(_goal(world, "power_plant") - 100)
	Rig.step(world, [PlaceRig.place(PlaceRig.SPOT.x, PlaceRig.SPOT.y)])
	assert_array([world.dropped_commands, world.unit_count()]).is_equal([1, rows])
	assert_int(world.queue_progress[queue]).is_equal(_goal(world, "power_plant"))
	Rig.step(world, [PlaceRig.place(PlaceRig.SPOT.x, PlaceRig.SPOT.y)])
	assert_array([world.dropped_commands, world.unit_count()]).is_equal([1, rows + 1])


func test_a_place_builds_the_head_complete_on_the_tile_of_the_point() -> void:
	var world: World = _ready_world()
	var queue: int = PlaceRig.queue()
	var plant: int = Worlds.type_of(world, "power_plant")
	var credits: int = world.credits[1]
	var open: Array[int] = Worlds.costs_at(world, 5 * Rig.COLS + 8)
	assert_array(open).is_equal([10, 10, 10])
	# The point (6700, 5300) lies in tile (6, 5), the footprint's top-left tile.
	Rig.step(world, [PlaceRig.place(6, 5)])
	var row: int = world.unit_count() - 1
	assert_array([world.owner[row], world.type_index[row]]).is_equal([1, plant])
	assert_int(world.hp[row]).is_equal(world.type_max_hp[plant])
	assert_vector(world.footprint_origin(row)).is_equal(Vector2i(6, 5))
	assert_array([world.pos_x[row], world.pos_y[row]]).is_equal([7000, 6000])
	for cell: Vector2i in [Vector2i(6, 5), Vector2i(7, 5), Vector2i(6, 6), Vector2i(7, 6)]:
		assert_array(Worlds.costs_at(world, cell.y * Rig.COLS + cell.x)).is_equal([0, 0, 0])
	assert_array(Worlds.costs_at(world, 5 * Rig.COLS + 8)).is_equal(open)
	assert_array(world.events).is_equal(
		[World.Event.SPAWNED, world.unit_id[row], 7000, 6000, plant, 1, 0, 0]
	)
	# The cost was paid when the item was queued; the head is gone and the build counted.
	assert_array([world.queue_count[queue], world.queue_progress[queue]]).is_equal([0, 0])
	assert_int(world.queue_type[queue * world.queue_slots]).is_equal(-1)
	assert_array([world.credits[1], world.stat_built[1], world.dropped_commands]).is_equal(
		[credits, 1, 0]
	)
	# The building is no unit: it moves nothing and gives no free unit.
	assert_int(ProductionSpawn.mobile_rows(world, 1)).is_equal(0)


func test_each_failing_reason_drops_the_place_and_keeps_the_head_ready() -> void:
	_dropped("ground", _ready_world([Vector2i(7, 6)]), PlaceRig.place(6, 5), 6, 5, GROUND)
	var occupied: World = _ready_world()
	occupied.add_unit(2, Worlds.type_of(occupied, "harvester"), 6500, 5500)
	_dropped("occupied", occupied, PlaceRig.place(6, 5), 6, 5, OCCUPIED)
	var unexplored: World = _ready_world()
	unexplored.fog.explored[5 * Rig.COLS + 6] = 0  # Player 1's block comes first.
	_dropped("unexplored", unexplored, PlaceRig.place(6, 5), 6, 5, UNEXPLORED)
	_dropped("too far", _ready_world(), PlaceRig.place(12, 12), 12, 12, TOO_FAR)
	var capped: World = _ready_world()
	capped.building_cap = 5  # The headquarters and four more: the enemy's barracks does not count.
	_dropped("cap", capped, PlaceRig.place(6, 5), 6, 5, CAP)
	var outside: World = _ready_world()
	_dropped("east edge", outside, PlaceRig.place(23, 5), 23, 5, OUTSIDE)
	_dropped("south edge", outside, PlaceRig.place(6, 15), 6, 15, OUTSIDE)
	_dropped("past the map", outside, Command.place(1, 40000, 5500), 40, 5, OUTSIDE)
	_dropped("negative x", outside, Command.place(1, -500, 5500), -1, 5, OUTSIDE)
	# `/` truncates -1 to 0: without the guard this point would be tile (6, 0), a valid one.
	assert_int(PlaceRig.reason(outside, "power_plant", 6, 0)).is_equal(Placement.Reason.OK)
	_dropped("negative y", outside, Command.place(1, 6500, -1), 6, -1, OUTSIDE)


## ADR 0017 section 4: any point inside the origin tile selects it, the tile's west and north edge
## included. A point on the zero line is tile column or row 0 (an origin at the map's west or
## north edge is a valid placement), not outside the map; only a negative point is outside.
func test_a_point_on_the_zero_line_is_the_origin_tile_of_column_or_row_zero() -> void:
	var west: World = _ready_world()
	Rig.step(west, [Command.place(1, 0, 5500)])
	var row: int = west.unit_count() - 1
	assert_array([west.dropped_commands, west.stat_built[1]]).is_equal([0, 1])
	assert_vector(west.footprint_origin(row)).is_equal(Vector2i(0, 5))
	var north: World = _ready_world()
	Rig.step(north, [Command.place(1, 6500, 0)])
	row = north.unit_count() - 1
	assert_array([north.dropped_commands, north.stat_built[1]]).is_equal([0, 1])
	assert_vector(north.footprint_origin(row)).is_equal(Vector2i(6, 0))


## The reason is judged again on every PLACE: the same head fits once the cap lifts, and the
## other player's rows do not count against player 1's cap.
func test_a_head_stopped_by_the_cap_goes_down_when_the_cap_lifts() -> void:
	var world: World = PlaceRig.world()
	var ticks: int = PlaceRig.build_ticks(world, "power_plant")
	world.building_cap = 6  # Five buildings of player 1 now; the barracks of player 2 is the sixth.
	Rig.step(world, [Rig.queue(world, 1, "power_plant"), Rig.queue(world, 1, "power_plant", 1)])
	Rig.run(world, ticks - 1)
	Rig.step(world, [PlaceRig.place(6, 5)])
	assert_array([world.dropped_commands, world.stat_built[1]]).is_equal([0, 1])
	Rig.run(world, ticks - 1)
	assert_int(PlaceRig.reason(world, "power_plant", 6, 7)).is_equal(CAP)
	Rig.step(world, [PlaceRig.place(6, 7)])
	assert_array([world.dropped_commands, world.stat_built[1]]).is_equal([1, 1])
	assert_int(world.queue_count[PlaceRig.queue()]).is_equal(1)
	world.building_cap = 7
	Rig.step(world, [PlaceRig.place(6, 7)])
	assert_array([world.dropped_commands, world.stat_built[1]]).is_equal([1, 2])
	assert_int(world.queue_count[PlaceRig.queue()]).is_equal(0)


## No carry: the item behind the head starts at 0 when the head is placed, and the PLACE step's own
## PRODUCTION already gives it 100, so it is ready as many steps later as its build ticks.
func test_the_next_structure_starts_from_zero_after_a_place() -> void:
	var world: World = PlaceRig.world()
	var ticks: int = PlaceRig.build_ticks(world, "power_plant")
	var queue: int = PlaceRig.queue()
	Rig.step(world, [Rig.queue(world, 1, "power_plant"), Rig.queue(world, 1, "power_plant", 1)])
	Rig.run(world, ticks - 1)
	assert_int(world.queue_progress[queue]).is_equal(_goal(world, "power_plant"))
	Rig.step(world, [PlaceRig.place(6, 5)])
	assert_array([world.queue_count[queue], world.queue_progress[queue]]).is_equal([1, 100])
	Rig.run(world, ticks - 2)
	Rig.step(world, [PlaceRig.place(6, 7)])
	assert_int(world.dropped_commands).is_equal(1)
	assert_int(world.queue_progress[queue]).is_equal(_goal(world, "power_plant"))
	Rig.step(world, [PlaceRig.place(6, 7)])
	assert_array([world.queue_count[queue], world.stat_built[1]]).is_equal([0, 2])
	assert_int(world.credits[1]).is_equal(
		world.start_credits - 2 * PlaceRig.cost(world, "power_plant")
	)


## A ready structure is cancelled like any item: the whole cost comes back and a later PLACE has no
## head to build.
func test_a_ready_structure_can_be_cancelled_for_its_whole_cost() -> void:
	var world: World = _ready_world()
	Rig.step(world, [Command.cancel(1, STRUCTURES, 0)])
	assert_array([world.credits[1], world.queue_count[PlaceRig.queue()]]).is_equal(
		[world.start_credits, 0]
	)
	assert_int(world.queue_progress[PlaceRig.queue()]).is_equal(0)
	var rows: int = world.unit_count()
	Rig.step(world, [PlaceRig.place(6, 5)])
	assert_array([world.dropped_commands, world.unit_count(), world.stat_built[1]]).is_equal(
		[1, rows, 0]
	)


## A payload, a player with no queue and a head that is not there are refused by the module.
func test_place_refuses_a_payload_another_players_queue_and_an_empty_queue() -> void:
	var world: World = _ready_world()
	var rows: int = world.unit_count()
	var payload: Command = PlaceRig.place(6, 5)
	payload.payload = PackedInt32Array([Worlds.type_of(world, "power_plant")])
	assert_bool(Production.apply_place(world, payload)).is_false()
	assert_bool(Production.apply_place(world, PlaceRig.place(6, 5, 2))).is_false()
	assert_array([world.unit_count(), world.queue_count[PlaceRig.queue()]]).is_equal([rows, 1])
	assert_bool(Production.apply_place(world, PlaceRig.place(6, 5))).is_true()
	assert_bool(Production.apply_place(world, PlaceRig.place(6, 7))).is_false()


## The first tile where `player` may place the type `id` now (`Placement.Reason.OK`), scanning
## lines then columns; (-1, -1) when there is none.
func _fitting_tile(world: World, player: int, id: String) -> Vector2i:
	var input: PlacementInput = PlacementInput.of_world(world)
	var type: int = Worlds.type_of(world, id)
	for line: int in world.map_rows:
		for col: int in world.map_cols:
			if Placement.reason(input, player, type, col, line) == Placement.Reason.OK:
				return Vector2i(col, line)
	return Vector2i(-1, -1)


## PLACE reads the placing player's own STRUCTURES queue: player 2 places its own ready plant
## while player 1's queue is empty, and the new building is player 2's.
func test_a_place_reads_the_placing_players_own_structures_queue() -> void:
	var world: World = PlaceRig.world()
	assert_int(world.add_building(2, Worlds.type_of(world, "headquarters"), 12, 11)).is_not_zero()
	Rig.step(world, [Rig.queue(world, 2, "power_plant")])
	Rig.run(world, PlaceRig.build_ticks(world, "power_plant") - 1)
	var own: int = Rig.queue_of(2, STRUCTURES)
	assert_int(world.queue_progress[own]).is_equal(_goal(world, "power_plant"))
	assert_int(world.queue_count[PlaceRig.queue()]).is_equal(0)
	var spot: Vector2i = _fitting_tile(world, 2, "power_plant")
	assert_vector(spot).is_not_equal(Vector2i(-1, -1))
	var rows: int = world.unit_count()
	Rig.step(world, [PlaceRig.place(spot.x, spot.y, 2)])
	assert_int(world.unit_count()).is_equal(rows + 1)
	assert_int(world.owner[world.unit_count() - 1]).is_equal(2)
	assert_array([world.queue_count[own], world.stat_built[2], world.stat_built[1]]).is_equal(
		[0, 1, 0]
	)


## PLACE asks for a ready head and a fitting tile, not for a producer: a structure that was finished
## before its headquarters died stays ready and can still be placed (a queue without a producer only
## stops gaining progress).
func test_a_finished_structure_can_be_placed_after_its_headquarters_is_lost() -> void:
	var world: World = _ready_world()
	var headquarters: int = Rig.rows_of(world, 1, "headquarters")[0]
	world.hp[headquarters] = 0
	Rig.step(world)
	assert_int(Production.producer_row(world, 1, STRUCTURES)).is_equal(-1)
	(
		assert_array([world.queue_count[PlaceRig.queue()], world.queue_progress[PlaceRig.queue()]])
		. is_equal([1, _goal(world, "power_plant")])
	)
	var rows: int = world.unit_count()
	Rig.step(world, [PlaceRig.place(6, 5)])
	assert_array([world.dropped_commands, world.unit_count(), world.stat_built[1]]).is_equal(
		[0, rows + 1, 1]
	)


## P70b's follow-up: the gate is Sim's, not the module's. A defeated player's PLACE is dropped and
## counted by `Sim.step` with a ready head and a fitting tile; the module itself would build.
func test_a_defeated_players_place_is_dropped_by_the_gate() -> void:
	var world: World = _ready_world()
	var rows: int = world.unit_count()
	world.defeated_tick[1] = 1
	Rig.step(world, [PlaceRig.place(6, 5)])
	assert_array([world.dropped_commands, world.unit_count(), world.stat_built[1]]).is_equal(
		[1, rows, 0]
	)
	assert_int(world.queue_count[PlaceRig.queue()]).is_equal(1)
	assert_int(PlaceRig.reason(world, "power_plant", 6, 5)).is_equal(Placement.Reason.OK)
	assert_bool(Production.apply_place(world, PlaceRig.place(6, 5))).is_true()
	assert_array([world.unit_count(), world.stat_built[1]]).is_equal([rows + 1, 1])
