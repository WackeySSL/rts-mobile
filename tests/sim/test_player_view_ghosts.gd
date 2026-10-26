extends GdUnitTestSuite
## PlayerView's last-seen records (plan row P77, ADR 0020 section 1, ADR 0017 section 3): the
## `ghost_*` fields are the player's own block of the World's ghost arrays, copied; `ghost_of` finds
## a record by building id and `ghost_pos` gives the building's position from the record. The rows,
## the state and the type tables of the view are in test_player_view_rows.gd and
## test_player_view_state.gd; how the records come and go is in test_last_seen.gd.

const Memory: GDScript = preload("res://tests/sim/support/memory_worlds.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const MISSING: int = PlayerView.MISSING
## The footprints of the position check: every width and height from 1 to this, one building each.
const MOST: int = 4
## The distance in tiles between the origins of those buildings on their map.
const PITCH: int = 8


## Player 1 remembers player 2's Headquarters (16, 6) and player 2 remembers player 1's (2, 2), and
## neither sees the other's now.
func _remembering_world() -> World:
	var world: World = Memory.world()
	Memory.build(world, 1, "headquarters", 2, 2)
	Memory.build(world, 2, "headquarters", 16, 6)
	Memory.show(world, 1, Memory.cell_of(16, 6, 3, 3))
	Memory.show(world, 2, Memory.cell_of(2, 2, 3, 3))
	Memory.turn(world, 1)
	Memory.turn(world, 2, world.tick + 1)
	Memory.show(world, 1, Memory.cell_of(16, 6, 3, 3), false)
	Memory.show(world, 2, Memory.cell_of(2, 2, 3, 3), false)
	return world


## A World of unarmed buildings of every size up to MOST x MOST, one each, owned by player 2 and in
## a grid on the map, every cell visible to player 1 and all of them remembered by it. Returns the
## World; the type of the w x h block is index `(h - 1) * MOST + w - 1`.
func _blocks_world() -> World:
	var units: Array[UnitDef] = []
	for height: int in range(1, MOST + 1):
		for width: int in range(1, MOST + 1):
			units.append(Worlds.block("block_%dx%d" % [width, height], width, height))
	var world: World = Rig.world_of(units, MOST * PITCH, MOST * PITCH, false)
	world.prepare()
	for type: int in units.size():
		world.add_building(2, type, type % MOST * PITCH, type / MOST * PITCH)
	world.fog.visible.fill(1)
	Memory.turn(world, 1)
	return world


func test_the_view_holds_the_players_block_of_every_ghost_array() -> void:
	var world: World = _remembering_world()
	assert_array(World.GHOST_ARRAYS).is_equal(
		[&"ghost_id", &"ghost_type", &"ghost_owner", &"ghost_cell", &"ghost_count"]
	)
	for player: int in [1, 2]:
		var view: PlayerView = PlayerView.of(world, player)
		var first: int = player * world.ghost_cap
		var count: int = world.ghost_count[player]
		assert_int(count).is_equal(1)
		for array_name: StringName in World.GHOST_ARRAYS:
			var column: PackedInt32Array = world.get(array_name)
			var held: Variant = view.get(array_name)
			if array_name == &"ghost_count":
				assert_int(held as int).is_equal(count)
			else:
				var block: PackedInt32Array = column.slice(first, first + count)
				assert_array(held).override_failure_message(array_name).is_equal(block)
				assert_int(block.size()).is_equal(1)
		# One record each, of the other player's Headquarters.
		var other: int = 3 - player
		assert_int(view.ghost_owner[0]).is_equal(other)
		assert_int(view.ghost_type[0]).is_equal(Worlds.type_of(world, "headquarters"))


func test_a_record_is_the_players_memory_and_not_a_row_it_sees() -> void:
	var world: World = _remembering_world()
	var theirs: int = world.unit_id[1]
	var view: PlayerView = PlayerView.of(world, 1)
	assert_int(view.row_of(theirs)).is_equal(MISSING)
	assert_int(view.seen_rows.size()).is_equal(0)
	assert_int(view.ghost_of(theirs)).is_equal(0)
	assert_int(view.ghost_id[0]).is_equal(theirs)
	assert_int(view.ghost_cell[0]).is_equal(Memory.cell_of(16, 6, 3, 3))
	# A building that is seen now is a row and a record both.
	Memory.show(world, 1, Memory.cell_of(16, 6, 3, 3))
	view = PlayerView.of(world, 1)
	assert_int(view.row_of(theirs)).is_equal(world.index_of(theirs))
	assert_int(view.ghost_of(theirs)).is_equal(0)
	# A player never remembers its own buildings: player 1 has no record of its Headquarters (id 1)
	# and player 2 none of its own (`theirs`).
	assert_int(view.ghost_of(world.unit_id[0])).is_equal(MISSING)
	assert_int(PlayerView.of(world, 2).ghost_of(theirs)).is_equal(MISSING)


func test_the_fields_are_copies_that_follow_no_later_write() -> void:
	var world: World = _remembering_world()
	var state: int = world.state_hash()
	var view: PlayerView = PlayerView.of(world, 1)
	var id: int = view.ghost_id[0]
	view.ghost_id[0] += 1000
	view.ghost_type[0] += 1000
	view.ghost_owner[0] += 1000
	view.ghost_cell[0] += 1000
	view.ghost_count += 1000
	assert_int(world.state_hash()).is_equal(state)
	assert_int(PlayerView.of(world, 1).ghost_id[0]).is_equal(id)
	# A record the sim writes or drops afterwards does not show in a view made before.
	var kept: PlayerView = PlayerView.of(world, 1)
	Memory.show(world, 1, Memory.cell_of(16, 6, 3, 3))
	Memory.destroy(world, id)
	Memory.turn(world, 1, world.tick + 1)
	assert_int(world.ghost_count[1]).is_equal(0)
	assert_int(kept.ghost_count).is_equal(1)
	assert_int(kept.ghost_id[0]).is_equal(id)
	assert_int(PlayerView.of(world, 1).ghost_count).is_equal(0)


func test_ghost_pos_is_the_buildings_centre_for_every_footprint_to_4x4() -> void:
	var world: World = _blocks_world()
	var view: PlayerView = PlayerView.of(world, 1)
	assert_int(view.ghost_count).is_equal(MOST * MOST)
	for type: int in MOST * MOST:
		var row: int = type  # One building per type, added in type order.
		var width: int = world.type_foot_w[type]
		var height: int = world.type_foot_h[type]
		assert_array([width, height]).is_equal([type % MOST + 1, type / MOST + 1])
		var record: int = view.ghost_of(world.unit_id[row])
		assert_int(record).is_not_equal(MISSING)
		(
			assert_vector(view.ghost_pos(record))
			. override_failure_message("%d x %d" % [width, height])
			. is_equal(Vector2i(world.pos_x[row], world.pos_y[row]))
		)


func test_what_is_not_remembered_answers_missing() -> void:
	var world: World = _remembering_world()
	var view: PlayerView = PlayerView.of(world, 1)
	# Id 1 is player 1's own Headquarters, and the last id is 2 past 32 bits: a record's id by its low
	# 32 bits, which is not the building's.
	for id: int in [0, -1, 1, 999, 1 << 40, (1 << 32) + 2]:
		assert_int(view.ghost_of(id)).is_equal(MISSING)
	for record: int in [-1, 1, 2, 40, 1 << 40]:
		assert_vector(view.ghost_pos(record)).is_equal(Vector2i(MISSING, MISSING))
	# A record of a type with no footprint has no position (hand-written: the sim writes none).
	var first: int = world.ghost_cap
	world.ghost_type[first] = Worlds.type_of(world, "rifle_squad")
	assert_vector(PlayerView.of(world, 1).ghost_pos(0)).is_equal(Vector2i(MISSING, MISSING))
	world.ghost_type[first] = world.type_ids.size() + 5  # And one of a type past the table.
	assert_vector(PlayerView.of(world, 1).ghost_pos(0)).is_equal(Vector2i(MISSING, MISSING))


func test_a_player_past_the_worlds_arrays_has_no_records_and_no_error() -> void:
	var world: World = _remembering_world()
	for player: int in [0, 3, 99, -1]:
		var view: PlayerView = PlayerView.of(world, player)
		assert_int(view.ghost_count).is_equal(0)
		assert_array([view.ghost_id.size(), view.ghost_type.size()]).is_equal([0, 0])
		assert_array([view.ghost_owner.size(), view.ghost_cell.size()]).is_equal([0, 0])
		assert_int(view.ghost_of(2)).is_equal(MISSING)
		assert_vector(view.ghost_pos(0)).is_equal(Vector2i(MISSING, MISSING))


func test_a_count_the_block_cannot_hold_is_cut_to_the_block() -> void:
	var world: World = _remembering_world()
	world.ghost_count[1] = world.ghost_cap + 50
	var view: PlayerView = PlayerView.of(world, 1)
	assert_int(view.ghost_count).is_equal(world.ghost_cap)
	assert_int(view.ghost_cell.size()).is_equal(world.ghost_cap)
	world.ghost_count[2] = -4
	assert_int(PlayerView.of(world, 2).ghost_count).is_equal(0)
