extends GdUnitTestSuite
## The footprint rule of the last-seen records (plan row P77b, ADR 0017 section 5, P115c's review):
## a building is seen when ANY cell of its footprint is visible to the player, as the view draws it
## (`BuildingLayer.is_seen`), and not only its centre tile. So a building seen at a corner is
## remembered, a record is forgotten when a corner of its spot is seen empty, and a building that
## leaves the rows while a cell of its footprint is visible takes its record with it, whatever the
## player sees at its next fog turn. The base rules (turns, order, cap) are in test_last_seen.gd,
## the same story through Sim.step in test_last_seen_play.gd. Each case names what the player sees
## through `memory_worlds.gd`: `show` writes a cell's visible count, `turn` runs the MEMORY phase on
## the player's turn, `destroy` removes the row as the REMOVE phase does.

const Memory: GDScript = preload("res://tests/sim/support/memory_worlds.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
## The Headquarters of player 2: 3 x 3 tiles from (16, 6), so tiles 16-18 by 6-8, centre (17, 7).
const HQ_COL: int = 16
const HQ_LINE: int = 6
const HQ_SIDE: int = 3


## The cell of tile (`col`, `line`).
func _tile(col: int, line: int) -> int:
	return line * Memory.COLS + col


## A World where player 2 has a Headquarters and player 1 nothing, and its id.
func _world(ghost_cap: int = -1) -> World:
	var world: World = Memory.world(ghost_cap)
	Memory.build(world, 2, "headquarters", HQ_COL, HQ_LINE)
	return world


## Player 1 sees nothing but the tile (`col`, `line`), and its turn runs.
func _see_only(world: World, col: int, line: int) -> void:
	world.fog.visible.fill(0)
	Memory.show(world, 1, _tile(col, line))
	Memory.turn(world, 1, world.tick + 1)


func test_a_building_seen_at_any_one_cell_of_its_footprint_is_remembered() -> void:
	var centre: int = Memory.cell_of(HQ_COL, HQ_LINE, HQ_SIDE, HQ_SIDE)
	for line: int in range(HQ_LINE, HQ_LINE + HQ_SIDE):
		for col: int in range(HQ_COL, HQ_COL + HQ_SIDE):
			var world: World = _world()
			var id: int = world.unit_id[0]
			_see_only(world, col, line)
			# The record is the building's own, on its centre tile, whichever cell was seen.
			(
				assert_array(Memory.records(world, 1))
				. override_failure_message("seen at (%d, %d)" % [col, line])
				. is_equal([[id, Worlds.type_of(world, "headquarters"), 2, centre]])
			)


func test_a_building_seen_only_beside_its_footprint_is_not_remembered() -> void:
	# The ring of tiles around the 3 x 3: its corners and its sides, none of them in the footprint.
	for line: int in range(HQ_LINE - 1, HQ_LINE + HQ_SIDE + 1):
		for col: int in range(HQ_COL - 1, HQ_COL + HQ_SIDE + 1):
			var inside: bool = (
				col >= HQ_COL
				and col < HQ_COL + HQ_SIDE
				and line >= HQ_LINE
				and line < HQ_LINE + HQ_SIDE
			)
			if inside:
				continue
			var world: World = _world()
			_see_only(world, col, line)
			(
				assert_array(world.ghost_count)
				. override_failure_message("seen at (%d, %d)" % [col, line])
				. is_equal([0, 0, 0])
			)


func test_a_two_by_two_building_is_seen_at_each_of_its_four_cells_and_no_other() -> void:
	for col: int in range(19, 23):
		for line: int in range(0, 4):
			var world: World = Memory.world()
			Memory.build(world, 2, "power_plant", 20, 1)  # Tiles 20-21 by 1-2, centre tile (21, 2).
			_see_only(world, col, line)
			var inside: bool = col >= 20 and col <= 21 and line >= 1 and line <= 2
			(
				assert_int(world.ghost_count[1])
				. override_failure_message("seen at (%d, %d)" % [col, line])
				. is_equal(1 if inside else 0)
			)


func test_a_record_whose_spot_is_seen_only_at_a_corner_is_dropped_when_the_building_is_gone(
) -> void:
	var world: World = _world()
	var id: int = world.unit_id[0]
	Memory.show(world, 1, Memory.cell_of(HQ_COL, HQ_LINE, HQ_SIDE, HQ_SIDE))
	Memory.turn(world, 1)
	assert_array(Memory.ids(world, 1)).is_equal([id])
	world.fog.visible.fill(0)
	Memory.destroy(world, id)  # Out of sight: the record stays, however many turns pass.
	Memory.turn(world, 1, world.tick + 1)
	Memory.turn(world, 1, world.tick + 1)
	assert_array(Memory.ids(world, 1)).is_equal([id])
	# The player looks at the spot's far corner and sees it empty: the record goes ...
	_see_only(world, HQ_COL + HQ_SIDE - 1, HQ_LINE + HQ_SIDE - 1)
	assert_array(world.ghost_count).is_equal([0, 0, 0])
	var first: int = world.ghost_cap
	assert_array([world.ghost_id[first], world.ghost_type[first]]).is_equal([0, 0])
	assert_array([world.ghost_owner[first], world.ghost_cell[first]]).is_equal([0, 0])
	# ... and it stays gone when the player looks away, or looks at another corner.
	world.fog.visible.fill(0)
	Memory.turn(world, 1, world.tick + 1)
	assert_array(world.ghost_count).is_equal([0, 0, 0])
	_see_only(world, HQ_COL, HQ_LINE)
	assert_array(world.ghost_count).is_equal([0, 0, 0])


func test_a_record_stays_while_only_the_ground_beside_its_spot_is_seen_empty() -> void:
	var world: World = _world()
	var id: int = world.unit_id[0]
	Memory.show(world, 1, Memory.cell_of(HQ_COL, HQ_LINE, HQ_SIDE, HQ_SIDE))
	Memory.turn(world, 1)
	world.fog.visible.fill(0)
	Memory.destroy(world, id)
	_see_only(world, HQ_COL - 1, HQ_LINE - 1)  # The tile diagonally outside the north-west corner.
	assert_array(Memory.ids(world, 1)).is_equal([id])
	_see_only(world, HQ_COL + HQ_SIDE, HQ_LINE + 1)  # The tile east of the footprint.
	assert_array(Memory.ids(world, 1)).is_equal([id])


func test_a_building_that_stands_keeps_its_record_whatever_cell_is_seen() -> void:
	var world: World = _world()
	var id: int = world.unit_id[0]
	_see_only(world, HQ_COL, HQ_LINE + HQ_SIDE - 1)
	var record: Array[Array] = Memory.records(world, 1)
	assert_array(Memory.ids(world, 1)).is_equal([id])
	for col: int in range(HQ_COL - 1, HQ_COL + HQ_SIDE + 1):
		_see_only(world, col, HQ_LINE)
		assert_array(Memory.records(world, 1)).is_equal(record)


func test_a_building_destroyed_in_sight_leaves_no_record_whatever_the_sight_at_the_next_turn(
) -> void:
	# The cell seen when it falls: the centre, a corner, an edge cell. The sight at the next turn:
	# the same, another corner, the ground beside it, nothing. None of the twelve leaves a record.
	var falls: Array[Vector2i] = [Vector2i(17, 7), Vector2i(16, 6), Vector2i(18, 7)]
	var then: Array[Vector2i] = [
		Vector2i(17, 7), Vector2i(18, 8), Vector2i(15, 5), Vector2i(-1, -1)
	]
	for fall: Vector2i in falls:
		for after: Vector2i in then:
			var world: World = _world()
			var id: int = world.unit_id[0]
			_see_only(world, fall.x, fall.y)
			assert_array(Memory.ids(world, 1)).is_equal([id])
			Memory.destroy(world, id)  # The sight is the one the turn wrote: the player watched it.
			var label: String = "fell at %s, then %s" % [fall, after]
			assert_array(world.ghost_count).override_failure_message(label).is_equal([0, 0, 0])
			world.fog.visible.fill(0)
			if after.x >= 0:
				Memory.show(world, 1, _tile(after.x, after.y))
			for _turn: int in 3:
				Memory.turn(world, 1, world.tick + 1)
				assert_array(world.ghost_count).override_failure_message(label).is_equal([0, 0, 0])


func test_a_player_that_did_not_see_the_building_fall_keeps_its_record() -> void:
	# Player 1 sees player 2's Headquarters, and player 2 sees player 1's (3 x 3 from (2, 2)).
	var world: World = _world()
	var mine: int = Memory.build(world, 1, "headquarters", 2, 2)
	var theirs: int = world.unit_id[0]
	var cell_theirs: int = Memory.cell_of(HQ_COL, HQ_LINE, HQ_SIDE, HQ_SIDE)
	var cell_mine: int = Memory.cell_of(2, 2, 3, 3)
	Memory.show(world, 1, cell_theirs)
	Memory.show(world, 2, cell_mine)
	Memory.turn(world, 1)
	Memory.turn(world, 2, world.tick + 1)
	assert_array(world.ghost_count).is_equal([0, 1, 1])
	# Player 2 looks away. Player 1's Headquarters falls in the sight of nobody but player 1 itself,
	# which keeps no record of its own building: player 2's record stays, and so does player 1's.
	world.fog.visible.fill(0)
	Memory.show(world, 1, cell_theirs)
	Memory.destroy(world, mine)
	assert_array(Memory.ids(world, 2)).is_equal([mine])
	assert_array(Memory.ids(world, 1)).is_equal([theirs])
	# Player 2's Headquarters falls in player 1's sight: its record goes, player 2's stays.
	Memory.destroy(world, theirs)
	assert_array(world.ghost_count).is_equal([0, 0, 1])


func test_the_death_of_a_unit_in_sight_changes_no_record() -> void:
	var world: World = _world()
	var squad: int = world.add_unit(2, Worlds.type_of(world, "rifle_squad"), 17500, 7500)
	Memory.show(world, 1, Memory.cell_of(HQ_COL, HQ_LINE, HQ_SIDE, HQ_SIDE))
	Memory.turn(world, 1)
	var record: Array[Array] = Memory.records(world, 1)
	world.stats.fill(0)
	Memory.destroy(world, squad)
	assert_array(Memory.records(world, 1)).is_equal(record)
	assert_int(world.stats[World.Stat.MEMORY_CHECKS]).is_equal(0)


func test_the_block_closes_up_in_order_when_a_record_goes_as_its_building_falls() -> void:
	var world: World = Memory.world()
	var ids: Array[int] = []
	for col: int in [4, 8, 12]:
		ids.append(Memory.build(world, 2, "barracks", col, 4))
		Memory.show(world, 1, Memory.cell_of(col, 4, 2, 2))
	Memory.turn(world, 1)
	assert_array(Memory.ids(world, 1)).is_equal(ids)
	var barracks: int = Worlds.type_of(world, "barracks")
	var last: int = world.ghost_cap + 2
	Memory.destroy(world, ids[0])
	assert_array(Memory.records(world, 1)).is_equal(
		[
			[ids[1], barracks, 2, Memory.cell_of(8, 4, 2, 2)],
			[ids[2], barracks, 2, Memory.cell_of(12, 4, 2, 2)]
		]
	)
	assert_array([world.ghost_id[last], world.ghost_type[last]]).is_equal([0, 0])
	assert_array([world.ghost_owner[last], world.ghost_cell[last]]).is_equal([0, 0])
	Memory.destroy(world, ids[2])
	assert_array(Memory.ids(world, 1)).is_equal([ids[1]])


func test_a_full_block_holds_ghost_cap_with_buildings_seen_at_corners() -> void:
	var world: World = Memory.world(2)
	var ids: Array[int] = []
	for col: int in [4, 8, 12]:
		ids.append(Memory.build(world, 2, "power_plant", col, 4))
		Memory.show(world, 1, _tile(col, 4))  # The north-west corner of each, not its centre.
	Memory.turn(world, 1)
	assert_array(Memory.ids(world, 1)).is_equal([ids[0], ids[1]])
	Memory.turn(world, 1, world.tick + 1)
	assert_array(world.ghost_count).is_equal([0, 2, 0])
	assert_int(world.ghost_id.size()).is_equal(world.ghost_cap * 3)
	# The block of player 2 and the neutral one hold nothing.
	for entry: int in [0, 1, 4, 5]:
		assert_array([world.ghost_id[entry], world.ghost_cell[entry]]).is_equal([0, 0])
	# A record that goes as its building falls frees the place for the one that was left out.
	Memory.destroy(world, ids[0])
	assert_array(Memory.ids(world, 1)).is_equal([ids[1]])
	Memory.turn(world, 1, world.tick + 1)
	assert_array(Memory.ids(world, 1)).is_equal([ids[1], ids[2]])
	assert_int(world.ghost_count[1]).is_less_equal(world.ghost_cap)


func test_a_fall_counts_the_records_it_looked_at_in_memory_checks() -> void:
	var world: World = Memory.world()
	var ids: Array[int] = []
	for col: int in [4, 8, 12]:
		ids.append(Memory.build(world, 2, "barracks", col, 4))
		Memory.show(world, 1, Memory.cell_of(col, 4, 2, 2))
	Memory.turn(world, 1)
	world.stats.fill(0)
	Memory.destroy(world, ids[1])  # The second of three records: two looked at, player 2 skipped.
	assert_int(world.stats[World.Stat.MEMORY_CHECKS]).is_equal(2)
	world.stats.fill(0)
	Memory.show(world, 1, Memory.cell_of(12, 4, 2, 2), false)
	Memory.destroy(world, ids[0])  # Its record is the first of two and its spot is seen: one.
	assert_int(world.stats[World.Stat.MEMORY_CHECKS]).is_equal(1)
	world.stats.fill(0)
	Memory.destroy(world, ids[2])  # The last of one, out of sight: one looked at, and it stays.
	assert_int(world.stats[World.Stat.MEMORY_CHECKS]).is_equal(1)
	assert_array(Memory.ids(world, 1)).is_equal([ids[2]])


func test_a_footprint_at_the_edge_of_the_map_does_not_wrap_to_the_line_above() -> void:
	# A record whose footprint hangs over the west edge (its centre on column 0, columns -1 to 1,
	# lines 4 to 6): column -1 of line 5 would index the last tile of line 4, which is not part of
	# the spot.
	var world: World = Memory.world()
	var type: int = Worlds.type_of(world, "headquarters")
	var first: int = world.ghost_cap
	world.ghost_id[first] = 77
	world.ghost_type[first] = type
	world.ghost_owner[first] = 2
	world.ghost_cell[first] = _tile(0, 5)
	world.ghost_count[1] = 1
	_see_only(world, Memory.COLS - 1, 4)  # The tile column -1 of line 5 would wrap to.
	assert_array(Memory.ids(world, 1)).is_equal([77])
	_see_only(world, 1, 6)  # A tile of the footprint (columns 0-1, lines 4-6): seen empty.
	assert_array(world.ghost_count).is_equal([0, 0, 0])
