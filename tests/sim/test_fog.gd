extends GdUnitTestSuite
## The fog update (P46, ADR 0010 section 1, ADR 0007 section 4): the initial stamp, the cadence,
## re-stamping only on a tile change, the new disc before the old one, the dirty lists, a dying
## row, and the hash. Hand-built worlds on a 30 x 30 map with literal numbers; the expected
## cells come from a brute force over the whole map, never from FogGrid. Units stand idle (speed
## 0) and the tests move them by writing the position between steps.

const COLS: int = 30
const MAP: int = 30000
## Type indexes: 0 sees 6000 (113 cells), 1 sees 2000 (13 cells).
const SCOUT: int = 0
const POST: int = 1
const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
const FogProbe: GDScript = preload("res://tests/sim/support/fog_view_probe.gd")


func test_prepare_stamps_every_players_vision_with_the_mask_of_its_type() -> void:
	var world: World = _world()
	world.add_unit(1, SCOUT, _centre(10), _centre(10))
	world.add_unit(1, SCOUT, _centre(12), _centre(10))
	world.add_unit(2, POST, _centre(20), _centre(5))
	world.add_unit(0, SCOUT, _centre(3), _centre(3))
	world.prepare()
	assert_array(world.fog_cell).is_equal([310, 312, 170, -1])
	var overlap: PackedInt32Array = _counts([_disc(10, 10, 6000), _disc(12, 10, 6000)])
	assert_array(_block(world, 1)).is_equal(overlap)
	assert_int(overlap.count(2)).is_equal(89)
	assert_array(_block(world, 2)).is_equal(_counts([_disc(20, 5, 2000)]))
	assert_int(_block(world, 2).count(1)).is_equal(13)
	for player: int in [1, 2]:
		for cell: int in COLS * COLS:
			var seen: bool = _block(world, player)[cell] > 0
			assert_bool(world.fog.is_explored(player, cell)).is_equal(seen)
	assert_int(world.stats[World.Stat.FOG_CELLS]).is_equal(0)
	# One mask per type, in type order, and a last one of sight 0 for a type with no entry.
	assert_array(world.fog.mask_radius).is_equal([6, 2, 0])


func test_a_type_with_no_entry_sees_its_own_tile_and_a_world_without_a_map_has_no_fog() -> void:
	var lost: World = World.new()
	lost.map_w = MAP
	lost.map_h = MAP
	lost.add_unit(1, 4, _centre(7), _centre(9))
	lost.prepare()
	assert_array(_block(lost, 1)).is_equal(_counts([_disc(7, 9, 0)]))
	assert_int(lost.fog_cell[0]).is_equal(9 * COLS + 7)
	lost.pos_x[0] = _centre(8)
	FogUpdate.run(lost)
	assert_array(_block(lost, 1)).is_equal(_counts([_disc(8, 9, 0)]))
	assert_int(lost.stats[World.Stat.FOG_CELLS]).is_equal(2)
	var bare: World = World.new()
	bare.type_ids.append(&"scout")
	bare.add_unit(1, 0, 4500, 4500)
	for _t: int in 4:
		Sim.step(bare, [])
	assert_array([bare.fog.cells, bare.fog_cell[0], bare.stats[World.Stat.FOG_CELLS]]).is_equal(
		[0, -1, 0]
	)
	bare.hp[0] = 0
	Sim.step(bare, [])
	assert_int(bare.unit_count()).is_equal(0)


## Every tick both units step to a new tile, so every update has work: a unit is stamped at its new
## cell only on its player's ticks, and a tick of nobody's (2, 5, 8) stamps nothing.
func test_player_1_updates_on_ticks_0_3_6_and_player_2_on_1_4_7() -> void:
	var world: World = _world()
	world.add_unit(1, SCOUT, _centre(8), _centre(10))
	world.add_unit(2, SCOUT, _centre(8), _centre(20))
	world.prepare()
	var ticks: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
	var stamped: PackedInt32Array = PackedInt32Array()
	for tick: int in 9:
		world.pos_x[0] = _centre(9 + tick)
		world.pos_x[1] = _centre(9 + tick)
		Sim.step(world, [])
		if world.fog_cell[0] == 10 * COLS + 9 + tick:
			ticks[0].append(tick)
		if world.fog_cell[1] == 20 * COLS + 9 + tick:
			ticks[1].append(tick)
		stamped.append(world.stats[World.Stat.FOG_CELLS])
	assert_array(ticks[0]).is_equal([0, 3, 6])
	assert_array(ticks[1]).is_equal([1, 4, 7])
	assert_array(stamped).is_equal([226, 226, 0, 226, 226, 0, 226, 226, 0])


## With four players 1 and 4 share a tick (tick % 3 == (p - 1) % 3), and 2 and 3 have their own.
func test_with_four_players_players_1_and_4_share_their_ticks() -> void:
	var world: World = _world()
	for player: int in range(1, 5):
		world.add_unit(player, POST, _centre(2), _centre(player * 6))
	world.prepare()
	var ticks: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
	ticks.append_array([PackedInt32Array(), PackedInt32Array()])
	for tick: int in 6:
		for row: int in 4:
			world.pos_x[row] = _centre(3 + tick)
		Sim.step(world, [])
		for row: int in 4:
			if world.fog_cell[row] == (row + 1) * 6 * COLS + 3 + tick:
				ticks[row].append(tick)
	var expected: Array = [[0, 3], [1, 4], [2, 5], [0, 3]]
	for row: int in 4:
		assert_array(ticks[row]).override_failure_message("player %d" % (row + 1)).is_equal(
			expected[row]
		)
		# The mask is the type's, and the old discs left nothing behind: the disc stands where the
		# unit was at the player's last update.
		var last: int = expected[row][1]
		var disc: PackedInt32Array = _counts([_disc(3 + last, (row + 1) * 6, 2000)])
		assert_array(_block(world, row + 1)).override_failure_message("sight").is_equal(disc)


## Tick 0 is player 1's. Unit 1 moves inside its tile, unit 2 one tile, unit 3 not at all: only
## unit 2 re-stamps, and stats[FOG_CELLS] counts the cells of its two discs (113 each). The next
## update has no mover and stamps nothing; the version of the player does not grow either.
func test_only_units_that_changed_tile_restamp() -> void:
	var world: World = _world()
	for column: int in [10, 14, 18]:
		world.add_unit(1, SCOUT, _centre(column), _centre(15))
	world.prepare()
	var before: int = world.fog.version_of(1)
	world.pos_x[0] += 300
	world.pos_x[1] += 1000
	Sim.step(world, [])
	assert_array(world.fog_cell).is_equal([15 * COLS + 10, 15 * COLS + 15, 15 * COLS + 18])
	assert_int(world.stats[World.Stat.FOG_CELLS]).is_equal(226)
	assert_int(world.fog.version_of(1)).is_greater(before)
	var after: int = world.fog.version_of(1)
	for _t: int in 3:
		Sim.step(world, [])
		assert_int(world.stats[World.Stat.FOG_CELLS]).is_equal(0)
	assert_int(world.fog.version_of(1)).is_equal(after)


## The count is the cells each stamp walks, clipped to the map: a unit in the corner and one that
## steps off an edge, against a brute force of the discs.
func test_fog_cells_count_the_clipped_discs() -> void:
	var world: World = _world()
	world.add_unit(1, SCOUT, _centre(0), _centre(0))
	world.add_unit(1, SCOUT, _centre(29), _centre(14))
	world.prepare()
	world.pos_x[0] = _centre(1)
	world.pos_y[1] = _centre(15)
	Sim.step(world, [])
	var cells: int = _disc(1, 0, 6000).size() + _disc(0, 0, 6000).size()
	cells += _disc(29, 15, 6000).size() + _disc(29, 14, 6000).size()
	assert_int(world.stats[World.Stat.FOG_CELLS]).is_equal(cells)
	assert_bool(cells < 4 * 113).is_true()


## A lone scout of player 2 with sight 6000 steps one tile along a row (cell 465 to 466) in one
## world, and one tile on the diagonal (465 to 496) in another, on a 30 x 30 map. The new disc is
## stamped first, so only the cells that change are listed: 26 and 34, where unstamping first
## lists 126 and 130 (the other order, run on a FogGrid beside it). Counts and explored are the
## same in either order.
func test_a_restamp_stamps_the_new_disc_first_and_lists_only_the_flipped_cells() -> void:
	for step: Vector2i in [Vector2i(1, 0), Vector2i(1, 1)]:
		var world: World = _world()
		world.add_unit(2, SCOUT, _centre(15), _centre(15))
		Sim.step(world, [])
		world.pos_x[0] += step.x * 1000
		world.pos_y[0] += step.y * 1000
		Sim.step(world, [])
		var moved: int = (15 + step.y) * COLS + 15 + step.x
		assert_int(world.fog_cell[0]).is_equal(moved)
		var old_disc: PackedInt32Array = _disc(15, 15, 6000)
		var new_disc: PackedInt32Array = _disc(15 + step.x, 15 + step.y, 6000)
		var expected: PackedInt32Array = PackedInt32Array()
		for cell: int in COLS * COLS:
			if old_disc.has(cell) != new_disc.has(cell):
				expected.append(cell)
		var listed: PackedInt32Array = world.fog.dirty_cells(2)
		listed.sort()
		assert_int(listed.size()).is_equal(26 if step.y == 0 else 34)
		assert_array(listed).is_equal(expected)
		assert_bool(world.fog.dirty_overflowed(2)).is_false()
		var other: FogGrid = FogGrid.new()
		other.configure(COLS, COLS, 2)
		var reference: int = other.add_mask(6000)
		other.stamp(2, 465, reference, 1)
		other.begin_update(2)
		other.stamp(2, 465, reference, -1)
		other.stamp(2, moved, reference, 1)
		assert_int(other.dirty_cells(2).size()).is_equal(126 if step.y == 0 else 130)
		assert_array(_block(world, 2)).is_equal(other.visible.slice(900))
		assert_array(world.fog.explored.slice(900)).is_equal(other.explored.slice(900))


## Dying units' discs (a scout and a post, two masks) are unstamped by remove_dead in the tick of
## their death, whoever's turn it is (tick 1 is player 2's): their cells go dark and are listed,
## nothing else of player 1 changes, and the explored bytes stay.
func test_a_dying_units_vision_ends_that_tick_and_explored_stays() -> void:
	var world: World = _world()
	world.add_unit(1, SCOUT, _centre(10), _centre(10))
	world.add_unit(1, POST, _centre(25), _centre(25))
	world.add_unit(1, POST, _centre(5), _centre(25))
	world.add_unit(2, POST, _centre(20), _centre(5))
	Sim.step(world, [])
	var gone: PackedInt32Array = _disc(10, 10, 6000) + _disc(25, 25, 2000)
	for cell: int in gone:
		assert_bool(world.fog.is_visible(1, cell)).is_true()
	world.hp[0] = 0
	world.hp[1] = 0
	Sim.step(world, [])
	assert_int(world.tick).is_equal(2)
	assert_int(world.unit_count()).is_equal(2)
	assert_array(world.events.slice(0, 2)).is_equal([World.Event.DIED, 1])
	assert_array(world.events.slice(8, 10)).is_equal([World.Event.DIED, 2])
	assert_array(_block(world, 1)).is_equal(_counts([_disc(5, 25, 2000)]))
	for cell: int in gone:
		assert_bool(world.fog.is_visible(1, cell)).is_false()
		assert_bool(world.fog.is_explored(1, cell)).is_true()
	var listed: PackedInt32Array = world.fog.dirty_cells(1)
	listed.sort()
	gone.sort()
	assert_array(listed).is_equal(gone)
	assert_array(world.fog_cell).is_equal([25 * COLS + 5, 5 * COLS + 20])


## Player 1 dies on its own update tick (tick 0), after its list was emptied at the start of the
## tick: the cells the dead disc flips are still listed when the update has run (the view patches
## them), and the survivors' stamps do not remove them.
func test_the_cells_of_a_death_on_the_owners_update_tick_stay_listed() -> void:
	var world: World = _world()
	world.add_unit(1, SCOUT, _centre(10), _centre(10))
	world.add_unit(1, POST, _centre(25), _centre(25))
	world.prepare()
	world.hp[0] = 0
	world.pos_x[1] += 1000
	Sim.step(world, [])
	var listed: PackedInt32Array = world.fog.dirty_cells(1)
	listed.sort()
	var expected: PackedInt32Array = PackedInt32Array()
	for cell: int in _disc(10, 10, 6000) + _flips(25, 25, 26, 25, 2000):
		expected.append(cell)
	expected.sort()
	assert_array(listed).is_equal(expected)
	assert_int(listed.size()).is_equal(113 + 10)


## The fog update is the last phase: at the REMOVE mark the dead row is gone and its disc is dark
## while the mover (player 1's turn, tick 0) still stands in its old cell, and at the FOG mark it
## has moved. Before REMOVE both rows are stamped where they were.
func test_the_fog_update_follows_the_removal_in_the_tick() -> void:
	var world: World = _world()
	world.add_unit(1, SCOUT, _centre(10), _centre(10))
	world.add_unit(1, SCOUT, _centre(20), _centre(10))
	world.prepare()
	world.hp[0] = 0
	world.pos_x[1] += 1000
	var probe: SimProbe = FogProbe.new(world)
	Sim.step(world, [], probe)
	var fire: int = probe.phases.find(SimProbe.Phase.FIRE)
	var remove: int = probe.phases.find(SimProbe.Phase.REMOVE)
	assert_array(probe.phases.slice(fire)).is_equal(
		[SimProbe.Phase.FIRE, SimProbe.Phase.REMOVE, SimProbe.Phase.FOG]
	)
	assert_array(probe.stamped[fire]).is_equal([10 * COLS + 10, 10 * COLS + 20])
	assert_array(probe.stamped[remove]).is_equal([10 * COLS + 20])
	assert_array(probe.stamped[remove + 1]).is_equal([10 * COLS + 21])
	var both: PackedInt32Array = _counts([_disc(10, 10, 6000), _disc(20, 10, 6000)])
	assert_array(probe.visible[fire].slice(0, 900)).is_equal(both)
	assert_array(probe.visible[remove].slice(0, 900)).is_equal(_counts([_disc(20, 10, 6000)]))
	assert_array(probe.visible[remove + 1].slice(0, 900)).is_equal(_counts([_disc(21, 10, 6000)]))


## The list is the flips of the last update and lives until that player's next one: kept on the
## ticks in between (also while the other player updates), emptied by the next update even when
## nothing moves. Then a death between updates is added to the list.
func test_the_dirty_list_keeps_the_last_updates_flips_until_the_players_next_update() -> void:
	var world: World = _world()
	world.add_unit(1, SCOUT, _centre(10), _centre(10))
	world.add_unit(2, SCOUT, _centre(20), _centre(20))
	world.prepare()
	world.pos_x[0] += 1000
	world.pos_x[1] += 1000
	Sim.step(world, [])
	assert_array([world.fog.dirty_cells(1).size(), world.fog.dirty_cells(2).size()]).is_equal(
		[26, 113]
	)
	var first: PackedInt32Array = world.fog.dirty_cells(1)
	Sim.step(world, [])
	assert_array([world.fog.dirty_cells(1).size(), world.fog.dirty_cells(2).size()]).is_equal(
		[26, 26]
	)
	var version: int = world.fog.version_of(1)
	Sim.step(world, [])
	assert_array(world.fog.dirty_cells(1)).is_equal(first)
	Sim.step(world, [])
	assert_array(world.fog.dirty_cells(1)).is_empty()
	assert_int(world.fog.version_of(1)).is_equal(version)
	assert_int(world.fog.dirty_cells(2).size()).is_equal(26)
	world.hp[0] = 0
	Sim.step(world, [])
	assert_int(world.fog.dirty_cells(1).size()).is_equal(113)


func test_a_row_added_later_is_stamped_at_its_players_next_update_and_a_neutral_row_never() -> void:
	var world: World = _world()
	world.add_unit(1, POST, _centre(5), _centre(5))
	world.add_unit(2, POST, _centre(5), _centre(25))
	Sim.step(world, [])
	Sim.step(world, [])
	world.add_unit(1, SCOUT, _centre(15), _centre(15))
	world.add_unit(0, SCOUT, _centre(20), _centre(20))
	assert_int(world.fog_cell[2]).is_equal(-1)
	Sim.step(world, [])
	assert_array(world.fog_cell.slice(2)).is_equal([-1, -1])
	Sim.step(world, [])
	assert_array(world.fog_cell.slice(2)).is_equal([15 * COLS + 15, -1])
	assert_int(world.tick).is_equal(4)
	assert_bool(world.fog.is_visible(1, 15 * COLS + 21)).is_true()
	assert_int(world.stats[World.Stat.FOG_CELLS]).is_equal(113)
	for _t: int in 3:
		Sim.step(world, [])
	assert_int(world.fog_cell[3]).is_equal(-1)
	assert_int(_block(world, 1).count(0) + _block(world, 2).count(0)).is_equal(1800 - 13 - 13 - 113)


## The hash covers visible and explored: one changed explored byte, or one count, changes the fog
## section and nothing else, and the change goes back with the byte.
func test_the_hash_changes_when_an_explored_byte_or_a_count_changes() -> void:
	var world: World = _world()
	world.add_unit(1, SCOUT, _centre(10), _centre(10))
	world.add_unit(2, POST, _centre(20), _centre(20))
	Sim.step(world, [])
	var hash_before: int = world.state_hash()
	var parts: PackedInt64Array = world.hash_parts()
	var names: PackedStringArray = World.hash_section_names()
	var fog_part: int = names.find("fog")
	assert_int(fog_part).is_greater(0)
	var corner: int = 0
	assert_int(world.fog.explored[corner]).is_equal(0)
	world.fog.explored[corner] = 1
	assert_int(world.state_hash()).is_not_equal(hash_before)
	var changed: PackedInt64Array = world.hash_parts()
	for part: int in names.size():
		assert_bool(changed[part] != parts[part]).is_equal(part == fog_part)
	world.fog.explored[corner] = 0
	assert_int(world.state_hash()).is_equal(hash_before)
	world.fog.visible[corner] = 1
	assert_int(world.state_hash()).is_not_equal(hash_before)
	world.fog.visible[corner] = 0
	assert_int(world.state_hash()).is_equal(hash_before)


## Two runs of the same scenario and orders give the same hash on every tick, and the fog is in
## it: the fog section and the fog_cell column differ between tick 0 and the end of the run.
func test_two_runs_give_the_same_hashes_and_the_fog_moves_with_the_units() -> void:
	var runs: Array[PackedInt64Array] = [PackedInt64Array(), PackedInt64Array()]
	var parts: Array[PackedInt64Array] = []
	for run: int in 2:
		var world: World = World.from_scenario(load(SCENARIO_PATH) as ScenarioDef)
		var order: Command = Command.attack_move(1, PackedInt32Array(range(1, 31)), 22250, 22250)
		order.tick = 0
		runs[run].append(world.state_hash())
		if run == 0:
			parts.append(world.hash_parts())
		var commands: Array[Command] = [order]
		for _t: int in 90:
			Sim.step(world, commands)
			commands.clear()
			runs[run].append(world.state_hash())
		if run == 0:
			parts.append(world.hash_parts())
	assert_array(runs[0]).is_equal(runs[1])
	assert_int(runs[0].size()).is_equal(91)
	var names: PackedStringArray = World.hash_section_names()
	for section: String in ["fog", "fog_cell", "pos_x"]:
		var part: int = names.find(section)
		assert_bool(parts[0][part] != parts[1][part]).override_failure_message(section).is_true()


func _world() -> World:
	var world: World = World.new()
	world.map_w = MAP
	world.map_h = MAP
	world.type_ids.append_array([&"scout", &"post"])
	world.type_sight.append_array([6000, 2000])
	return world


## The middle of tile `tile` in milli-tiles.
func _centre(tile: int) -> int:
	return tile * 1000 + 500


## The tiles of the 30 x 30 map inside the disc of `sight` milli-tiles at tile (cx, cy), by a brute
## force over every tile: (dx * 1000)^2 + (dy * 1000)^2 <= sight^2, ascending.
func _disc(cx: int, cy: int, sight: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for y: int in COLS:
		for x: int in COLS:
			var dx: int = (x - cx) * 1000
			var dy: int = (y - cy) * 1000
			if dx * dx + dy * dy <= sight * sight:
				out.append(y * COLS + x)
	return out


## The cells that differ between the discs of `sight` at (x1, y1) and at (x2, y2).
func _flips(x1: int, y1: int, x2: int, y2: int, sight: int) -> PackedInt32Array:
	var one: PackedInt32Array = _disc(x1, y1, sight)
	var two: PackedInt32Array = _disc(x2, y2, sight)
	var out: PackedInt32Array = PackedInt32Array()
	for cell: int in COLS * COLS:
		if one.has(cell) != two.has(cell):
			out.append(cell)
	return out


## How many of `discs` cover each cell of the map.
func _counts(discs: Array[PackedInt32Array]) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(COLS * COLS)
	for disc: PackedInt32Array in discs:
		for cell: int in disc:
			out[cell] += 1
	return out


## The visible counts of one player, one per cell.
func _block(world: World, player: int) -> PackedInt32Array:
	return world.fog.visible.slice((player - 1) * COLS * COLS, player * COLS * COLS)
