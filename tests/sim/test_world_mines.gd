extends GdUnitTestSuite
## The ground layout (plan row P286, ADR 0037 sections 8, 11 and 15, named exception 25):
## STATE_FORMAT stays 7, the row column `stance`, the mine table (`mine_*`, the scalars
## `next_mine_id` and `mine_count`), the records of found mines (`mine_seen_*`), the section
## `mines` and the derived `mine_at`. No rule uses them yet (Mines.gd is P287, hold position P298);
## this suite pins the shape and what the hash does and does not see. Numbers are literals, so no
## layout can agree with itself. The golden hashes are pinned in test_world_hash and
## tests/perf/test_golden_hashes.

const HashBytes: GDScript = preload("res://tests/perf/support/hash_bytes.gd")
const FOOT: int = World.MoveClass.FOOT


func test_the_layout_version_the_lists_and_the_section_are_the_contract() -> void:
	assert_int(World.STATE_FORMAT).is_equal(7)  # Never shipped at 7 before P286: no new number.
	assert_int(World.HASH_OTHER_SECTIONS).is_equal(9)
	assert_int(World.ROW_ARRAYS.find(&"stance")).is_equal(World.ROW_ARRAYS.find(&"carry_mode") + 1)
	assert_array(World.MINE_ARRAYS).is_equal(
		[&"mine_id", &"mine_owner", &"mine_cell", &"mine_weapon", &"mine_armed_tick"]
	)
	assert_array(World.MINE_SEEN_ARRAYS).is_equal(
		[&"mine_seen_id", &"mine_seen_owner", &"mine_seen_cell", &"mine_seen_count"]
	)
	assert_array(World.HASHED_SCALARS.slice(-3)).is_equal(
		[&"pass_count", &"next_mine_id", &"mine_count"]
	)
	assert_bool(World.DERIVED_ARRAYS.has(&"mine_at")).is_true()
	assert_array(World.hash_section_names().slice(-2)).is_equal(["passengers", "mines"])
	assert_str(World.hash_section_names()[-1]).is_equal("mines")


func test_the_tables_are_sized_from_the_rules_and_start_empty() -> void:
	var world: World = World.from_scenario(_scenario())
	# 2 players x mine_cap 3 mines; 3 entries (players 0..2) x mine_known_cap 2 records.
	assert_int(world.next_mine_id).is_equal(1)
	assert_int(world.mine_count).is_equal(0)
	for column_name: StringName in World.MINE_ARRAYS:
		assert_array(world.get(column_name)).override_failure_message(column_name).is_equal(
			[0, 0, 0, 0, 0, 0]
		)
	for column_name: StringName in [&"mine_seen_id", &"mine_seen_owner", &"mine_seen_cell"]:
		assert_array(world.get(column_name)).override_failure_message(column_name).is_equal(
			[0, 0, 0, 0, 0, 0]
		)
	assert_array(world.mine_seen_count).is_equal([0, 0, 0])
	assert_int(world.mine_at.size()).is_equal(12 * 3)  # One entry per map cell.
	assert_int(world.mine_at.count(0)).is_equal(12 * 3)
	# The default `mine_cap` is 0: a scenario that sets none has no mine table (no mine can be laid).
	# `mine_known_cap` defaults to 24, so its records are sized, and empty.
	var plain: World = World.from_scenario(ScenarioDef.new())
	assert_int(plain.mine_id.size()).is_equal(0)
	assert_int(plain.mine_seen_id.size()).is_equal((plain.player_count + 1) * 24)
	assert_int(plain.mine_seen_count.count(0)).is_equal(plain.player_count + 1)
	assert_array(world.stance).is_equal([0, 0])


func test_each_new_value_moves_its_own_section_and_the_derived_array_moves_none() -> void:
	var base: World = World.from_scenario(_scenario())
	var world: World = World.from_scenario(_scenario())
	world.stance[1] = 1
	_assert_sections(base, world, ["stance"])
	world = World.from_scenario(_scenario())
	world.next_mine_id = 5  # A counter is in the header.
	_assert_sections(base, world, ["header"])
	world = World.from_scenario(_scenario())
	world.mine_count = 1  # The count is in the header, and its record (all zeros) in the section.
	_assert_sections(base, world, ["header", "mines"])
	# Each field of a live mine is in the section.
	for column_name: StringName in World.MINE_ARRAYS:
		var live: World = World.from_scenario(_scenario())
		live.mine_count = 2
		var other: World = World.from_scenario(_scenario())
		other.mine_count = 2
		var column: PackedInt32Array = other.get(column_name)
		column[1] += 1
		_assert_sections(live, other, ["mines"], String(column_name))
	# A slot at or above the count is not state.
	world = World.from_scenario(_scenario())
	for column_name: StringName in World.MINE_ARRAYS:
		var column: PackedInt32Array = world.get(column_name)
		column[5] = 77
	_assert_sections(base, world, [])
	# Each field of a live record is in the section: entry `player * mine_known_cap + record`.
	for column_name: StringName in [&"mine_seen_id", &"mine_seen_owner", &"mine_seen_cell"]:
		var live: World = World.from_scenario(_scenario())
		live.mine_seen_count[2] = 2
		var other: World = World.from_scenario(_scenario())
		other.mine_seen_count[2] = 2
		var column: PackedInt32Array = other.get(column_name)
		column[2 * 2 + 1] += 1
		_assert_sections(live, other, ["mines"], String(column_name))
	# The count of a player is in the section, and in no other.
	world = World.from_scenario(_scenario())
	world.mine_seen_count[1] = 1
	_assert_sections(base, world, ["mines"])
	# A record at or above its player's count is not state.
	world = World.from_scenario(_scenario())
	world.mine_seen_id[3] = 9
	_assert_sections(base, world, [])
	# The derived `mine_at` and the rule ints are in no section of the state hash.
	world = World.from_scenario(_scenario())
	world.mine_at[7] = 1
	_assert_sections(base, world, [])
	var rule: World = World.from_scenario(_scenario())
	rule.mine_cap = 99
	assert_int(rule.state_hash()).is_equal(base.state_hash())
	assert_int(rule.defs_hash()).is_not_equal(base.defs_hash())


func test_a_count_outside_the_table_is_clamped_to_zero_and_the_table_size() -> void:
	var world: World = World.from_scenario(_scenario())
	for column_name: StringName in World.MINE_ARRAYS:
		var column: PackedInt32Array = world.get(column_name)
		for slot: int in 6:
			column[slot] = 10 + slot  # A full table: 3 mines each of 2 players.
	var at: int = World.hash_section_names().find("mines")
	var parts: Dictionary[int, int] = {}
	for count: int in [-1, 0, 6, 99]:
		world.mine_count = count
		parts[count] = world.hash_parts()[at]
	assert_int(parts[99]).is_equal(parts[6])  # No script error, and the table's size.
	assert_int(parts[-1]).is_equal(parts[0])
	assert_int(parts[6]).is_not_equal(parts[0])
	# A column shorter than the others bounds the count as well.
	world.mine_count = 6
	world.mine_owner.resize(2)
	var short: int = world.hash_parts()[at]
	world.mine_count = 2
	assert_int(world.hash_parts()[at]).is_equal(short)
	# The same for the records: a count past the player's block reads nothing past it.
	var seen: World = World.from_scenario(_scenario())
	seen.mine_seen_count[2] = 50
	assert_int(seen.hash_parts().size()).is_equal(World.hash_section_names().size())
	seen.mine_seen_id.resize(3)  # A short column bounds the records as well.
	seen.mine_seen_count[2] = 2
	assert_int(seen.hash_parts().size()).is_equal(World.hash_section_names().size())


func test_a_new_row_starts_with_stance_0_and_a_removal_moves_the_column() -> void:
	var world: World = World.from_scenario(_scenario())
	world.stance[1] = 1
	world.hp[0] = 0
	world.remove_dead()
	assert_array(world.stance).is_equal([1])
	var id: int = world.add_unit(1, 0, 500, 500)
	assert_array(world.stance).is_equal([1, 0])
	var at: int = world.insert_row(1, 1, 0, 50, 700, 700)  # An old id goes back in id order.
	assert_int(at).is_equal(0)
	assert_array(world.stance).is_equal([0, 1, 0])
	assert_int(id).is_greater(1)


## The hash bytes the perf harness rebuilds from the shape lists equal state_hash() with live mines
## and records, and the live prefix is what they carry.
func test_the_rebuilt_stream_hashes_like_the_world_with_live_mines_and_records() -> void:
	var world: World = World.from_scenario(_scenario())
	world.mine_count = 2
	world.next_mine_id = 3
	for slot: int in 2:
		world.mine_id[slot] = slot + 1
		world.mine_owner[slot] = 1 + slot
		world.mine_cell[slot] = 10 + slot
		world.mine_weapon[slot] = 0
		world.mine_armed_tick[slot] = 30
	world.mine_seen_count[1] = 1
	world.mine_seen_id[2] = 2  # Player 1, record 0: entry 1 * mine_known_cap.
	world.mine_seen_owner[2] = 2
	world.mine_seen_cell[2] = 11
	world.stance[0] = 1
	assert_int(HashBytes.digest(HashBytes.stream(world))).is_equal(world.state_hash())
	var empty: World = World.from_scenario(_scenario())
	assert_int(HashBytes.digest(HashBytes.stream(empty))).is_equal(empty.state_hash())
	assert_int(world.state_hash()).is_not_equal(empty.state_hash())


## Two tiny rule ints and a unit that gives a mine table of 2 x 3 entries, records of 2 per player
## on a 12 x 3 grass map, and two rows.
func _scenario() -> ScenarioDef:
	var terrains: TerrainSetDef = TerrainSetDef.new()
	var grass: TerrainDef = TerrainDef.new()
	grass.symbol = "."
	grass.cost = PackedInt32Array([10, 10, 10])
	terrains.terrains.append(grass)
	var map: MapDef = MapDef.new()
	map.rows = PackedStringArray(["............", "............", "............"])
	map.terrain = terrains
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map = map
	scenario.player_count = 2
	var rules: RulesDef = RulesDef.new()
	rules.mine_cap = 3
	rules.mine_known_cap = 2
	scenario.rules = rules
	var rifle: UnitDef = UnitDef.new()
	rifle.type_id = &"rifle"
	rifle.speed = 100
	rifle.radius = 300
	rifle.sight_range = 3000
	rifle.max_hp = 100
	rifle.move_class = FOOT
	scenario.roster.append(rifle)
	for owner: int in [1, 2]:
		var spawn: SpawnDef = SpawnDef.new()
		spawn.owner = owner
		spawn.unit = rifle
		spawn.count = 1
		spawn.origin_tile = Vector2i(1 + owner * 3, 1)
		scenario.spawns.append(spawn)
	return scenario


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
