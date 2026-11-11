extends GdUnitTestSuite
## The type tables that the views of a match take from one holder (plan row P198c, ADR 0020 section
## 1's note): the World keeps one `TypeTables` holder, made by the first view, and every view's
## `type_*` fields are copies of its arrays. The views of one match share the holder's contents and
## never its arrays, two matches never share a holder, a write through a view's table reaches
## neither a fresh view, the holder, the World nor another match, and building the holder changes
## nothing the state hash reads. The perf_ai workload's own check (the holder still equals the
## World's tables after 900 ticks of two AIs) is in tests/perf/support/ai_perf_run.gd.

const ViewWorlds: GDScript = preload("res://tests/sim/support/view_worlds.gd")
const Check: GDScript = preload("res://tests/sim/support/type_tables_check.gd")


## The view's public type tables, by name, from the script's own variables.
func _view_tables() -> Array[String]:
	return Check.view_tables()


## A hand-built World with three types and only some of the type tables filled, not prepared:
## `prepare()` pads the rest to the type count.
func _unprepared() -> World:
	var world: World = World.new()
	world.map_w = 8000
	world.map_h = 8000
	world.player_count = 2
	world.type_ids = [&"a", &"b", &"c"]
	world.type_cost = PackedInt32Array([10, 20, 30])
	world.type_speed = PackedInt32Array([0, 100, 100])
	return world


## One more type in every per-type table of `world`, and its id.
func _add_type(world: World) -> void:
	world.type_ids.append(&"late")
	for name: StringName in World.TYPE_ARRAYS:
		var table: Variant = world.get(name)
		table.resize(table.size() + 1)


func test_a_world_has_no_holder_until_its_first_view_and_every_view_then_shares_it() -> void:
	var world: World = ViewWorlds.crafted()
	assert_object(world.type_tables).is_null()
	var first: PlayerView = PlayerView.of(world, 1)
	var held: TypeTables = world.type_tables
	assert_object(held).is_not_null()
	assert_object(first._tables).is_same(held)
	for player: int in [0, 1, 2]:
		assert_object(PlayerView.of(world, player)._tables).is_same(held)
	assert_object(world.type_tables).is_same(held)


func test_two_worlds_never_share_a_holder() -> void:
	var one: World = ViewWorlds.crafted()
	var other: World = ViewWorlds.crafted()
	var view_one: PlayerView = PlayerView.of(one, 1)
	var view_other: PlayerView = PlayerView.of(other, 1)
	assert_object(view_one._tables).is_not_same(view_other._tables)
	assert_object(one.type_tables).is_not_same(other.type_tables)
	# Equal tables, but two sets of arrays: a write to one holder's is not the other's.
	assert_array(Check.differences(one.type_tables, other.type_tables)).is_empty()
	one.type_tables.cost[0] += 1
	assert_array(Check.differences(one.type_tables, other.type_tables)).is_equal(["cost"])


func test_the_holder_holds_the_worlds_tables_and_the_view_fields_are_copies_of_its_arrays() -> void:
	var world: World = ViewWorlds.crafted()
	var view: PlayerView = PlayerView.of(world, 1)
	assert_array(Check.differences(world.type_tables, TypeTables.of(world))).is_empty()
	var held: TypeTables = world.type_tables
	var tables: Array[String] = _view_tables()
	# Every holder table has a view table and the reverse: three fields more (docks, ids), which the
	# view reads through `type_index_of` and `is_refinery`.
	assert_int(tables.size() + 3).is_equal(Check.fields().size())
	assert_int(tables.size()).is_equal(21)
	for name: String in tables:
		var field: String = Check.holder_field(name)
		assert_bool(Check.fields().has(field)).override_failure_message(name).is_true()
		var table: PackedInt32Array = view.get(name)
		var source: PackedInt32Array = held.get(field)
		assert_array(table).override_failure_message(name).is_equal(source)
		assert_bool(table.is_empty()).override_failure_message(name).is_false()
		# A copy of the holder's array, not the array: a write moves only the view's.
		table[0] += 1
		assert_bool(table == source).override_failure_message(name).is_false()
		table[0] -= 1
	assert_int(view.unit_cap).is_equal(world.unit_cap)


## A view's tables are its own copies (plan row P198c: GDScript shares a packed array by assignment,
## so the view takes a `duplicate()` of each). A write through any of them, in place or by fill,
## resize or clear, shows in no fresh view, not in the holder, not in the World and not in another
## match.
func test_a_write_through_a_views_tables_reaches_no_fresh_view_holder_world_or_match() -> void:
	var world: World = ViewWorlds.crafted()
	var other: World = ViewWorlds.crafted()
	PlayerView.of(other, 1)
	var other_kept: TypeTables = TypeTables.of(other)
	var kept: TypeTables = TypeTables.of(world)
	var world_hash: int = world.state_hash()
	var view: PlayerView = PlayerView.of(world, 1)
	var held: TypeTables = world.type_tables
	for name: String in _view_tables():
		var table: PackedInt32Array = view.get(name)
		table[0] = table[0] + 12345
	view.type_cost.fill(-5)
	view.type_vs_armour.resize(1)
	view.type_range.clear()
	assert_int(view.type_cost[0]).is_equal(-5)
	assert_array(Check.differences(held, kept)).is_empty()
	assert_array(Check.differences(TypeTables.of(world), kept)).is_empty()
	assert_array(world.type_cost).is_equal(kept.cost)
	assert_array(world.type_weapon).is_equal(kept.weapon)
	assert_int(world.state_hash()).is_equal(world_hash)
	var fresh: PlayerView = PlayerView.of(world, 2)
	assert_object(world.type_tables).is_same(held)
	for name: String in _view_tables():
		var got: PackedInt32Array = fresh.get(name)
		assert_bool(got.size() > 1).override_failure_message(name).is_true()
	assert_array(fresh.type_cost).is_equal(kept.cost)
	assert_array(fresh.type_vs_armour).is_equal(kept.vs_armour)
	assert_array(fresh.type_range).is_equal(kept.weapon_range)
	assert_array(Check.differences(other.type_tables, other_kept)).is_empty()
	var other_view: PlayerView = PlayerView.of(other, 2)
	assert_array(other_view.type_cost).is_equal(other_kept.cost)


## The holder is a copy of every table of the World: a write to the World after the first view
## reaches none of them (the tables are fixed once a match runs; a test that writes one clears
## `world.type_tables`).
func test_a_write_to_the_world_after_the_first_view_reaches_no_table_of_the_holder() -> void:
	var world: World = ViewWorlds.crafted()
	PlayerView.of(world, 1)
	var held: TypeTables = world.type_tables
	var checked: int = 0
	for field: String in Check.fields():
		var table: Variant = world.get("type_" + field)
		if not table is PackedInt32Array or table.is_empty():
			continue
		var before: int = held.get(field)[0]
		table[0] = before + 9
		assert_int(world.get("type_" + field)[0]).override_failure_message(field).is_equal(
			before + 9
		)
		assert_int(held.get(field)[0]).override_failure_message(field).is_equal(before)
		checked += 1
	# The 20 tables of the World that the holder copies as they are (the 18 and the two docks); the
	# three weapon tables are derived, the ids are not an int table.
	assert_int(checked).is_equal(Check.fields().size() - 4)


## Each view table is its own World table, not a neighbour: a World whose tables hold distinct
## numbers per table and per type (and a footprint that is not square) is read through a view, and
## every `type_*` field must equal its World table element by element. The three weapon tables are
## read through each type's weapon: the expected values are worked out here, per type.
func test_every_view_table_equals_its_own_world_table_on_distinct_numbers() -> void:
	var world: World = ViewWorlds.crafted()
	var types: int = world.type_ids.size()
	var weapons: int = world.weapon_range.size()
	var number: int = 0
	var direct: Array[String] = []
	for field: String in Check.fields():
		var table: Variant = world.get("type_" + field)
		if not table is PackedInt32Array or field == "weapon":
			continue
		number += 1
		for type: int in table.size():
			table[type] = 1000 * number + 7 * type + 3
		direct.append(field)
	for type: int in types:
		world.type_weapon[type] = type % (weapons + 1) - 1
	world.weapon_range.resize(weapons)
	world.weapon_min_range.resize(weapons)
	world.weapon_vs_armour.resize(weapons * PlayerView.ARMOUR_CLASSES)
	for weapon: int in weapons:
		world.weapon_range[weapon] = 50000 + 11 * weapon
		world.weapon_min_range[weapon] = 60000 + 13 * weapon
	for at: int in world.weapon_vs_armour.size():
		world.weapon_vs_armour[at] = 70000 + 17 * at
	world.type_tables = null
	var view: PlayerView = PlayerView.of(world, 1)
	# No two direct tables hold the same numbers, so a table read from its neighbour shows.
	assert_bool(direct.size() > 15).is_true()
	for first: int in direct.size():
		for second: int in range(first + 1, direct.size()):
			var one: PackedInt32Array = world.get("type_" + direct[first])
			var two: PackedInt32Array = world.get("type_" + direct[second])
			assert_bool(one == two).override_failure_message(direct[first]).is_false()
	for name: String in Check.view_tables():
		var got: PackedInt32Array = view.get(name)
		var want: PackedInt32Array = PackedInt32Array()
		match name:
			"type_range", "type_min_range", "type_vs_armour":
				want = _derived(world, name)
			_:
				want = world.get(name)
		assert_int(want.size()).override_failure_message(name).is_greater(1)
		assert_array(got).override_failure_message(name).is_equal(want)


## The weapon-derived table `name` of `world`, type by type through the type's weapon (0 for none).
func _derived(world: World, name: String) -> PackedInt32Array:
	var width: int = PlayerView.ARMOUR_CLASSES if name == "type_vs_armour" else 1
	var made: PackedInt32Array = PackedInt32Array()
	made.resize(world.type_ids.size() * width)
	for type: int in world.type_ids.size():
		var weapon: int = world.type_weapon[type]
		if weapon < 0:
			continue
		for at: int in width:
			match name:
				"type_range":
					made[type] = world.weapon_range[weapon]
				"type_min_range":
					made[type] = world.weapon_min_range[weapon]
				_:
					made[type * width + at] = world.weapon_vs_armour[weapon * width + at]
	return made


## A World whose type count changes after a view gets a fresh holder with the new count in every
## table. Each table of the view holds one entry more.
func test_a_world_that_gains_a_type_after_a_view_gets_a_fresh_holder() -> void:
	var world: World = ViewWorlds.crafted()
	var old: TypeTables = PlayerView.of(world, 1)._tables
	var types: int = world.type_ids.size()
	_add_type(world)
	assert_int(world.type_cost.size()).is_equal(types + 1)
	var view: PlayerView = PlayerView.of(world, 1)
	assert_object(view._tables).is_not_same(old)
	assert_object(world.type_tables).is_same(view._tables)
	for name: String in _view_tables():
		var table: PackedInt32Array = view.get(name)
		var per: int = PlayerView.ARMOUR_CLASSES if name == "type_vs_armour" else 1
		assert_int(table.size()).override_failure_message(name).is_equal((types + 1) * per)


## An unprepared World gets a throwaway holder, so the tables that `prepare()` pads afterwards are
## read fresh: the second view holds every table at the full type count.
func test_an_unprepared_world_is_not_cached_and_reads_the_padded_tables_once_prepared() -> void:
	var world: World = _unprepared()
	var types: int = world.type_ids.size()
	var early: PlayerView = PlayerView.of(world, 1)
	assert_object(world.type_tables).is_null()
	var short: int = 0
	for name: String in _view_tables():
		var table: PackedInt32Array = early.get(name)
		short += 1 if table.size() < types else 0
	# The case is real only if some table was short before `prepare()`.
	assert_bool(short > 0).is_true()
	world.prepare()
	var view: PlayerView = PlayerView.of(world, 1)
	assert_object(world.type_tables).is_not_null()
	for name: String in _view_tables():
		var table: PackedInt32Array = view.get(name)
		var per: int = PlayerView.ARMOUR_CLASSES if name == "type_vs_armour" else 1
		assert_int(table.size()).override_failure_message(name).is_equal(types * per)


func test_building_the_holder_does_not_touch_the_state_hash() -> void:
	var world: World = ViewWorlds.crafted()
	var before: int = world.state_hash()
	var defs: int = world.defs_hash()
	PlayerView.of(world, 1)
	assert_object(world.type_tables).is_not_null()
	assert_int(world.state_hash()).is_equal(before)
	assert_int(world.defs_hash()).is_equal(defs)
