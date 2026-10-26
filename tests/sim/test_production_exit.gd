extends GdUnitTestSuite
## Where a finished unit appears and when it has to wait (plan row P73, ADR 0018 section 5): the
## exit tile, the clockwise walk of the ring around the footprint when it is closed to the unit's
## class, `Stat.EXIT_SCANNED`, a ring cut by the map edge, and the holds at 100 % (no open exit
## tile, `unit_cap` mobile rows, `max_rows`). The barracks of the base world is a 2x2 at tile
## (8, 1), exit tile (9, 3); its ring clockwise from the top-left corner is (7,0) (8,0) (9,0)
## (10,0) (10,1) (10,2) (10,3) (9,3) (8,3) (7,3) (7,2) (7,1), twelve tiles, the exit the eighth.

const Rig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const INFANTRY: int = World.Tab.INFANTRY
const ROCK: int = 2  # The index of '#' in GridWorld.GROUND.
const SCRUB: int = 1  # '^': foot units only.
const GRASS: int = 0


func _scanned(world: World) -> int:
	return world.stats[World.Stat.EXIT_SCANNED]


func _block(world: World, tiles: Array[Vector2i], terrain: int = ROCK) -> void:
	for tile: Vector2i in tiles:
		world.set_terrain(tile.y * world.map_cols + tile.x, terrain)


## A rifle squad queued on tick 0 and run to the step before it is done; the next step finishes it.
func _almost_done(world: World) -> void:
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad")])
	Rig.run(world, 73)


func _rifles(world: World) -> Array[int]:
	return Rig.rows_of(world, 1, "rifle_squad")


@warning_ignore("integer_division")
func _tile_of(world: World, row: int) -> Vector2i:
	return Vector2i(world.pos_x[row] / 1000, world.pos_y[row] / 1000)


func test_the_ring_is_every_neighbour_of_the_footprint_once_in_clockwise_order() -> void:
	var origin: Vector2i = Vector2i(8, 1)
	var barracks: Array[Vector2i] = []
	for at: int in 12:
		barracks.append(ProductionSpawn.ring_tile(origin, Vector2i(2, 2), at))
	(
		assert_array(barracks)
		. is_equal(
			[
				Vector2i(7, 0),
				Vector2i(8, 0),
				Vector2i(9, 0),
				Vector2i(10, 0),
				Vector2i(10, 1),
				Vector2i(10, 2),
				Vector2i(10, 3),
				Vector2i(9, 3),
				Vector2i(8, 3),
				Vector2i(7, 3),
				Vector2i(7, 2),
				Vector2i(7, 1),
			]
		)
	)
	for size: Vector2i in [Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3), Vector2i(3, 2)]:
		var length: int = ProductionSpawn.ring_length(size)
		assert_int(length).is_equal(2 * (size.x + size.y) + 4)
		var seen: Dictionary[Vector2i, bool] = {}
		var previous: Vector2i = ProductionSpawn.ring_tile(origin, size, length - 1)
		for at: int in length:
			var tile: Vector2i = ProductionSpawn.ring_tile(origin, size, at)
			var gap: Vector2i = Vector2i(
				maxi(maxi(origin.x - tile.x, tile.x - (origin.x + size.x - 1)), 0),
				maxi(maxi(origin.y - tile.y, tile.y - (origin.y + size.y - 1)), 0)
			)
			assert_array([gap.x <= 1, gap.y <= 1, gap != Vector2i.ZERO]).is_equal(
				[true, true, true]
			)
			assert_bool(seen.has(tile)).is_false()
			seen[tile] = true
			# Each tile is one step from the one before it, the last from the first.
			assert_int(absi(tile.x - previous.x) + absi(tile.y - previous.y)).is_equal(1)
			previous = tile
		assert_int(seen.size()).is_equal(length)


func test_an_open_exit_tile_is_the_spawn_tile_and_costs_one_scan() -> void:
	var world: World = Rig.base()
	_almost_done(world)
	assert_int(_scanned(world)).is_equal(0)
	Rig.step(world)
	assert_vector(_tile_of(world, _rifles(world)[0])).is_equal(Vector2i(9, 3))
	assert_int(_scanned(world)).is_equal(1)
	Rig.step(world)
	assert_int(_scanned(world)).is_equal(0)


## The walk goes on clockwise from the exit tile, round the corner and past ring tile 0.
func test_a_closed_exit_tile_hands_the_unit_to_the_next_open_ring_tile_clockwise() -> void:
	var cases: Array[Array] = [
		[[Vector2i(9, 3)], Vector2i(8, 3), 2],
		[[Vector2i(9, 3), Vector2i(8, 3)], Vector2i(7, 3), 3],
		[[Vector2i(9, 3), Vector2i(8, 3), Vector2i(7, 3)], Vector2i(7, 2), 4],
		[
			[Vector2i(9, 3), Vector2i(8, 3), Vector2i(7, 3), Vector2i(7, 2), Vector2i(7, 1)],
			Vector2i(7, 0),
			6
		],
	]
	for case: Array in cases:
		var world: World = Rig.base()
		var closed: Array[Vector2i] = []
		closed.assign(case[0])
		_block(world, closed)
		_almost_done(world)
		Rig.step(world)
		var rifles: Array[int] = _rifles(world)
		assert_array(rifles).override_failure_message(str(case)).has_size(1)
		assert_vector(_tile_of(world, rifles[0])).override_failure_message(str(case)).is_equal(
			case[1]
		)
		assert_int(_scanned(world)).override_failure_message(str(case)).is_equal(case[2])


## The exit tile is judged for the unit's own class: scrub is open to foot units and not to
## tracked ones (ring walk of the 3x3 vehicle factory at (17, 1), exit tile (18, 4): clockwise it
## goes west along the bottom row to (17, 4)).
func test_the_walk_asks_the_class_of_the_unit() -> void:
	var world: World = Rig.base()
	_block(world, [Vector2i(18, 4)], SCRUB)
	var factory: int = world.index_of(Rig.FACTORY)
	world.stats.fill(0)
	var foot: Vector2i = ProductionSpawn.exit_tile(world, factory, World.MoveClass.FOOT)
	assert_array([foot, _scanned(world)]).is_equal([Vector2i(18, 4), 1])
	world.stats.fill(0)
	var tracked: Vector2i = ProductionSpawn.exit_tile(world, factory, World.MoveClass.TRACKED)
	assert_array([tracked, _scanned(world)]).is_equal([Vector2i(17, 4), 2])
	# And through the phase: a harvester (tracked) appears on the next tile.
	Rig.step(world, [Rig.queue(world, 1, "harvester")])
	Rig.run(world, 298)
	assert_int(_scanned(world)).is_equal(0)
	Rig.step(world)
	var rows: Array[int] = Rig.rows_of(world, 1, "harvester")
	assert_vector(_tile_of(world, rows[0])).is_equal(Vector2i(17, 4))
	assert_int(_scanned(world)).is_equal(2)


## A barracks in the corner of the map: seven of its twelve ring tiles are off the map and are
## skipped without a count. With the exit tile (1, 2) and (0, 2) closed the walk goes on clockwise
## past the left side and the top, off the map all the way, to (2, 0).
func test_ring_tiles_off_the_map_are_skipped_and_not_counted() -> void:
	var world: World = Worlds.world(GridWorld.grass(12, 8), Rig.IDS)
	world.add_building(1, Worlds.type_of(world, "barracks"), 0, 0)
	Rig.add_plant(world, 1, 8, 4)
	_block(world, [Vector2i(1, 2), Vector2i(0, 2)])
	_almost_done(world)
	Rig.step(world)
	assert_vector(_tile_of(world, _rifles(world)[0])).is_equal(Vector2i(2, 0))
	assert_int(_scanned(world)).is_equal(3)


## With every ring tile closed the finished unit waits at 100 % with its credits spent: the queue
## and the progress stay, nothing is refused (`spawn_refused`), each tick looks at the twelve
## tiles, and it comes out the tick after one opens.
func test_a_unit_with_no_open_exit_tile_waits_at_full_progress_until_one_opens() -> void:
	var world: World = Rig.base()
	var ring: Array[Vector2i] = []
	for at: int in ProductionSpawn.ring_length(Vector2i(2, 2)):
		ring.append(ProductionSpawn.ring_tile(Vector2i(8, 1), Vector2i(2, 2), at))
	_block(world, ring)
	_almost_done(world)
	var queue: int = Rig.queue_of(1, INFANTRY)
	for _tick: int in 3:
		Rig.step(world)
		assert_array(_rifles(world)).is_empty()
		assert_array([world.queue_count[queue], world.queue_progress[queue]]).is_equal([1, 7500])
		assert_int(_scanned(world)).is_equal(12)
	assert_array([world.credits[1], world.stat_built[1], world.spawn_refused]).is_equal(
		[1900, 0, 0]
	)
	_block(world, [Vector2i(7, 1)], GRASS)
	Rig.step(world)
	assert_vector(_tile_of(world, _rifles(world)[0])).is_equal(Vector2i(7, 1))
	assert_array([world.queue_count[queue], world.queue_progress[queue]]).is_equal([0, 0])
	assert_array([world.stat_built[1], world.spawn_refused]).is_equal([1, 0])


## At `unit_cap` mobile rows the finished unit holds at 100 % before it looks for a tile
## (`EXIT_SCANNED` stays 0, nothing is refused); a death below the cap lets it out in the step of
## the death (REMOVE runs before PRODUCTION). Buildings and the other player's units do not count.
func test_the_unit_cap_holds_at_full_progress_and_a_death_releases_the_unit() -> void:
	var world: World = Rig.base()
	world.unit_cap = 2
	var rifle: int = Worlds.type_of(world, "rifle_squad")
	for index: int in 6:
		world.add_unit(2, rifle, 20500 + index * 600, 14500)
	var mine: PackedInt32Array = PackedInt32Array()
	for index: int in 2:
		mine.append(world.add_unit(1, rifle, 2500 + index * 600, 14500))
	_almost_done(world)
	var queue: int = Rig.queue_of(1, INFANTRY)
	for _tick: int in 3:
		Rig.step(world)
		assert_int(_rifles(world).size()).is_equal(2)
		assert_array([world.queue_count[queue], world.queue_progress[queue]]).is_equal([1, 7500])
		assert_array([_scanned(world), world.spawn_refused]).is_equal([0, 0])
	world.hp[world.index_of(mine[0])] = 0
	Rig.step(world)
	assert_int(_rifles(world).size()).is_equal(2)
	assert_vector(_tile_of(world, _rifles(world)[1])).is_equal(Vector2i(9, 3))
	assert_array([world.queue_count[queue], world.stat_built[1], _scanned(world)]).is_equal(
		[0, 1, 1]
	)


## The cap counts mobile rows of the player, harvesters among them, and no building: one below the
## cap a unit is let out, and the next one then holds.
func test_the_cap_counts_the_players_mobile_rows_only() -> void:
	var world: World = Rig.base()
	world.unit_cap = 3
	var rifle: int = Worlds.type_of(world, "rifle_squad")
	world.add_unit(1, rifle, 2500, 14500)
	world.add_unit(1, Worlds.type_of(world, "harvester"), 3500, 14500)
	# The four buildings of player 1 are not counted.
	assert_int(ProductionSpawn.mobile_rows(world, 1)).is_equal(2)
	assert_int(ProductionSpawn.mobile_rows(world, 2)).is_equal(0)
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad"), Rig.queue(world, 1, "rifle_squad", 1)])
	Rig.run(world, 74)
	assert_int(ProductionSpawn.mobile_rows(world, 1)).is_equal(3)
	var queue: int = Rig.queue_of(1, INFANTRY)
	Rig.run(world, 100)
	assert_array([world.queue_count[queue], world.queue_progress[queue]]).is_equal([1, 7500])
	assert_int(world.spawn_refused).is_equal(0)


## A full row table (`max_rows`) holds a finished unit the same way, and `add_unit` is never asked,
## so `spawn_refused` stays 0; room (here a raised limit) lets it out.
func test_a_full_row_table_holds_the_unit_without_a_refusal() -> void:
	var world: World = Rig.base()
	_almost_done(world)
	world.max_rows = world.unit_count()
	var queue: int = Rig.queue_of(1, INFANTRY)
	for _tick: int in 3:
		Rig.step(world)
		assert_array([world.queue_count[queue], world.queue_progress[queue]]).is_equal([1, 7500])
		assert_array([world.unit_count(), world.spawn_refused, _scanned(world)]).is_equal([5, 0, 0])
	world.max_rows += 1
	Rig.step(world)
	assert_array([world.unit_count(), world.queue_count[queue], world.spawn_refused]).is_equal(
		[6, 0, 0]
	)
