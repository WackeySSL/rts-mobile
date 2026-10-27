extends GdUnitTestSuite
## The rules of the last-seen building records (plan row P77, ADR 0017 sections 3 and 5): which
## buildings a player remembers, when a record is added and when it is forgotten, whose turn it is,
## what a full block does, and the order the records keep. Each case names what the player sees on
## which fog turn through `memory_worlds.gd` (`show` writes a cell's visible count, `turn` runs the
## MEMORY phase on the player's turn); the same rules through `Sim.step` and the real fog, under
## both implementations of FOG, are in test_last_seen_play.gd, and PlayerView's getters in
## test_player_view_ghosts.gd. Expected types and cells come from the World's tables and rows.

const Memory: GDScript = preload("res://tests/sim/support/memory_worlds.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")


## The type index of the roster entry `id`.
func _type(world: World, id: String) -> int:
	return Worlds.type_of(world, id)


## The cell of tile (`col`, `line`): the north-west corner of a building whose top-left tile it is.
func _tile(col: int, line: int) -> int:
	return line * Memory.COLS + col


## A World where player 1 has a Headquarters at (2, 2) and player 2 one at (16, 6), and the cell of
## player 2's, which the cases light for player 1.
func _bases() -> World:
	var world: World = Memory.world()
	Memory.build(world, 1, "headquarters", 2, 2)
	Memory.build(world, 2, "headquarters", 16, 6)
	return world


func test_a_seen_enemy_building_is_remembered_on_its_players_turn() -> void:
	var world: World = _bases()
	var theirs: int = world.unit_id[1]
	var cell: int = Memory.cell_of(16, 6, 3, 3)
	assert_int(cell).is_equal(185)  # Tile (17, 7): the centre tile of a 3x3 from (16, 6), 24 wide.
	assert_int(Memory.cell_at(world, theirs)).is_equal(cell)
	Memory.show(world, 1, cell)
	Memory.turn(world, 1)
	assert_array(Memory.records(world, 1)).is_equal(
		[[theirs, _type(world, "headquarters"), 2, cell]]
	)
	assert_array(world.ghost_count).is_equal([0, 1, 0])


func test_only_the_players_whose_fog_turn_it_is_update() -> void:
	# The table is the suite's own period (`Memory.FOG_PERIOD`, 3), not the shipped rule's.
	assert_int(Memory.world().fog_period_ticks).is_equal(Memory.FOG_PERIOD)
	assert_int(Memory.FOG_PERIOD).is_equal(3)
	assert_int(Memory.idle_tick(Memory.world())).is_equal(2)
	# Both players see the other's Headquarters. Player 1 turns on ticks 0, 3 and 6, player 2 on 1,
	# 4 and 7, and nobody on 2 and 5 (FogUpdate's rule, which MEMORY follows).
	var expected: Dictionary[int, Array] = {
		0: [0, 1, 0], 1: [0, 0, 1], 2: [0, 0, 0], 3: [0, 1, 0], 4: [0, 0, 1], 5: [0, 0, 0]
	}
	for tick: int in expected:
		var world: World = _bases()
		Memory.show(world, 1, Memory.cell_of(16, 6, 3, 3))
		Memory.show(world, 2, Memory.cell_of(2, 2, 3, 3))
		world.tick = tick
		LastSeen.run(world)
		assert_array(world.ghost_count).override_failure_message("tick %d" % tick).is_equal(
			expected[tick]
		)


func test_own_neutral_and_mobile_rows_are_never_remembered() -> void:
	var world: World = _bases()
	Memory.build(world, 0, "power_plant", 10, 1)
	world.add_unit(2, _type(world, "rifle_squad"), 12500, 5500)
	world.add_unit(0, _type(world, "rifle_squad"), 13500, 5500)
	world.fog.visible.fill(1)  # Player 1 sees every cell, its own Headquarters and the rest.
	Memory.turn(world, 1)
	assert_array(world.ghost_count).is_equal([0, 1, 0])
	assert_array(Memory.ids(world, 1)).is_equal([world.unit_id[1]])


func test_a_building_out_of_sight_is_not_remembered() -> void:
	var world: World = _bases()
	Memory.show(world, 1, Memory.cell_of(16, 6, 3, 3) - 2)  # The tile west of the footprint.
	Memory.turn(world, 1)
	assert_array(world.ghost_count).is_equal([0, 0, 0])
	Memory.show(world, 1, Memory.cell_of(16, 6, 3, 3))
	Memory.turn(world, 1, world.tick + 1)
	assert_array(world.ghost_count).is_equal([0, 1, 0])


func test_a_building_is_recorded_once_and_new_records_append_in_the_order_seen() -> void:
	var world: World = _bases()
	var plant: int = Memory.build(world, 2, "power_plant", 20, 1)
	var barracks: int = Memory.build(world, 2, "barracks", 20, 9)
	var hq: int = world.unit_id[1]
	Memory.show(world, 1, Memory.cell_of(20, 9, 2, 2))
	Memory.turn(world, 1)
	assert_array(Memory.ids(world, 1)).is_equal([barracks])
	Memory.show(world, 1, Memory.cell_of(16, 6, 3, 3))
	Memory.show(world, 1, Memory.cell_of(20, 1, 2, 2))
	Memory.turn(world, 1, world.tick + 1)
	Memory.turn(world, 1, world.tick + 1)
	# The records keep their places, and each building seen on one turn follows in row order.
	assert_array(Memory.ids(world, 1)).is_equal([barracks, hq, plant])


func test_a_building_destroyed_out_of_sight_stays_remembered_until_its_cell_is_seen() -> void:
	var world: World = _bases()
	var theirs: int = world.unit_id[1]
	var cell: int = Memory.cell_of(16, 6, 3, 3)
	Memory.show(world, 1, cell)
	Memory.turn(world, 1)
	var record: Array[Array] = Memory.records(world, 1)
	Memory.show(world, 1, cell, false)
	Memory.destroy(world, theirs)
	assert_int(world.index_of(theirs)).is_equal(-1)
	Memory.turn(world, 1, world.tick + 1)
	Memory.turn(world, 1, world.tick + 1)
	assert_array(Memory.records(world, 1)).is_equal(record)
	# Seen again, but not on player 1's turn: the memory moves with the player's own sight only.
	Memory.show(world, 1, cell)
	world.tick = Memory.idle_tick(world)
	LastSeen.run(world)
	assert_array(Memory.records(world, 1)).is_equal(record)
	Memory.turn(world, 1, world.tick + 1)
	assert_array(world.ghost_count).is_equal([0, 0, 0])
	var first: int = world.ghost_cap
	assert_array([world.ghost_id[first], world.ghost_type[first]]).is_equal([0, 0])
	assert_array([world.ghost_owner[first], world.ghost_cell[first]]).is_equal([0, 0])


func test_a_building_that_stands_keeps_its_record_seen_or_not() -> void:
	var world: World = _bases()
	var cell: int = Memory.cell_of(16, 6, 3, 3)
	Memory.show(world, 1, cell)
	Memory.turn(world, 1)
	var record: Array[Array] = Memory.records(world, 1)
	for seen: bool in [false, true, false, true]:
		Memory.show(world, 1, cell, seen)
		Memory.turn(world, 1, world.tick + 1)
		assert_array(Memory.records(world, 1)).is_equal(record)


func test_a_building_destroyed_in_sight_is_dropped_as_it_dies() -> void:
	var world: World = _bases()
	var cell: int = Memory.cell_of(16, 6, 3, 3)
	Memory.show(world, 1, cell)
	Memory.turn(world, 1)
	assert_array(world.ghost_count).is_equal([0, 1, 0])
	Memory.destroy(world, world.unit_id[1])  # The record goes with the row, before any turn.
	assert_array(world.ghost_count).is_equal([0, 0, 0])
	world.tick = Memory.idle_tick(world)
	LastSeen.run(world)
	Memory.turn(world, 1, world.tick + 1)
	assert_array(world.ghost_count).is_equal([0, 0, 0])


func test_a_full_block_holds_ghost_cap_and_never_writes_past_it() -> void:
	var world: World = Memory.world(2)
	var ids: Array[int] = []
	for col: int in [4, 8, 12]:
		ids.append(Memory.build(world, 2, "power_plant", col, 4))
		Memory.show(world, 1, Memory.cell_of(col, 4, 2, 2))
	Memory.turn(world, 1)
	assert_array(Memory.ids(world, 1)).is_equal([ids[0], ids[1]])
	Memory.turn(world, 1, world.tick + 1)
	assert_array(world.ghost_count).is_equal([0, 2, 0])
	# The blocks of the neutral player and of player 2 hold nothing.
	for entry: int in [0, 1, 4, 5]:
		assert_array([world.ghost_id[entry], world.ghost_cell[entry]]).is_equal([0, 0])
	# A record that goes frees its place for the building that was left out. The first building
	# falls out of sight, so its record stays; on the next turn a corner of its spot is seen empty
	# and the record goes before the building left out is looked at (the forget comes first).
	Memory.show(world, 1, Memory.cell_of(4, 4, 2, 2), false)
	Memory.destroy(world, ids[0])
	assert_array(Memory.ids(world, 1)).is_equal([ids[0], ids[1]])
	Memory.show(world, 1, _tile(4, 4))
	Memory.turn(world, 1, world.tick + 1)
	assert_array(Memory.ids(world, 1)).is_equal([ids[1], ids[2]])
	assert_int(world.ghost_id.size()).is_equal(world.ghost_cap * 3)


func test_records_keep_their_places_when_one_goes() -> void:
	var world: World = Memory.world()
	var ids: Array[int] = []
	for col: int in [4, 8, 12, 16]:
		ids.append(Memory.build(world, 2, "barracks", col, 4))
		Memory.show(world, 1, Memory.cell_of(col, 4, 2, 2))
	Memory.turn(world, 1)
	assert_array(Memory.ids(world, 1)).is_equal(ids)
	# The second building falls out of sight (its spot is dark): its record stays until a corner of
	# the spot is seen empty on the player's turn, which closes the block up in order (the in-sight
	# fall is pinned in test_last_seen_footprint.gd).
	Memory.show(world, 1, Memory.cell_of(8, 4, 2, 2), false)
	Memory.destroy(world, ids[1])
	assert_array(Memory.ids(world, 1)).is_equal(ids)
	Memory.show(world, 1, _tile(8, 4))
	Memory.turn(world, 1, world.tick + 1)
	assert_array(Memory.ids(world, 1)).is_equal([ids[0], ids[2], ids[3]])
	var last: int = world.ghost_cap + 3  # The freed place after the three that are left.
	assert_array([world.ghost_id[last], world.ghost_type[last]]).is_equal([0, 0])
	assert_array([world.ghost_owner[last], world.ghost_cell[last]]).is_equal([0, 0])


func test_each_player_keeps_its_own_memory_in_its_own_block() -> void:
	var world: World = _bases()
	var mine: int = world.unit_id[0]
	var theirs: int = world.unit_id[1]
	Memory.show(world, 1, Memory.cell_of(16, 6, 3, 3))
	Memory.show(world, 2, Memory.cell_of(2, 2, 3, 3))
	Memory.turn(world, 1)
	Memory.turn(world, 2, world.tick + 1)
	var hq: int = _type(world, "headquarters")
	assert_array(Memory.records(world, 1)).is_equal([[theirs, hq, 2, Memory.cell_of(16, 6, 3, 3)]])
	assert_array(Memory.records(world, 2)).is_equal([[mine, hq, 1, Memory.cell_of(2, 2, 3, 3)]])
	Memory.destroy(world, mine)
	Memory.turn(world, 2, world.tick + 1)
	assert_array(world.ghost_count).is_equal([0, 1, 0])


func test_memory_checks_count_the_records_and_the_building_rows_looked_at() -> void:
	var world: World = _bases()
	Memory.build(world, 2, "power_plant", 20, 1)
	var rows: int = 3  # Both Headquarters and the plant: every building row is looked at.
	Memory.show(world, 1, Memory.cell_of(16, 6, 3, 3))
	Memory.show(world, 1, Memory.cell_of(20, 1, 2, 2))
	world.stats.fill(0)
	world.tick = Memory.idle_tick(world)  # Nobody's turn.
	LastSeen.run(world)
	assert_int(world.stats[World.Stat.MEMORY_CHECKS]).is_equal(0)
	Memory.turn(world, 1)
	assert_int(world.stats[World.Stat.MEMORY_CHECKS]).is_equal(0 + rows)
	assert_int(world.ghost_count[1]).is_equal(2)
	world.stats.fill(0)
	Memory.turn(world, 1, world.tick + 1)
	assert_int(world.stats[World.Stat.MEMORY_CHECKS]).is_equal(2 + rows)
	world.stats.fill(0)
	Memory.turn(world, 2, world.tick + 1)  # Player 2 has no record and looks at the same rows.
	assert_int(world.stats[World.Stat.MEMORY_CHECKS]).is_equal(0 + rows)


func test_a_world_that_cannot_keep_records_keeps_none_and_raises_no_error() -> void:
	LastSeen.run(World.new())  # Not prepared: no fog cells, no arrays.
	var world: World = Memory.world(0)  # Prepared, but a block of no records.
	Memory.build(world, 2, "headquarters", 16, 6)
	world.fog.visible.fill(1)
	world.stats.fill(0)
	Memory.turn(world, 1)
	assert_array(world.ghost_count).is_equal([0, 0, 0])
	assert_int(world.ghost_id.size()).is_equal(0)
	assert_int(world.stats[World.Stat.MEMORY_CHECKS]).is_equal(0)


func test_the_ghosts_section_hashes_the_live_records_only() -> void:
	var names: PackedStringArray = World.hash_section_names()
	var at: int = names.find("ghosts")
	var world: World = _bases()
	var start: PackedInt64Array = world.hash_parts()
	var cell: int = Memory.cell_of(16, 6, 3, 3)
	Memory.show(world, 1, cell)
	Memory.turn(world, 1)
	var live: PackedInt64Array = world.hash_parts()
	assert_int(live[at]).is_not_equal(start[at])
	# The record goes (its building dies in sight): the section is the start's again.
	var gone: Array = Memory.records(world, 1)[0]
	Memory.destroy(world, world.unit_id[1])
	Memory.turn(world, 1, world.tick + 1)
	assert_int(world.ghost_count[1]).is_equal(0)
	assert_int(world.hash_parts()[at]).is_equal(start[at])
	# Stale values in the freed place (the record that was there) are not state while the count
	# stays below them, so a hash that fed the whole arrays would differ from the start's here.
	var free: int = world.ghost_cap
	world.ghost_id[free] = gone[0]
	world.ghost_type[free] = gone[1]
	world.ghost_owner[free] = gone[2]
	world.ghost_cell[free] = gone[3]
	assert_int(world.ghost_id[free]).is_not_equal(0)
	assert_int(world.hash_parts()[at]).is_equal(start[at])
	# The same entry below the count is state: the count alone makes it count.
	world.ghost_count[1] = 1
	assert_int(world.hash_parts()[at]).is_equal(live[at])
