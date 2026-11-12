extends GdUnitTestSuite
## The opponent AI's data (plan row P175, ADR 0030 section 6): the three difficulty files, the two
## `OpponentDef` files and the six build orders in `data/ai/`. The numbers are pinned as the ADR
## states them, every type id is a type of the def's own faction with its requirement before it,
## each build order can be built in order, the weak tier has no radar, only the strong tier has a
## strike building, the ignored inherited fields of `AiDef` are at their defaults, and the script
## defaults equal the files (Normal's, the fossil file's).

const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const FACTION_PATHS: Dictionary[String, String] = {
	"fossil": "res://data/factions/fossil.tres", "renew": "res://data/factions/renew.tres"
}
const UNIT_DIR: String = "res://data/units/"
const FROZEN_UNIT_DIR: String = "res://data/dev/arena/units/"
const TIER_NAMES: Array[String] = ["weak", "standard", "strong"]
## The fields that are off by default, with their script defaults (P274): the frozen arena's level
## files name none of them, so they play as before; the shipped files turn them on.
const _OFF_BY_DEFAULT: Dictionary[String, int] = {"mend_below_percent": 0, "mend_floor": 0}
## ADR 0030 section 6's table (its two mend rows from P274, ADR 0037 section 4): per level, in the
## field order of `_LEVEL_FIELDS`.
const _LEVEL_FIELDS: Array[String] = [
	"build_order_tier",
	"reaction_ticks",
	"harvesters_per_refinery",
	"refineries_max",
	"factories_max",
	"defences_max",
	"scout_first_tick",
	"scout_interval_ticks",
	"wave_first_tick",
	"wave_first_strength",
	"wave_growth_percent",
	"wave_jitter_ticks",
	"all_in_tick",
	"retreat_percent",
	"retreat_ratio_percent",
	"unit_retreat_hp_percent",
	"focus_fire",
	"counter_percent",
	"uses_strike",
	"mend_below_percent",
	"mend_floor",
	"commands_per_think_max",
	"income_percent",
]
const _LEVELS: Dictionary[String, Array] = {
	"easy": [0, 90, 1, 1, 1, 1, 0, 0, 6300, 2000, 10, 450, 12600, 0, 0, 0, 0, 0, 0, 0, 0, 3, 100],
	"normal":
	[
		1,
		30,
		2,
		2,
		1,
		2,
		1800,
		2700,
		4050,
		4000,
		25,
		300,
		10800,
		40,
		200,
		0,
		0,
		30,
		1,
		50,
		400,
		8,
		100
	],
	"hard":
	[
		2,
		15,
		2,
		2,
		2,
		3,
		1350,
		1800,
		3600,
		5000,
		30,
		150,
		9900,
		50,
		150,
		30,
		1,
		60,
		1,
		70,
		250,
		12,
		100
	],
}


func test_each_level_file_has_the_numbers_of_the_adr(
	level: String, _test_parameters := _levels()
) -> void:
	var def: AiDifficultyDef = Rig.level_of(level)
	assert_object(def).is_not_null()
	assert_str(String(def.id)).is_equal(level)
	var found: Array = []
	for field: String in _LEVEL_FIELDS:
		found.append(def.get(field))
	assert_array(found).is_equal(_LEVELS[level])


func test_easy_never_uses_the_strike_and_no_level_gets_a_money_bonus() -> void:
	assert_array([Rig.level_of("easy").uses_strike, Rig.level_of("normal").uses_strike]).is_equal(
		[0, 1]
	)
	for level: String in Rig.LEVELS:
		assert_int(Rig.level_of(level).income_percent).is_equal(100)


func test_the_script_defaults_of_a_level_are_normals_file() -> void:
	var skip: Array[String] = []
	skip.assign(_OFF_BY_DEFAULT.keys())
	_assert_defaults_equal(AiDifficultyDef.new(), Rig.level_of("normal"), skip)


func test_the_off_by_default_fields_default_off_and_normals_file_turns_them_on() -> void:
	var fresh: AiDifficultyDef = AiDifficultyDef.new()
	var normal: AiDifficultyDef = Rig.level_of("normal")
	for field: String in _OFF_BY_DEFAULT:
		assert_int(fresh.get(field)).is_equal(_OFF_BY_DEFAULT[field])
		(
			assert_bool(normal.get(field) != _OFF_BY_DEFAULT[field])
			. override_failure_message("Normal's %s equals its default" % field)
			. is_true()
		)


func test_the_script_defaults_of_an_opponent_def_are_the_fossil_file() -> void:
	_assert_defaults_equal(OpponentDef.new(), Rig.def_of("fossil"), ["id", "build_orders"])


func test_the_opponent_files_hold_the_numbers_of_the_adr(
	faction: String, _test_parameters := _factions()
) -> void:
	var def: OpponentDef = Rig.def_of(faction)
	assert_str(String(def.id)).is_equal("opponent_" + faction)
	assert_array([def.think_period, def.think_tick]).is_equal([5, 6])
	(
		assert_array(
			[
				def.power_margin,
				def.staging_offset_tiles,
				def.unseen_hit_shift_tiles,
				def.sector_tiles,
				def.sectors_max,
				def.squads_max,
				def.place_tries_per_think,
				def.target_tests_max,
				def.goal_keys_max,
				def.spiral_slots,
				def.strike_min_value
			]
		)
		. is_equal([20, 6, 4, 8, 64, 4, 8, 512, 4, 64, 3000])
	)


func test_the_ignored_inherited_fields_are_at_their_script_defaults(
	faction: String, _test_parameters := _factions()
) -> void:
	var def: OpponentDef = Rig.def_of(faction)
	var base: AiDef = AiDef.new()
	assert_array(def.build_order).is_equal(base.build_order)
	assert_array([def.place_tries, def.harvesters_wanted, def.guard_offset_tiles]).is_equal(
		[base.place_tries, base.harvesters_wanted, base.guard_offset_tiles]
	)


func test_every_type_of_the_def_is_a_type_of_its_faction_and_of_the_frozen_arena(
	faction: String, _test_parameters := _factions()
) -> void:
	var def: OpponentDef = Rig.def_of(faction)
	var own: Array[StringName] = _ids_of(load(FACTION_PATHS[faction]) as FactionDef)
	var other: Array[StringName] = _ids_of(
		load(FACTION_PATHS["renew" if faction == "fossil" else "fossil"]) as FactionDef
	)
	for id: StringName in _all_types(def):
		assert_array(own).override_failure_message(String(id)).contains([id])
		assert_array(other).not_contains([id])
		var unit: UnitDef = load(UNIT_DIR + String(id) + ".tres") as UnitDef
		assert_str(String(unit.faction)).is_equal(faction)
		assert_bool(FileAccess.file_exists(FROZEN_UNIT_DIR + String(id) + ".tres")).is_true()


func test_the_role_types_are_of_the_right_kind(
	faction: String, _test_parameters := _factions()
) -> void:
	var def: OpponentDef = Rig.def_of(faction)
	assert_int(_building(def.hq_type).produces).is_equal(World.Tab.STRUCTURES)
	assert_int(_unit(def.harvester_type).harvest_capacity).is_greater(0)
	var units: Array[StringName] = [def.scout_type, def.anti_infantry_type, def.tank_type]
	units.append_array(def.anti_vehicle_types)
	units.append(def.artillery_type)
	for id: StringName in units:
		assert_int(_unit(id).tab).is_in([World.Tab.INFANTRY, World.Tab.VEHICLES])
		assert_object(_unit(id).weapon).override_failure_message(String(id)).is_not_null()
	for id: StringName in [def.defence_type, def.strike_type]:
		assert_int(_unit(id).tab).is_equal(World.Tab.STRUCTURES)
	assert_int(_building(def.strike_type).strike_kind).is_greater(0)
	assert_object(_building(def.defence_type).weapon).is_not_null()


func test_each_tier_has_one_build_order_buildable_in_order(
	faction: String, _test_parameters := _factions()
) -> void:
	var def: OpponentDef = Rig.def_of(faction)
	assert_int(def.build_orders.size()).is_equal(OpponentDef.TIERS)
	for tier: int in OpponentDef.TIERS:
		var order: AiBuildOrderDef = def.build_orders[tier]
		assert_int(order.tier).is_equal(tier)
		assert_str(String(order.id)).is_equal("%s_%s" % [faction, TIER_NAMES[tier]])
		assert_array(order.steps).is_not_empty()
		var earlier: Array[StringName] = [def.hq_type]
		for id: StringName in order.steps:
			var unit: UnitDef = _unit(id)
			assert_int(unit.tab).is_equal(World.Tab.STRUCTURES)
			assert_int(unit.cost).is_greater(0)
			var needs: StringName = unit.requires.type_id if unit.requires != null else &""
			(
				assert_bool(unit.requires == null or earlier.has(needs))
				. override_failure_message("%s needs %s before it" % [id, needs])
				. is_true()
			)
			earlier.append(id)


func test_only_the_strong_tier_has_the_strike_and_only_the_weak_tier_has_no_radar(
	faction: String, _test_parameters := _factions()
) -> void:
	var def: OpponentDef = Rig.def_of(faction)
	var radar: StringName = _unit(def.strike_type).requires.type_id
	var weak: Array[StringName] = def.build_orders[0].steps
	assert_array(weak).not_contains([def.strike_type, radar])
	assert_int(def.role_weight(0, OpponentDef.Role.ARTILLERY)).is_equal(0)
	# The artillery needs the radar, so a tier that builds it may draw it.
	assert_str(String(_unit(def.artillery_type).requires.type_id)).is_equal(String(radar))
	# P192b: the standard tier keeps the radar (the artillery needs it) but drops the strike
	# building, 2500 credits fired about 0.1 times a match; the strong tier keeps both.
	for tier: int in [1, 2]:
		var steps: Array[StringName] = def.build_orders[tier].steps
		assert_array(steps).contains([radar])
		assert_int(steps.count(def.strike_type)).is_equal(1 if tier == 2 else 0)
		assert_int(def.role_weight(tier, OpponentDef.Role.ARTILLERY)).is_greater(0)


func test_the_strong_tier_builds_the_factory_and_second_refinery_earlier(
	faction: String, _test_parameters := _factions()
) -> void:
	var def: OpponentDef = Rig.def_of(faction)
	var factory: StringName = &"vehicle_factory" if faction == "fossil" else &"renew_factory"
	var standard: int = def.build_orders[1].steps.find(factory)
	var strong: int = def.build_orders[2].steps.find(factory)
	assert_int(strong).is_between(0, standard - 1)
	var refinery: StringName = &"refinery" if faction == "fossil" else &"renew_refinery"
	assert_int(def.build_orders[1].steps.count(refinery)).is_equal(1)
	assert_int(def.build_orders[2].steps.count(refinery)).is_equal(2)
	assert_int(def.build_orders[0].steps.count(refinery)).is_equal(1)


func test_every_role_with_weight_has_its_producer_and_requirement_in_the_tiers_steps(
	faction: String, _test_parameters := _factions()
) -> void:
	var def: OpponentDef = Rig.def_of(faction)
	var roles: Dictionary[int, Array] = {
		OpponentDef.Role.ANTI_INFANTRY: [def.anti_infantry_type],
		OpponentDef.Role.ANTI_VEHICLE: def.anti_vehicle_types,
		OpponentDef.Role.TANK: [def.tank_type],
		OpponentDef.Role.ARTILLERY: [def.artillery_type],
	}
	for tier: int in OpponentDef.TIERS:
		var built: Array[StringName] = [def.hq_type]
		built.append_array(def.build_orders[tier].steps)
		for role: int in roles:
			if def.role_weight(tier, role) == 0:
				continue
			for id: StringName in roles[role]:
				var unit: UnitDef = _unit(id)
				var producer: bool = false
				for step: StringName in built:
					if _building(step).produces == unit.tab:
						producer = true
				(
					assert_bool(producer)
					. override_failure_message("tier %d: no producer of %s" % [tier, id])
					. is_true()
				)
				if unit.requires != null:
					(
						assert_array(built)
						. override_failure_message(
							"tier %d: %s needs %s" % [tier, id, unit.requires.type_id]
						)
						. contains([unit.requires.type_id])
					)


func test_a_build_order_def_has_empty_defaults_unlike_the_other_defs() -> void:
	var order: AiBuildOrderDef = AiBuildOrderDef.new()
	assert_str(String(order.id)).is_empty()
	assert_int(order.tier).is_equal(0)
	assert_array(order.steps).is_empty()


func test_the_role_weights_cover_every_tier_and_role_and_each_tier_draws_something(
	faction: String, _test_parameters := _factions()
) -> void:
	var def: OpponentDef = Rig.def_of(faction)
	assert_int(def.role_weights.size()).is_equal(OpponentDef.TIERS * OpponentDef.ROLES)
	for tier: int in OpponentDef.TIERS:
		var total: int = 0
		for role: int in OpponentDef.ROLES:
			assert_int(def.role_weight(tier, role)).is_greater_equal(0)
			total += def.role_weight(tier, role)
		assert_int(total).is_greater(0)
	assert_int(def.role_weight(3, 0)).is_equal(0)
	assert_int(def.role_weight(0, 4)).is_equal(0)


func test_the_numbers_fit_the_rules_and_the_footprints(
	faction: String, _test_parameters := _factions()
) -> void:
	var def: OpponentDef = Rig.def_of(faction)
	var rules: RulesDef = load("res://data/rules.tres") as RulesDef
	assert_int(def.queue_target).is_between(1, rules.queue_slots)
	assert_int(def.squads_max).is_greater(0)
	assert_int(def.sectors_max).is_greater(0)
	assert_int(def.place_tries_per_think).is_greater(0)
	assert_int(def.spiral_slots).is_greater_equal(def.place_tries_per_think)
	var widest: int = 0
	for id: StringName in _all_types(def):
		var unit: UnitDef = _unit(id)
		if unit is BuildingDef:
			var building: BuildingDef = unit as BuildingDef
			widest = maxi(widest, maxi(building.footprint.x, building.footprint.y))
	assert_int(def.place_stride_tiles).is_greater_equal(widest + 1)


func test_players_1_to_4_think_on_residues_0_to_3_and_never_on_a_checkpoint_tick(
	faction: String, _test_parameters := _factions()
) -> void:
	var def: OpponentDef = Rig.def_of(faction)
	assert_int(Replay.CHECKPOINT_PERIOD % def.think_period).is_equal(0)
	for player: int in [1, 2, 3, 4]:
		var ai: OpponentAi = Rig.opponent(faction, "normal", player)
		for tick: int in 30:
			if (tick + ai.think_offset) % ai.think_period == 0:
				assert_int(tick % 5).is_equal(player - 1)
				assert_int(tick % Replay.CHECKPOINT_PERIOD).is_not_equal(
					Replay.CHECKPOINT_PERIOD - 1
				)


func _levels() -> Array[Array]:
	return [["easy"], ["normal"], ["hard"]]


func _factions() -> Array[Array]:
	return [["fossil"], ["renew"]]


## Every property the script declares equals between `fresh` and `loaded`, but those in `skip`.
func _assert_defaults_equal(fresh: Resource, loaded: Resource, skip: Array[String]) -> void:
	var checked: int = 0
	for property: Dictionary in fresh.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var name: String = property["name"]
		if skip.has(name):
			continue
		checked += 1
		(
			assert_bool(fresh.get(name) == loaded.get(name))
			. override_failure_message("default of %s differs from the file" % name)
			. is_true()
		)
	assert_int(checked).is_greater(10)


func _all_types(def: OpponentDef) -> Array[StringName]:
	var ids: Array[StringName] = [
		def.hq_type,
		def.harvester_type,
		def.scout_type,
		def.anti_infantry_type,
		def.tank_type,
		def.artillery_type,
		def.defence_type,
		def.strike_type
	]
	ids.append_array(def.anti_vehicle_types)
	for order: AiBuildOrderDef in def.build_orders:
		ids.append_array(order.steps)
	return ids


func _unit(id: StringName) -> UnitDef:
	var unit: UnitDef = load(UNIT_DIR + String(id) + ".tres") as UnitDef
	assert_object(unit).override_failure_message("no type " + String(id)).is_not_null()
	return unit


func _building(id: StringName) -> BuildingDef:
	return _unit(id) as BuildingDef


func _ids_of(faction: FactionDef) -> Array[StringName]:
	var ids: Array[StringName] = []
	for unit: UnitDef in faction.roster:
		ids.append(unit.type_id)
	return ids
