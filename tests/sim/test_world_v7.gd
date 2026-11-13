extends GdUnitTestSuite
## World v7, the carriers' layout (plan row P262, ADR 0036 sections 3 and 8, named exception 24):
## STATE_FORMAT 7, the row column `carry_mode`, the type tables `type_carry_slots` and
## `type_carry_classes`, the passenger table (`pass_*`, the hashed scalar `pass_count`, the rule
## `passenger_cap`, the section `passengers`) and `World.insert_row`. The rules that use them come
## with Carry.gd (P263); this suite pins the shape. Numbers are literals, so no layout can agree
## with itself. The golden hashes are pinned in test_world_hash and tests/perf/test_golden_hashes.

const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const FOOT: int = World.MoveClass.FOOT
const AIR: int = World.MoveClass.AIR


func test_the_layout_version_the_lists_and_the_section_are_the_contract() -> void:
	assert_int(World.STATE_FORMAT).is_equal(7)
	assert_int(World.HASH_OTHER_SECTIONS).is_equal(8)
	# Adjacent pairs, found by name, so that a later row moves nothing here.
	assert_int(World.ROW_ARRAYS.find(&"carry_mode")).is_equal(World.ROW_ARRAYS.find(&"ammo") + 1)
	var slots_at: int = World.TYPE_ARRAYS.find(&"type_carry_slots")
	assert_int(slots_at).is_greater(0)
	assert_int(World.TYPE_ARRAYS.find(&"type_carry_classes")).is_equal(slots_at + 1)
	assert_array(World.PASSENGER_ARRAYS).is_equal(
		[&"pass_carrier", &"pass_id", &"pass_type", &"pass_hp", &"pass_owner"]
	)
	assert_bool(World.HASHED_SCALARS.has(&"pass_count")).is_true()
	for list: Array[StringName] in [World.RULE_SCALARS, World.UNHASHED_SCALARS]:
		var cap_at: int = list.find(&"passenger_cap")
		assert_int(cap_at).is_greater(0)
		assert_int(cap_at).is_equal(list.find(&"mend_cost_percent") + 1)
	assert_array(World.hash_section_names().slice(-2)).is_equal(["ghosts", "passengers"])


func test_the_type_tables_come_from_the_defs_and_a_padded_type_carries_nothing() -> void:
	var world: World = World.from_scenario(_scenario())
	assert_array(world.type_ids).is_equal([&"rifle", &"truck", &"carrier"])
	assert_array(world.type_carry_slots).is_equal([0, 0, 3])
	assert_array(world.type_carry_classes).is_equal([0, 0, 1])
	var bare: World = World.new()
	bare.type_ids.append_array([&"a", &"b"])
	bare.prepare()
	assert_array(bare.type_carry_slots).is_equal([0, 0])
	assert_array(bare.type_carry_classes).is_equal([0, 0])
	# Rules, not state: a table is in defs_hash and out of the state hash.
	var changed: World = World.from_scenario(_scenario())
	var hash_before: int = changed.state_hash()
	var defs_before: int = changed.defs_hash()
	changed.type_carry_slots[2] = 2
	assert_int(changed.state_hash()).is_equal(hash_before)
	assert_int(changed.defs_hash()).is_not_equal(defs_before)


func test_the_passenger_table_is_sized_by_the_rule_and_starts_empty() -> void:
	var scenario: ScenarioDef = _scenario()
	var world: World = World.from_scenario(scenario)
	assert_int(world.passenger_cap).is_equal(4)
	assert_int(world.pass_count).is_equal(0)
	for column_name: StringName in World.PASSENGER_ARRAYS:
		assert_array(world.get(column_name)).override_failure_message(column_name).is_equal(
			[0, 0, 0, 0]
		)
	# The default rule is 0: a scenario that sets none has an empty table, and nothing can board.
	var plain: World = World.from_scenario(ScenarioDef.new())
	assert_int(plain.passenger_cap).is_equal(0)
	assert_int(plain.pass_id.size()).is_equal(0)
	# A column that every row starts at 0 for.
	assert_array(world.carry_mode).is_equal([0, 0, 0])


func test_each_new_value_moves_its_own_section_and_the_rule_moves_none() -> void:
	var base: World = World.from_scenario(_scenario())
	var world: World = World.from_scenario(_scenario())
	world.carry_mode[2] = 1
	_assert_sections(base, world, ["carry_mode"])
	world = World.from_scenario(_scenario())
	world.pass_count = 1  # The count is in the header, and its record (all zeros) in the section.
	_assert_sections(base, world, ["header", "passengers"])
	world = World.from_scenario(_scenario())
	world.pass_count = 1
	world.pass_id[0] = 9
	_assert_sections(base, world, ["header", "passengers"])
	# A slot at or above the count is not state.
	world = World.from_scenario(_scenario())
	for column_name: StringName in World.PASSENGER_ARRAYS:
		var column: PackedInt32Array = world.get(column_name)
		column[3] = 77
	_assert_sections(base, world, [])
	# Each field of a live record is in the section.
	for column_name: StringName in World.PASSENGER_ARRAYS:
		var live: World = World.from_scenario(_scenario())
		live.pass_count = 2
		var other: World = World.from_scenario(_scenario())
		other.pass_count = 2
		var column: PackedInt32Array = other.get(column_name)
		column[1] += 1
		_assert_sections(live, other, ["passengers"], String(column_name))
	# The cap is a rule: the state hash stays, defs_hash moves.
	var rule: World = World.from_scenario(_scenario())
	rule.passenger_cap = 99
	assert_int(rule.state_hash()).is_equal(base.state_hash())
	assert_int(rule.defs_hash()).is_not_equal(base.defs_hash())


func test_a_count_outside_the_table_is_clamped_to_zero_and_the_table_size() -> void:
	var world: World = World.from_scenario(_scenario())
	for column_name: StringName in World.PASSENGER_ARRAYS:
		var column: PackedInt32Array = world.get(column_name)
		for slot: int in 4:
			column[slot] = 10 + slot  # A full table: the cap is 4.
	var parts: Dictionary[int, int] = {}
	var at: int = World.hash_section_names().find("passengers")
	for count: int in [-1, 0, 4, 9]:
		world.pass_count = count
		parts[count] = world.hash_parts()[at]
	assert_int(parts[9]).is_equal(parts[4])  # No script error, and the table's size.
	assert_int(parts[-1]).is_equal(parts[0])
	assert_int(parts[4]).is_not_equal(parts[0])
	# A column shorter than the others bounds the count as well.
	world.pass_count = 4
	world.pass_hp.resize(2)
	var short: int = world.hash_parts()[at]
	world.pass_count = 2
	assert_int(world.hash_parts()[at]).is_equal(short)


func test_a_new_row_starts_with_carry_mode_0_and_a_removal_moves_the_column() -> void:
	var world: World = World.from_scenario(_scenario())
	assert_array(world.carry_mode).is_equal([0, 0, 0])
	world.carry_mode[1] = 1
	world.carry_mode[2] = 1
	world.hp[0] = 0
	world.remove_dead()
	assert_array(world.carry_mode).is_equal([1, 1])
	var id: int = world.add_unit(1, 2, 500, 500)
	assert_int(world.carry_mode[world.index_of(id)]).is_equal(0)


func test_insert_row_puts_the_squad_back_in_id_order_with_its_old_id() -> void:
	var world: World = _hand_world()
	var ids: Array[int] = []
	for _i: int in 5:
		ids.append(world.add_unit(1, 0, 1500 + _i * 1000, 1500))
	assert_array(ids).is_equal([1, 2, 3, 4, 5])
	# Distinct values in more columns of the rows that stay (ids 2 and 4), so that a rotation that
	# skips a column shows.
	var marked: Array[StringName] = [
		&"carry_mode", &"ammo", &"cooldown", &"home", &"stall", &"cargo", &"order_target", &"target"
	]
	for index: int in marked.size():
		for row: int in [1, 3]:
			var column: PackedInt32Array = world.get(marked[index])
			column[row] = 100 * (row + 1) + index + 1
	# Three squads leave the table (board); they come back later: a gap, and one at each end.
	for row: int in [0, 2, 4]:
		world.hp[row] = 0
	world.remove_dead()
	assert_array(world.unit_id).is_equal([2, 4])
	var events_before: int = world.events.size()
	var next_before: int = world.next_id
	var version: int = world.rows_version
	assert_int(world.insert_row(3, 1, 0, 40, 3500, 2500)).is_equal(1)
	assert_int(world.next_id).is_equal(next_before)  # After each call: the last id is below it.
	assert_int(world.rows_version).is_equal(version + 1)
	assert_int(world.insert_row(1, 1, 0, 55, 1500, 2500)).is_equal(0)
	assert_int(world.next_id).is_equal(next_before)
	assert_int(world.insert_row(5, 2, 0, 77, 4500, 500)).is_equal(4)
	assert_int(world.next_id).is_equal(next_before)
	assert_int(world.rows_version).is_equal(version + 3)
	assert_array(world.unit_id).is_equal([1, 2, 3, 4, 5])
	assert_array(world.hp).is_equal([55, 100, 40, 100, 77])
	assert_array(world.owner).is_equal([1, 1, 1, 1, 2])
	assert_array(world.pos_x).is_equal([1500, 2500, 3500, 4500, 4500])
	assert_array(world.pos_y).is_equal([2500, 1500, 2500, 1500, 500])
	# Every column has one entry per row.
	for column_name: StringName in World.ROW_ARRAYS:
		assert_int(world.get(column_name).size()).override_failure_message(column_name).is_equal(5)
	# The rows that stayed kept every marked value, now one or two rows further down...
	for id: int in [2, 4]:
		var row: int = world.index_of(id)
		var source: int = id - 1  # Their row before the inserts' ids were removed: 1 and 3.
		for index: int in marked.size():
			var column: PackedInt32Array = world.get(marked[index])
			(
				assert_int(column[row])
				. override_failure_message("id %d %s" % [id, marked[index]])
				. is_equal(100 * (source + 1) + index + 1)
			)
	# ...and the new rows are idle at their start values.
	for row: int in [0, 2, 4]:
		(
			assert_array(
				[
					world.order[row],
					world.goal_x[row] - world.pos_x[row],
					world.order_target[row],
					world.target[row],
					world.cooldown[row],
					world.field[row],
					world.fog_cell[row],
					world.build_left[row],
					world.carry_mode[row],
					world.harvest_slot[row],
					world.group_cell[row],
					world.ammo[row],
					world.home[row],
					world.stall[row],
					world.cargo[row],
				]
			)
			. override_failure_message("row %d" % row)
			. is_equal([0, 0, 0, 0, 0, -1, -1, 0, 0, -1, -1, 0, 0, 0, 0])
		)
	# No event, no refusal count and no new player.
	assert_array([world.events.size(), world.spawn_refused, world.player_count]).is_equal(
		[events_before, 0, 2]
	)
	assert_int(world.index_of(3)).is_equal(2)


func test_insert_row_gives_the_row_the_shots_of_its_type_and_takes_hp_1() -> void:
	var world: World = _hand_world()
	world.type_ammo[1] = 6
	world.add_unit(1, 0, 500, 500)
	world.add_unit(1, 0, 900, 900)
	world.hp[0] = 0
	world.remove_dead()
	assert_int(world.insert_row(1, 1, 1, 1, 800, 800)).is_equal(0)
	assert_array(world.ammo).is_equal([6, 0])
	assert_array(world.hp).is_equal([1, 100])


func test_insert_row_refuses_and_changes_nothing() -> void:
	var world: World = _gapped_world()
	var snapshot: World = _gapped_world()
	assert_array(world.unit_id).is_equal([1, 2, 3])
	assert_int(world.next_id).is_equal(5)  # Ids 1 to 4 were issued, 4 is free.
	var version: int = world.rows_version
	# A used id, an id that is none, negative, not yet issued (next_id) or far past it, hp below 1,
	# an owner of none or beyond the players, an unknown type.
	var cases: Array = [
		["used id", [2, 1, 0, 10, 0, 0]],
		["id 0", [0, 1, 0, 10, 0, 0]],
		["negative id", [-3, 1, 0, 10, 0, 0]],
		["id at next_id", [5, 1, 0, 10, 0, 0]],
		["id past next_id", [99, 1, 0, 10, 0, 0]],
		["hp 0", [4, 1, 0, 0, 0, 0]],
		["negative hp", [4, 1, 0, -5, 0, 0]],
		["neutral owner", [4, 0, 0, 10, 0, 0]],
		["owner past the players", [4, 3, 0, 10, 0, 0]],
		["negative type", [4, 1, -1, 10, 0, 0]],
		["type past the tables", [4, 1, 2, 10, 0, 0]],
	]
	for row: Array in cases:
		var args: Array = row[1]
		var result: int = world.insert_row(args[0], args[1], args[2], args[3], args[4], args[5])
		assert_int(result).override_failure_message(row[0]).is_equal(-1)
		assert_int(world.rows_version).override_failure_message(row[0]).is_equal(version)
		assert_str(StateDiff.first(world, snapshot)).override_failure_message(row[0]).is_empty()
	# The free issued id itself is accepted.
	assert_int(world.insert_row(4, 1, 0, 10, 0, 0)).is_equal(3)


func test_insert_row_refuses_at_max_rows_and_takes_the_last_free_row() -> void:
	var world: World = _hand_world()
	world.max_rows = 4
	world.prepare()
	for _i: int in 4:
		world.add_unit(1, 0, 1500, 1500)
	for row: int in [1, 2, 3]:
		world.hp[row] = 0
	world.remove_dead()  # Id 1 stays: one row, with room for three.
	assert_int(world.insert_row(2, 1, 0, 10, 500, 500)).is_equal(1)
	assert_int(world.insert_row(3, 1, 0, 10, 500, 500)).is_equal(2)
	assert_int(world.insert_row(4, 1, 0, 10, 500, 500)).is_equal(3)
	assert_int(world.unit_count()).is_equal(4)
	world.next_id = 20  # So that id 9 passes the id guard: only the full table refuses it.
	var version: int = world.rows_version
	var hash_before: int = world.state_hash()
	assert_int(world.insert_row(9, 1, 0, 10, 500, 500)).is_equal(-1)  # Full.
	assert_int(world.rows_version).is_equal(version)
	assert_int(world.state_hash()).is_equal(hash_before)
	assert_int(world.spawn_refused).is_equal(0)


## A world with a row inserted mid-table, after some steps and with the kernels attached, steps on
## the same in both implementations. Both runs get the same setup: the implementation is chosen
## first, then the rows are added. The map has no building or harvester row, so the derived row
## lists are not exercised here.
func test_a_world_with_an_inserted_row_steps_on_the_same_under_both_implementations() -> void:
	var hashes: Array[int] = []
	for impl: int in SimImpls.IMPLS:
		var world: World = GridWorld.from_rows(GridWorld.grass(16, 6), [FOOT])
		world.player_count = 2
		assert_array(SimImpls.use(world, impl)).is_empty()
		for i: int in 4:
			world.add_unit(1 + i % 2, 0, 2500 + i * 1500, 2500)
		for _tick: int in 5:
			Sim.step(world, [])
		world.hp[1] = 0
		world.remove_dead()
		assert_int(world.insert_row(2, 2, 0, 100, 6500, 3500)).is_equal(1)
		var order: Command = Command.move(1, PackedInt32Array([1, 2]), 12500, 4500)
		order.tick = world.tick
		var first: Array[Command] = [order]
		Sim.step(world, first)
		for _tick: int in 60:
			Sim.step(world, [])
		assert_int(world.dropped_commands).is_equal(0)
		hashes.append(world.state_hash())
	assert_int(hashes[0]).is_equal(hashes[1])


## Ids 1 to 3 as rows and id 4 issued and free (a squad that boarded), next_id 5.
func _gapped_world() -> World:
	var world: World = _hand_world()
	for _i: int in 4:
		world.add_unit(1, 0, 1500, 1500)
	world.hp[3] = 0
	world.remove_dead()
	return world


func _hand_world() -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(12, 6), [FOOT, AIR])
	world.player_count = 2
	world.type_max_hp[0] = 100
	world.type_max_hp[1] = 100
	return world


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


## Three types (a rifle squad, a truck and a carrier of 3 squads that takes FOOT), a table of 4
## squads and three rows, one of each type, on a 12 x 3 grass map.
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
	scenario.player_count = 1
	var rules: RulesDef = RulesDef.new()
	rules.passenger_cap = 4
	scenario.rules = rules
	var rifle: UnitDef = _unit(&"rifle")
	var truck: UnitDef = _unit(&"truck")
	var carrier: UnitDef = _unit(&"carrier")
	carrier.carry_slots = 3
	carrier.carry_classes = 1
	for unit: UnitDef in [rifle, truck, carrier]:
		scenario.roster.append(unit)
		var spawn: SpawnDef = SpawnDef.new()
		spawn.owner = 1
		spawn.unit = unit
		spawn.count = 1
		spawn.origin_tile = Vector2i(1 + scenario.spawns.size() * 3, 1)
		scenario.spawns.append(spawn)
	return scenario


func _unit(id: StringName) -> UnitDef:
	var unit: UnitDef = UnitDef.new()
	unit.type_id = id
	unit.speed = 100
	unit.radius = 300
	unit.sight_range = 3000
	unit.max_hp = 100
	unit.move_class = FOOT
	return unit
