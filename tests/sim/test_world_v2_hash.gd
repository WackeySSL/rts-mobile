extends GdUnitTestSuite
## World v2, the hash (plan P70, ADR 0017 sections 3 and 7, ADR 0016): the sections players, ore and
## ghosts follow their arrays alone, a ghost record below its player's count is state and one above
## it is not, the derived arrays and the type tables stay out of the state hash, the new state
## stays at its start values through a run of the perf arena (no later Phase 3 row may move the
## arena's golden hashes), and the map digest covers the ore cells and the buildable flags.

const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const TERRAIN_PATH: String = "res://data/terrain/standard.tres"
const TICKS: int = 150
## The index of the first record of player 1: `player * ghost_cap`, with the rule default of 40.
const GHOSTS_OF_PLAYER_1: int = 40


## One element (the last) of each PLAYER_ARRAYS array changes the "players" section and no other.
func test_each_player_array_changes_the_players_section_alone() -> void:
	var base: World = _arena()
	for array_name: StringName in World.PLAYER_ARRAYS:
		var world: World = _arena()
		var column: PackedInt32Array = world.get(array_name)
		column[column.size() - 1] += 1
		_assert_sections(base, world, ["players"], array_name)


## The ore left in a cell changes the "ore" section and no other.
func test_the_ore_left_changes_the_ore_section_alone() -> void:
	var base: World = _ore_world()
	assert_int(base.ore_amount.size()).is_equal(3)
	for cell: int in base.ore_amount.size():
		var world: World = _ore_world()
		world.ore_amount[cell] -= 1
		_assert_sections(base, world, ["ore"], "cell %d" % cell)


## A last-seen record is state while it is below its player's count, field by field, and the count
## is state; a record at or above the count, and any other array of the record, is not.
func test_a_ghost_record_is_state_only_below_its_players_count() -> void:
	var base: World = _arena()
	var seen: World = _arena_with_ghost()
	_assert_sections(base, seen, ["ghosts"], "one record")
	for column_name: StringName in World.GHOST_ARRAYS:
		if column_name != &"ghost_count":
			var world: World = _arena_with_ghost()
			var column: PackedInt32Array = world.get(column_name)
			column[GHOSTS_OF_PLAYER_1] += 1
			_assert_sections(seen, world, ["ghosts"], column_name)
			var spare: World = _arena_with_ghost()  # The record after the live one is free.
			column = spare.get(column_name)
			column[GHOSTS_OF_PLAYER_1 + 1] += 1
			_assert_sections(seen, spare, [], "free %s" % column_name)
	var two: World = _arena_with_ghost()
	two.ghost_count[1] = 2
	_assert_sections(seen, two, ["ghosts"], "count")
	var other: World = _arena_with_ghost()  # The same record held by player 2 is another state.
	other.ghost_count[1] = 0
	other.ghost_count[2] = 1
	for column_name: StringName in [&"ghost_id", &"ghost_type", &"ghost_owner", &"ghost_cell"]:
		var column: PackedInt32Array = other.get(column_name)
		column[2 * GHOSTS_OF_PLAYER_1] = column[GHOSTS_OF_PLAYER_1]
	_assert_sections(seen, other, ["ghosts"], "player 2")


## The derived arrays (ADR 0016) and the Phase 3 type tables are not in the state hash: changing
## one moves no section. The type tables are in defs_hash, the derived arrays in neither.
func test_the_derived_arrays_and_the_type_tables_are_out_of_the_state_hash() -> void:
	var base: World = _arena()
	var defs: int = base.defs_hash()
	for array_name: StringName in World.DERIVED_ARRAYS:
		var world: World = _arena()
		var column: PackedInt32Array = world.get(array_name)
		column.append(1)
		_assert_sections(base, world, [], array_name)
		assert_int(world.defs_hash()).override_failure_message(array_name).is_equal(defs)
	for array_name: StringName in World.TYPE_ARRAYS.slice(11):
		var world: World = _arena()
		var column: PackedInt32Array = world.get(array_name)
		column[column.size() - 1] += 1
		_assert_sections(base, world, [], array_name)
		assert_int(world.defs_hash()).override_failure_message(array_name).is_not_equal(defs)


## The rule ints of Phase 3 are in defs_hash and not in the state hash.
func test_the_phase_3_rule_ints_are_in_defs_hash_and_not_in_the_state_hash() -> void:
	var base: World = _arena()
	var defs: int = base.defs_hash()
	for rule_name: StringName in World.RULE_SCALARS.slice(World.RULE_SCALARS.find(&"max_rows") + 1):
		var world: World = _arena()
		world.set(rule_name, int(world.get(rule_name)) + 1)
		_assert_sections(base, world, [], rule_name)
		assert_int(world.defs_hash()).override_failure_message(rule_name).is_not_equal(defs)


## The perf arena has no building, no ore and no queue: through 150 ticks the players, ore and
## ghosts sections stay what the start made them (no later Phase 3 row may move them, ADR 0017
## section 7), and so does every start value those sections hold.
func test_the_phase_3_state_stays_at_its_start_values_through_a_run_of_the_arena() -> void:
	var world: World = _arena()
	var names: PackedStringArray = World.hash_section_names()
	var start: PackedInt64Array = world.hash_parts()
	var none: Array[Command] = []
	for _tick: int in TICKS:
		Sim.step(world, none)
	var parts: PackedInt64Array = world.hash_parts()
	for section: String in ["players", "ore", "ghosts"]:
		var at: int = names.find(section)
		assert_int(parts[at]).override_failure_message(section).is_equal(start[at])
	assert_array(world.credits).is_equal([0, 2000, 2000])
	assert_array([world.match_end_tick, world.winner]).is_equal([0, 0])
	assert_array(world.defeated_tick).is_equal([0, 0, 0])
	assert_array([world.dropped_commands, world.spawn_refused]).is_equal([0, 0])


## The map digest covers the new map arrays: a buildable flag or an ore cell moves the "map" section
## once the version is bumped, and only that one (a bump alone moves the header).
func test_the_map_digest_covers_the_buildable_flags_and_the_ore_cells() -> void:
	var base: World = _ore_world()
	for array_name: StringName in [&"terrain_buildable", &"ore_cell"]:
		var world: World = _ore_world()
		var column: Variant = world.get(array_name)
		column[column.size() - 1] += 1
		_assert_sections(base, world, [], array_name)
		world.map_version += 1
		_assert_sections(base, world, ["header", "map"], array_name)


## The perf arena from its scenario, 2 players.
func _arena() -> World:
	return World.from_scenario(load(ARENA_PATH) as ScenarioDef)


## The arena with player 1 holding one last-seen record (id 7, type 2, owner 2, cell 99).
func _arena_with_ghost() -> World:
	var world: World = _arena()
	world.ghost_count[1] = 1
	world.ghost_id[GHOSTS_OF_PLAYER_1] = 7
	world.ghost_type[GHOSTS_OF_PLAYER_1] = 2
	world.ghost_owner[GHOSTS_OF_PLAYER_1] = 2
	world.ghost_cell[GHOSTS_OF_PLAYER_1] = 99
	return world


## A 4 x 3 map over the standard terrain set with three ore cells.
func _ore_world() -> World:
	var map: MapDef = MapDef.new()
	map.rows = PackedStringArray(["..oo", "o.#:", "~~.."])
	map.terrain = load(TERRAIN_PATH) as TerrainSetDef
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map = map
	scenario.player_count = 2
	return World.from_scenario(scenario)


## The sections of `world` whose hash part differs from `base`'s are `expected`, and state_hash
## differs exactly when there is one.
func _assert_sections(
	base: World, world: World, expected: Array[String], label: String = ""
) -> void:
	var names: PackedStringArray = World.hash_section_names()
	var before: PackedInt64Array = base.hash_parts()
	var parts: PackedInt64Array = world.hash_parts()
	var differing: Array[String] = []
	for i: int in names.size():
		if parts[i] != before[i]:
			differing.append(names[i])
	assert_array(differing).override_failure_message(label).is_equal(expected)
	var changed: bool = world.state_hash() != base.state_hash()
	assert_bool(changed).override_failure_message(label).is_equal(not expected.is_empty())
