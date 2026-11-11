extends GdUnitTestSuite
## PlayerView v2 (plan row P172, ADR 0030 section 7): the type tables the managers read, the
## own-only charge and blackout getters, the pending ruptures every player sees and the rule caps.
## The strike rig of `strike_worlds.gd` gives a bore (charge 40, warning 12, radius 3000); every
## expected rule number comes from the World's tables.

const StrikeWorlds: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const ViewWorlds: GDScript = preload("res://tests/sim/support/view_worlds.gd")
const MISSING: int = PlayerView.MISSING
const TABLES: Array[StringName] = [
	&"type_max_hp",
	&"type_armour",
	&"type_range",
	&"type_min_range",
	&"type_sight",
	&"type_faction",
	&"type_strike_kind",
	&"type_strike_radius",
	&"type_charge_ticks",
	&"type_vs_armour",
	&"warned_x",
	&"warned_y",
	&"warned_tick",
]
## No table can hold it: the ticks are never negative and the "none" values are -1.
const SENTINEL: int = -7777


## Runs to the first tick the bore may fire and fires it at the rig's point.
func _fire(world: World) -> void:
	StrikeWorlds.run_to(world, StrikeWorlds.fire_tick(world, StrikeWorlds.BORE_A))
	StrikeWorlds.step(world, [StrikeWorlds.fire(StrikeWorlds.BORE_A)])


func test_each_new_table_is_a_copy_of_the_worlds() -> void:
	var world: World = StrikeWorlds.world()
	_fire(world)
	var state: int = world.state_hash()
	var defs: int = world.defs_hash()
	var max_hp: Array = Array(world.type_max_hp)
	var view: PlayerView = PlayerView.of(world, 1)
	var types: int = world.type_ids.size()
	for field: StringName in TABLES:
		var table: PackedInt32Array = view.get(field)
		assert_bool(table.size() > 0).override_failure_message(String(field)).is_true()
		var before: PackedInt32Array = table.duplicate()
		for at: int in table.size():
			table[at] += 1000
		# The write lands in the view's own array and in no World array.
		var again: PackedInt32Array = view.get(field)
		assert_int(again[0]).override_failure_message(String(field)).is_equal(table[0])
		assert_int(table[0]).is_equal(before[0] + 1000)
	assert_int(world.state_hash()).is_equal(state)
	assert_int(world.defs_hash()).is_equal(defs)
	assert_array(Array(world.type_max_hp)).is_equal(max_hp)
	var fresh: PlayerView = PlayerView.of(world, 1)
	assert_array(Array(fresh.type_max_hp)).is_equal(Array(world.type_max_hp))
	assert_array(Array(fresh.type_armour)).is_equal(Array(world.type_armour))
	assert_array(Array(fresh.type_sight)).is_equal(Array(world.type_sight))
	assert_array(Array(fresh.type_faction)).is_equal(Array(world.type_faction))
	assert_array(Array(fresh.type_strike_kind)).is_equal(Array(world.type_strike_kind))
	assert_array(Array(fresh.type_strike_radius)).is_equal(Array(world.type_strike_radius))
	assert_array(Array(fresh.type_charge_ticks)).is_equal(Array(world.type_charge_ticks))
	assert_int(fresh.type_range.size()).is_equal(types)
	assert_int(fresh.type_min_range.size()).is_equal(types)
	assert_int(fresh.type_vs_armour.size()).is_equal(types * PlayerView.ARMOUR_CLASSES)


func test_the_weapon_tables_read_through_each_types_weapon() -> void:
	var world: World = StrikeWorlds.world()
	var view: PlayerView = PlayerView.of(world, 1)
	var armed: int = 0
	for type: int in world.type_ids.size():
		var weapon: int = world.type_weapon[type]
		if weapon < 0 or weapon >= world.weapon_range.size():
			assert_int(view.type_range[type]).is_equal(0)
			assert_int(view.type_min_range[type]).is_equal(0)
			for armour: int in PlayerView.ARMOUR_CLASSES:
				assert_int(view.type_vs_armour[type * PlayerView.ARMOUR_CLASSES + armour]).is_equal(
					0
				)
			continue
		armed += 1
		assert_int(view.type_range[type]).is_equal(world.weapon_range[weapon])
		assert_int(view.type_min_range[type]).is_equal(world.weapon_min_range[weapon])
		for armour: int in PlayerView.ARMOUR_CLASSES:
			assert_int(view.type_vs_armour[type * PlayerView.ARMOUR_CLASSES + armour]).is_equal(
				world.weapon_vs_armour[weapon * PlayerView.ARMOUR_CLASSES + armour]
			)
	# The strike rig's units are unarmed. The view rig's rifle squad is armed, and gets a weapon of
	# its own here: a later index than its type, a minimum range, four distinct percents. The old
	# weapon stays behind as the decoy that a read by type index or a swapped class would pick up.
	var crafted: World = ViewWorlds.crafted()
	var rifle: int = crafted.type_ids.find(&"rifle_squad")
	var own_weapon: int = crafted.weapon_range.size()
	assert_int(crafted.weapon_vs_armour.size()).is_equal(own_weapon * PlayerView.ARMOUR_CLASSES)
	crafted.weapon_range.append(4321)
	crafted.weapon_min_range.append(1234)
	for armour: int in PlayerView.ARMOUR_CLASSES:
		crafted.weapon_vs_armour.append(11 + 7 * armour)
	crafted.type_weapon[rifle] = own_weapon
	assert_int(rifle).is_not_equal(own_weapon)
	var armed_view: PlayerView = PlayerView.of(crafted, 1)
	for type: int in crafted.type_ids.size():
		var weapon: int = crafted.type_weapon[type]
		if weapon < 0:
			continue
		armed += 1
		assert_int(armed_view.type_range[type]).is_equal(crafted.weapon_range[weapon])
		assert_int(armed_view.type_min_range[type]).is_equal(crafted.weapon_min_range[weapon])
		for armour: int in PlayerView.ARMOUR_CLASSES:
			(
				assert_int(armed_view.type_vs_armour[type * PlayerView.ARMOUR_CLASSES + armour])
				. is_equal(crafted.weapon_vs_armour[weapon * PlayerView.ARMOUR_CLASSES + armour])
			)
	assert_int(armed_view.type_range[rifle]).is_equal(4321)
	assert_int(armed_view.type_min_range[rifle]).is_equal(1234)
	for armour: int in PlayerView.ARMOUR_CLASSES:
		assert_int(armed_view.type_vs_armour[rifle * PlayerView.ARMOUR_CLASSES + armour]).is_equal(
			11 + 7 * armour
		)
	assert_bool(armed > 0).is_true()
	# The bore's rupture is a building's strike weapon, not its `type_weapon`; its kind, radius and
	# charge come through the strike tables.
	var bore: int = StrikeWorlds.type_of(world, "bore")
	assert_int(view.type_strike_kind[bore]).is_equal(world.type_strike_kind[bore])
	assert_int(view.type_strike_kind[bore]).is_not_equal(0)
	assert_int(view.type_strike_radius[bore]).is_equal(StrikeWorlds.radius_of(world, "bore"))
	assert_int(view.type_charge_ticks[bore]).is_equal(StrikeWorlds.charge_of(world, "bore"))
	var tank: int = StrikeWorlds.type_of(world, "tank")
	assert_int(view.type_armour[tank]).is_equal(World.Armour.HEAVY)
	assert_int(view.type_max_hp[tank]).is_equal(world.type_max_hp[tank])


func test_own_getters_answer_for_an_own_row_and_missing_for_a_seen_enemy() -> void:
	var world: World = ViewWorlds.crafted()
	var own: int = world.index_of(ViewWorlds.HQ_1)
	var foe: int = world.index_of(ViewWorlds.NEAR_FOE)
	world.ready_tick[own] = 120
	world.offline_until[own] = 240
	world.ready_tick[foe] = SENTINEL
	world.offline_until[foe] = SENTINEL + 1
	var view: PlayerView = PlayerView.of(world, 1)
	assert_bool(view.seen_rows.has(foe)).is_true()
	assert_int(view.row_ready_tick(own)).is_equal(120)
	assert_int(view.row_offline_until(own)).is_equal(240)
	assert_int(view.row_ready_tick(foe)).is_equal(MISSING)
	assert_int(view.row_offline_until(foe)).is_equal(MISSING)
	for row: int in [-1, world.unit_id.size(), 1 << 40]:
		assert_int(view.row_ready_tick(row)).is_equal(MISSING)
		assert_int(view.row_offline_until(row)).is_equal(MISSING)


func test_own_getters_hide_a_seen_enemy_strike_building_a_blackout_and_a_neutral_row() -> void:
	var world: World = StrikeWorlds.world()
	var enemy_bore: int = world.index_of(
		world.add_building(2, StrikeWorlds.type_of(world, "bore"), 20, 4)
	)
	var neutral: int = world.index_of(StrikeWorlds.add(world, 0, "rifle", 12500, 12500))
	var own: int = world.index_of(StrikeWorlds.BORE_A)
	world.ready_tick[enemy_bore] = SENTINEL
	world.offline_until[enemy_bore] = SENTINEL - 1
	world.ready_tick[neutral] = SENTINEL - 2
	world.offline_until[neutral] = SENTINEL - 3
	var view: PlayerView = PlayerView.of(world, 1)
	# The map is revealed: both rows are seen, so only the owner test keeps their numbers back.
	assert_bool(view.seen_rows.has(enemy_bore)).is_true()
	assert_bool(view.seen_rows.has(neutral)).is_true()
	assert_int(view.row_ready_tick(own)).is_equal(world.ready_tick[own])
	for row: int in [enemy_bore, neutral]:
		assert_int(view.row_ready_tick(row)).is_equal(MISSING)
		assert_int(view.row_offline_until(row)).is_equal(MISSING)
	# A neutral row the viewer does not see answers the same.
	var crafted: World = ViewWorlds.crafted()
	var far: int = crafted.index_of(ViewWorlds.FAR_NEUTRAL)
	crafted.ready_tick[far] = SENTINEL
	crafted.offline_until[far] = SENTINEL
	var crafted_view: PlayerView = PlayerView.of(crafted, 1)
	assert_int(crafted_view.row_ready_tick(far)).is_equal(MISSING)
	assert_int(crafted_view.row_offline_until(far)).is_equal(MISSING)


func test_hidden_rows_expose_nothing_and_no_public_field_carries_an_enemys_charge() -> void:
	var world: World = ViewWorlds.crafted()
	var hidden: int = world.index_of(ViewWorlds.FAR_FOE)
	var seen: int = world.index_of(ViewWorlds.NEAR_FOE)
	world.ready_tick[hidden] = SENTINEL
	world.offline_until[hidden] = SENTINEL
	world.ready_tick[seen] = SENTINEL
	world.offline_until[seen] = SENTINEL
	var view: PlayerView = PlayerView.of(world, 1)
	assert_bool(view.own_rows.has(hidden) or view.seen_rows.has(hidden)).is_false()
	assert_int(view.row_ready_tick(hidden)).is_equal(MISSING)
	assert_int(view.row_offline_until(hidden)).is_equal(MISSING)
	for property: Dictionary in view.get_property_list():
		var field: StringName = StringName(property["name"])
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or field.begins_with("_"):
			continue
		var value: Variant = view.get(field)
		if value is PackedInt32Array:
			var column: PackedInt32Array = value
			assert_bool(column.has(SENTINEL)).override_failure_message(String(field)).is_false()


func test_warned_ruptures_list_exactly_the_pending_strikes_of_every_player() -> void:
	_check_warned(StrikeWorlds.world(true, 3))


## The same with the fog real: a rupture outside the viewer's sight is listed all the same (ADR
## 0023 section 10: the fog does not hide the warning).
func test_warned_ruptures_are_listed_through_the_fog() -> void:
	var world: World = StrikeWorlds.world(false, 3)
	var hidden: int = 0
	for who: int in [1, 2, 3]:
		if not Targeting.sees(world, who, StrikeWorlds.POINT.x, StrikeWorlds.POINT.y):
			hidden += 1
		if not Targeting.sees(world, who, 4500, 5500):
			hidden += 1
	assert_bool(hidden > 0).override_failure_message("a point must be dark to someone").is_true()
	_check_warned(world)


func _check_warned(world: World) -> void:
	var view: PlayerView = PlayerView.of(world, 2)
	assert_int(view.warned_x.size()).is_equal(0)
	assert_int(view.warned_y.size()).is_equal(0)
	assert_int(view.warned_tick.size()).is_equal(0)
	# Player 1 fires for real; player 3 has a rupture written in by hand, and so has the neutral
	# player 0, which the list leaves out.
	_fire(world)
	var landing: int = world.strike_tick[1]
	assert_int(landing).is_greater(0)
	world.strike_x[3] = 4500
	world.strike_y[3] = 5500
	world.strike_tick[3] = landing + 5
	world.strike_x[0] = 7500
	world.strike_y[0] = 8500
	world.strike_tick[0] = landing + 9
	for who: int in [1, 2, 3]:
		var seen_by: PlayerView = PlayerView.of(world, who)
		assert_array(Array(seen_by.warned_x)).is_equal([StrikeWorlds.POINT.x, 4500])
		assert_array(Array(seen_by.warned_y)).is_equal([StrikeWorlds.POINT.y, 5500])
		assert_array(Array(seen_by.warned_tick)).is_equal([landing, landing + 5])
	# Once the first has landed (strike_tick back to 0) only the second is listed.
	StrikeWorlds.run_to(world, landing)
	var after: PlayerView = PlayerView.of(world, 2)
	assert_int(world.strike_tick[1]).is_equal(0)
	assert_array(Array(after.warned_tick)).is_equal([landing + 5])
	assert_array(Array(after.warned_x)).is_equal([4500])


func test_own_strike_tick_is_the_viewers_own_pending_landing_and_never_anothers() -> void:
	var world: World = StrikeWorlds.world(true, 3)
	for who: int in [0, 1, 2, 3]:
		assert_int(PlayerView.of(world, who).own_strike_tick).is_equal(0)
	_fire(world)
	var landing: int = world.strike_tick[1]
	assert_int(landing).is_greater(0)
	assert_int(PlayerView.of(world, 1).own_strike_tick).is_equal(landing)
	assert_int(PlayerView.of(world, 2).own_strike_tick).is_equal(0)
	assert_int(PlayerView.of(world, 3).own_strike_tick).is_equal(0)
	assert_int(PlayerView.of(world, 0).own_strike_tick).is_equal(0)
	world.strike_tick[3] = landing + 5
	assert_int(PlayerView.of(world, 1).own_strike_tick).is_equal(landing)
	assert_int(PlayerView.of(world, 2).own_strike_tick).is_equal(0)
	assert_int(PlayerView.of(world, 3).own_strike_tick).is_equal(landing + 5)
	StrikeWorlds.run_to(world, landing - 1)  # The boundary: still pending one step before landing.
	assert_int(PlayerView.of(world, 1).own_strike_tick).is_equal(landing)
	StrikeWorlds.run_to(world, landing)
	assert_int(PlayerView.of(world, 1).own_strike_tick).is_equal(0)
	assert_int(PlayerView.of(world, 3).own_strike_tick).is_equal(landing + 5)


func test_the_armour_width_is_the_worlds_class_count() -> void:
	assert_int(PlayerView.ARMOUR_CLASSES).is_equal(World.Armour.size())


func test_the_rule_caps_come_from_the_world() -> void:
	var world: World = StrikeWorlds.world()
	world.unit_cap = 31
	world.building_cap = 17
	var view: PlayerView = PlayerView.of(world, 1)
	assert_int(view.unit_cap).is_equal(31)
	assert_int(view.building_cap).is_equal(17)
	world.unit_cap = 99
	assert_int(view.unit_cap).is_equal(31)


## `type_range`, `type_min_range` and `type_vs_armour` read through a type's weapon, and a weapon
## past a table's end reads as 0 there (plan row P198 rewrote the guards): one type's weapon is
## exactly one past the range table, and another's minimum range and armour table are cut short.
func test_a_weapon_past_the_end_of_a_table_reads_as_zero() -> void:
	var world: World = ViewWorlds.crafted()
	var armed: Array[int] = []
	for type: int in world.type_weapon.size():
		if world.type_weapon[type] >= 0:
			armed.append(type)
	assert_array(armed).is_not_empty()
	var short: int = armed[0]
	var past: int = (short + 1) % world.type_weapon.size()
	var weapon: int = world.type_weapon[short]
	world.type_weapon[past] = world.weapon_range.size()
	# The second weapon has a range but no minimum range, and only 2 of its 4 armour entries.
	world.weapon_min_range.resize(weapon)
	world.weapon_vs_armour.resize(weapon * PlayerView.ARMOUR_CLASSES + 2)
	var kept: Array[int] = [
		world.weapon_vs_armour[weapon * PlayerView.ARMOUR_CLASSES],
		world.weapon_vs_armour[weapon * PlayerView.ARMOUR_CLASSES + 1],
	]
	var view: PlayerView = PlayerView.of(world, 1)
	assert_int(view.type_range[past]).is_equal(0)
	assert_int(view.type_min_range[past]).is_equal(0)
	for armour: int in PlayerView.ARMOUR_CLASSES:
		assert_int(view.type_vs_armour[past * PlayerView.ARMOUR_CLASSES + armour]).is_equal(0)
	assert_int(view.type_range[short]).is_equal(world.weapon_range[weapon])
	assert_int(view.type_min_range[short]).is_equal(0)
	var at: int = short * PlayerView.ARMOUR_CLASSES
	assert_array([view.type_vs_armour[at], view.type_vs_armour[at + 1]]).is_equal(kept)
	assert_int(view.type_vs_armour[at + 2]).is_equal(0)
	assert_int(view.type_vs_armour[at + 3]).is_equal(0)
