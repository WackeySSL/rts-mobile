extends GdUnitTestSuite
## The state hash (P31b, ADR 0007 section 8): the helper lists, that each hashed member changes its
## section and no unhashed one changes the hash, the map digest cache, hash_hex, the pinned tick-0
## hash and defs_hash. Numbers are literals, so no layout can agree with itself.

const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
## hash_hex(state_hash()) of controls_test at tick 0, seed 1. Change it only in a PR that changes
## the hash layout or the scenario, and say so there. P37b: the `group_cell` column joined
## ROW_ARRAYS (STATE_FORMAT stays 1, no golden hash exists yet), so the digest changed from
## 73341a6f5754b7b4. P48: controls_test got its map (data/maps/controls_test.tres), so only the
## "map" section changed (the digest of terrain, move_cost and terrain_cost); the scenario without
## the map still hashes to the previous cf4af0c09a33ccf2.
const TICK_0_SEED_1: String = "d7d4de335b7cdde2"


## Every int, bool and Packed array member of a helper, private ones too, is in HASHED or UNHASHED
## once and nothing else is (P32f's FogGrid check for every helper and flow slot; the bool counts).
func test_every_helper_member_is_listed_once() -> void:
	var world: World = _world()
	assert_int(world.flow.fields.size()).is_equal(8)
	assert_array(FogGrid.HASHED).is_equal([&"visible", &"explored"])
	for derived: Array in [FlowCache.HASHED, FlowField.HASHED, SpatialGrid.HASHED]:
		assert_array(derived).is_empty()
	for helper: Array in _helpers(world):
		var found: Array[StringName] = []
		for info: Dictionary in helper[0].get_property_list():
			var kind: int = info.type
			var script_var: bool = (int(info.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0
			var packed: bool = kind >= TYPE_PACKED_BYTE_ARRAY and kind < TYPE_MAX
			if script_var and (kind == TYPE_INT or kind == TYPE_BOOL or packed):
				found.append(StringName(info.name))
		var listed: Array = helper[2] + helper[3]
		assert_array(found).override_failure_message(helper[1]).contains_exactly_in_any_order(
			listed
		)


## The rule ints defs_hash covers are the RulesDef ints (UNHASHED_SCALARS holds them by name).
func test_the_rule_scalars_are_the_rules_def_ints() -> void:
	var rule_ints: Array[StringName] = []
	for info: Dictionary in RulesDef.new().get_property_list():
		if (int(info.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and info.type == TYPE_INT:
			rule_ints.append(StringName(info.name))
	assert_array(World.RULE_SCALARS).contains_exactly_in_any_order(rule_ints)


## A `+` on typed constants gives an untyped Array (Godot 4.7.2), which a typed local or parameter
## of a later kernel or test would refuse at runtime only. Every shape, scalar and HASHED/UNHASHED
## list of World and its helpers is a literal Array[StringName].
func test_every_shape_scalar_and_hashed_list_is_a_typed_string_name_array() -> void:
	var checked: int = 0
	for script: GDScript in [World, FlowCache, FlowField, SpatialGrid, FogGrid]:
		var constants: Dictionary = script.get_script_constant_map()
		for const_name: String in constants:
			var is_list: bool = const_name.ends_with("_ARRAYS") or const_name.ends_with("_SCALARS")
			if is_list or const_name == "HASHED" or const_name == "UNHASHED":
				var list: Array = constants[const_name]
				var label: String = "%s.%s" % [script.get_global_name(), const_name]
				var typed: bool = list.is_typed() and list.get_typed_builtin() == TYPE_STRING_NAME
				assert_bool(typed).override_failure_message(label).is_true()
				checked += 1
	assert_int(checked).is_equal(20)


## The literal UNHASHED lists repeat the names of STATE_ARRAYS and RULE_SCALARS; this keeps the
## repeat honest.
func test_the_unhashed_lists_repeat_the_state_arrays_and_the_rule_scalars() -> void:
	for pair: Array in [
		[FlowCache.STATE_ARRAYS, FlowCache.UNHASHED],
		[FlowField.STATE_ARRAYS, FlowField.UNHASHED],
		[World.RULE_SCALARS, World.UNHASHED_SCALARS],
	]:
		for member: StringName in pair[0]:
			assert_array(pair[1]).contains([member])


## One element (the last) of each row column, each hashed scalar and the stream changes its section.
func test_each_hashed_row_array_scalar_and_the_stream_changes_its_section() -> void:
	var base: World = _world()
	for column_name: StringName in World.ROW_ARRAYS:
		var world: World = _world()
		var column: PackedInt32Array = world.get(column_name)
		column[column.size() - 1] += 1
		_assert_sections(base, world, [String(column_name)], column_name)
	for scalar_name: StringName in World.HASHED_SCALARS:
		var world: World = _world()
		world.set(scalar_name, int(world.get(scalar_name)) - 1)
		var expected: Array[String] = ["header"]
		if scalar_name == &"proj_free_top":
			expected.append("projectiles")  # The used part of the free stack is shorter.
		_assert_sections(base, world, expected, scalar_name)
	var stepped: World = _world()
	stepped.rng.next_u32()
	_assert_sections(base, stepped, ["header"])


## A live slot is hashed with its index and fields, the free stack up to proj_free_top; a free
## slot's fields and the stack above the top are not state.
func test_projectiles_hash_the_live_slots_and_the_used_free_stack() -> void:
	var base: World = _with_projectile(0)
	_assert_sections(_world(), _with_projectile(0), ["header", "projectiles"])
	_assert_sections(base, _with_projectile(1), ["projectiles"])
	for column_name: StringName in World.PROJECTILE_ARRAYS:
		var live: World = _with_projectile(0)
		var column: PackedInt32Array = live.get(column_name)
		column[3 if column_name == &"proj_free" else 0] += 1  # A stack entry in use, or the slot.
		_assert_sections(base, live, ["projectiles"], column_name)
		if column_name != &"proj_id":  # A slot with another proj_id is not free.
			var free: World = _with_projectile(0)
			column = free.get(column_name)
			column[free.proj_free_top if column_name == &"proj_free" else 2] += 1  # Free or above.
			_assert_sections(base, free, [], column_name)


func test_the_fog_arrays_change_the_fog_section() -> void:
	var base: World = _world()
	for array_name: StringName in FogGrid.HASHED:
		var world: World = _world()
		var grid: Variant = world.fog.get(array_name)
		grid[grid.size() - 1] += 1  # The last cell of the last player.
		_assert_sections(base, world, ["fog"], array_name)


## One case per helper (fog, the cache, each slot, both grids) and one for World: every unhashed
## member changed, one after the other, leaves the hash as it was. World's `_map_digest` is left
## out: it is the cache that feeds the map section, so a changed value is a changed input.
func test_changing_an_unhashed_member_leaves_the_hash_unchanged() -> void:
	var world: World = _world()
	var baseline: int = world.state_hash()
	var unhashed: Array = World.UNHASHED_SCALARS + World.TYPE_ARRAYS + World.WEAPON_ARRAYS
	unhashed.append_array(World.SCRATCH_ARRAYS + World.RUNTIME_ARRAYS)
	var targets: Array[Array] = _helpers(world)
	targets.append([world, "world", [], unhashed])
	for target: Array in targets:
		for member: StringName in target[3]:
			if member != &"_map_digest":
				_poke(target[0], member)
				var label: String = "%s.%s" % [target[1], member]
				assert_int(world.state_hash()).override_failure_message(label).is_equal(baseline)


## Which implementation runs a phase is never state (ADR 0013 section 3): attaching kernels and a
## phase mask changes no section of the hash, and the hash walk reads only its lists.
func test_attaching_kernels_and_a_phase_mask_changes_no_section_of_the_hash() -> void:
	var world: World = _world()
	var baseline: int = world.state_hash()
	var parts: PackedInt64Array = world.hash_parts()
	world.kernels = RefCounted.new()
	world.native_phases = 0x7FF
	assert_int(world.state_hash()).is_equal(baseline)
	assert_array(world.hash_parts()).is_equal(parts)
	assert_bool(World.UNHASHED_SCALARS.has(&"native_phases")).is_true()


func test_set_terrain_changes_the_header_and_the_map_digest() -> void:
	var world: World = _arena()
	world.set_terrain(world.terrain.find(0), 2)
	_assert_sections(_arena(), world, ["header", "map"])


## The digest covers all three MAP_ARRAYS, is recomputed when map_version changes and not before,
## and does not depend on map_version itself (a bump alone changes only the header).
func test_each_map_array_changes_the_map_part_once_the_version_is_bumped() -> void:
	var base: World = _arena()
	for array_name: StringName in World.MAP_ARRAYS:
		var world: World = _arena()
		var column: PackedByteArray = world.get(array_name)
		column[column.size() - 1] += 1
		_assert_sections(base, world, [], array_name)
		world.map_version += 1
		_assert_sections(base, world, ["header", "map"], array_name)
	var bumped: World = _arena()
	bumped.map_version += 1
	_assert_sections(base, bumped, ["header"])


func test_hash_hex_is_sixteen_lower_case_digits_least_significant_byte_first() -> void:
	var cases: Dictionary[int, String] = {
		0: "0000000000000000",
		1: "0100000000000000",
		-1: "ffffffffffffffff",
		-2: "feffffffffffffff",
		-9223372036854775807 - 1: "0000000000000080",
		0x0123456789ABCDEF: "efcdab8967452301",
	}
	for value: int in cases:
		assert_str(World.hash_hex(value)).is_equal(cases[value])


func test_the_sections_are_named_in_hash_order() -> void:
	var names: PackedStringArray = World.hash_section_names()
	assert_array(names.slice(0, 4)).is_equal(["header", "map", "unit_id", "owner"])
	assert_array(names.slice(21)).is_equal(["fog_cell", "projectiles", "fog"])
	assert_array(names.slice(2, 22)).is_equal(World.ROW_ARRAYS)
	assert_int(_world().hash_parts().size()).is_equal(names.size())


func test_equal_worlds_hash_equal_and_the_tick_0_hash_with_seed_1_is_pinned() -> void:
	var world: World = _world()
	assert_str(World.hash_hex(world.state_hash())).is_equal(TICK_0_SEED_1)
	assert_array(_world().hash_parts()).is_equal(world.hash_parts())


## A hand-built world hashes before prepare() (empty helpers and map) to another value than after,
## and the digest follows the grid prepare() builds without a map_version bump (the same as a world
## never hashed early). A scenario world is prepared; a second prepare() keeps its hash.
func test_a_hand_built_world_and_a_scenario_world_hash_the_same_way_every_time() -> void:
	var early: World = _hand_built()
	var before: int = early.state_hash()
	assert_int(_hand_built().state_hash()).is_equal(before)
	early.prepare()
	var late: World = _hand_built()
	late.prepare()
	assert_int(late._map_digest_version).is_equal(late.map_version)  # prepare() made the digest.
	assert_int(early.state_hash()).is_not_equal(before)
	assert_array(early.hash_parts()).is_equal(late.hash_parts())
	var scenario: World = _world()
	var after_setup: int = scenario.state_hash()
	scenario.prepare()
	assert_int(scenario.state_hash()).is_equal(after_setup)


## defs_hash covers the weapon and type tables entry by entry, their ids and the rule ints, and none
## of the match state.
func test_defs_hash_follows_the_data_and_not_the_state() -> void:
	var defs: int = _world().defs_hash()
	assert_int(_world().defs_hash()).is_equal(defs)
	var played: World = _world()
	played.tick += 3
	played.hp[0] -= 1
	played.set_terrain(0, 0)
	assert_int(played.defs_hash()).is_equal(defs)
	var heavier: World = _world()
	heavier.weapon_damage[0] += 1
	assert_int(heavier.defs_hash()).is_not_equal(defs)
	for table: StringName in World.TYPE_ARRAYS + World.WEAPON_ARRAYS:  # One entry, not the size.
		var edited: World = _world()
		_edit_last(edited, table)
		assert_int(edited.defs_hash()).override_failure_message(table).is_not_equal(defs)
	for rule: StringName in World.RULE_SCALARS:
		var changed: World = _world()
		_poke(changed, rule)
		assert_int(changed.defs_hash()).override_failure_message(rule).is_not_equal(defs)
	for ids_name: StringName in [&"type_ids", &"weapon_ids"]:
		var renamed: World = _world()
		var ids: Array[StringName] = renamed.get(ids_name)
		ids[0] = &"renamed"
		assert_int(renamed.defs_hash()).override_failure_message(ids_name).is_not_equal(defs)


## controls_test with seed 1, at tick 0.
func _world() -> World:
	var scenario: ScenarioDef = load(SCENARIO_PATH) as ScenarioDef
	return World.from_scenario(scenario, DetRandom.create(1, DetRandom.STREAM_SIM))


## The perf arena: 64 x 64 tiles, 5 terrains.
func _arena() -> World:
	return World.from_scenario(load(ARENA_PATH) as ScenarioDef)


## A 5 x 4 tile world made by hand and not prepared: two units and the rule defaults.
func _hand_built() -> World:
	var world: World = World.new()
	world.map_w = 5000
	world.map_h = 4000
	world.add_unit(1, 0, 1500, 500)
	world.add_unit(2, 0, 3500, 2500)
	return world


## A world with a projectile in slot `slot` (every field set) and one slot fewer free.
func _with_projectile(slot: int) -> World:
	var world: World = _world()
	var value: int = 10
	for column_name: StringName in World.PROJECTILE_ARRAYS:
		if column_name != &"proj_free":
			var column: PackedInt32Array = world.get(column_name)
			column[slot] = value
			value += 1
	world.proj_free_top -= 1
	return world


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


## [object, label, HASHED, UNHASHED] of the fog, the cache, each of its slots and both grids.
func _helpers(world: World) -> Array[Array]:
	var helpers: Array[Array] = [[world.fog, "fog", FogGrid.HASHED, FogGrid.UNHASHED]]
	helpers.append([world.flow, "flow", FlowCache.HASHED, FlowCache.UNHASHED])
	for slot: int in world.flow.fields.size():
		var label: String = "flow.fields[%d]" % slot
		helpers.append([world.flow.fields[slot], label, FlowField.HASHED, FlowField.UNHASHED])
	helpers.append([world.sep_grid, "sep_grid", SpatialGrid.HASHED, SpatialGrid.UNHASHED])
	helpers.append([world.target_grid, "target_grid", SpatialGrid.HASHED, SpatialGrid.UNHASHED])
	return helpers


## Changes the last entry of the Packed array `member` of `object` and keeps its size.
func _edit_last(object: Object, member: StringName) -> void:
	var value: Variant = object.get(member)
	assert_int(value.size()).override_failure_message(member).is_greater(0)
	var last: int = value.size() - 1
	value[last] = value[last] + ("x" if value is PackedStringArray else 1)
	object.set(member, value)


## Changes `member` of `object`: an int by one, a bool flipped, a Packed array by one more entry.
func _poke(object: Object, member: StringName) -> void:
	var value: Variant = object.get(member)
	if value is bool:
		object.set(member, not value)
	elif value is int:
		object.set(member, value + 1)
	else:
		value.append("x" if value is PackedStringArray else 1)
		object.set(member, value)
