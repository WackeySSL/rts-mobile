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
## The view's public type tables, by name.
const VIEW_TABLES: Array[String] = [
	"type_cost",
	"type_tab",
	"type_requires",
	"type_produces",
	"type_foot_w",
	"type_foot_h",
	"type_speed",
	"type_weapon",
	"type_harvest",
	"type_power",
	"type_build_ticks",
	"type_max_hp",
	"type_armour",
	"type_range",
	"type_min_range",
	"type_sight",
	"type_faction",
	"type_strike_kind",
	"type_strike_radius",
	"type_charge_ticks",
	"type_vs_armour",
]


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
	var wanted: Array[PackedInt32Array] = [
		held.cost,
		held.tab,
		held.requires,
		held.produces,
		held.foot_w,
		held.foot_h,
		held.speed,
		held.weapon,
		held.harvest,
		held.power,
		held.build_ticks,
		held.max_hp,
		held.armour,
		held.weapon_range,
		held.weapon_min_range,
		held.sight,
		held.faction,
		held.strike_kind,
		held.strike_radius,
		held.charge_ticks,
		held.vs_armour,
	]
	for at: int in VIEW_TABLES.size():
		var table: PackedInt32Array = view.get(VIEW_TABLES[at])
		assert_array(table).override_failure_message(VIEW_TABLES[at]).is_equal(wanted[at])
		assert_bool(table.is_empty()).override_failure_message(VIEW_TABLES[at]).is_false()
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
	for name: String in VIEW_TABLES:
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
	for name: String in VIEW_TABLES:
		var got: PackedInt32Array = fresh.get(name)
		assert_bool(got.size() > 1).override_failure_message(name).is_true()
	assert_array(fresh.type_cost).is_equal(kept.cost)
	assert_array(fresh.type_vs_armour).is_equal(kept.vs_armour)
	assert_array(fresh.type_range).is_equal(kept.weapon_range)
	assert_array(Check.differences(other.type_tables, other_kept)).is_empty()
	var other_view: PlayerView = PlayerView.of(other, 2)
	assert_array(other_view.type_cost).is_equal(other_kept.cost)


func test_a_write_to_the_world_after_the_first_view_is_not_seen_by_the_holder_alone() -> void:
	# The tables are fixed once a match runs; the holder is a copy, so the World's own write does
	# not move it (and a later view that builds a fresh holder would see the write).
	var world: World = ViewWorlds.crafted()
	var before: int = PlayerView.of(world, 1).type_cost[0]
	world.type_cost[0] = before + 9
	assert_int(world.type_tables.cost[0]).is_equal(before)


func test_a_world_that_gains_a_type_after_a_view_gets_a_fresh_holder() -> void:
	var world: World = ViewWorlds.crafted()
	var old: TypeTables = PlayerView.of(world, 1)._tables
	world.type_ids.append(&"late")
	world.type_cost.append(5)
	var view: PlayerView = PlayerView.of(world, 1)
	assert_object(view._tables).is_not_same(old)
	assert_int(view.type_cost.size()).is_equal(world.type_cost.size())


func test_building_the_holder_does_not_touch_the_state_hash() -> void:
	var world: World = ViewWorlds.crafted()
	var before: int = world.state_hash()
	var defs: int = world.defs_hash()
	PlayerView.of(world, 1)
	assert_object(world.type_tables).is_not_null()
	assert_int(world.state_hash()).is_equal(before)
	assert_int(world.defs_hash()).is_equal(defs)
