extends GdUnitTestSuite
## The dummy's defs in `data/ai/` (plan rows P83 and P83d, ADR 0020 section 4, ADR 0023 section 6):
## `dummy_fossil.tres` of the Derrick League and `dummy_renew.tres` of the Lumen Accord. Each is
## pinned for the numbers the plan names and for the types it names: every one is a shipped type of
## the right kind and of the def's own faction, with its requirement before it in the order, so the
## dummy never waits for a building its order never builds and never names a type of the other
## faction.

const DEF_PATHS: Dictionary[String, String] = {
	"fossil": "res://data/ai/dummy_fossil.tres", "renew": "res://data/ai/dummy_renew.tres"
}
const FACTION_PATHS: Dictionary[String, String] = {
	"fossil": "res://data/factions/fossil.tres", "renew": "res://data/factions/renew.tres"
}
const UNIT_DIR: String = "res://data/units/"
const FOSSIL_BUILD_ORDER: Array[StringName] = [
	&"power_plant",
	&"refinery",
	&"barracks",
	&"power_plant",
	&"vehicle_factory",
	&"defence_turret",
	&"defence_turret",
	&"power_plant",
]
## The Lumen Accord's: the same shape, each type its faction's counterpart (ADR 0023 section 7).
const RENEW_BUILD_ORDER: Array[StringName] = [
	&"renew_power",
	&"renew_refinery",
	&"renew_barracks",
	&"renew_power",
	&"renew_factory",
	&"renew_defence",
	&"renew_defence",
	&"renew_power",
]
const HEADQUARTERS: Dictionary[String, StringName] = {
	"fossil": &"headquarters", "renew": &"renew_hq"
}
const HARVESTERS: Dictionary[String, StringName] = {
	"fossil": &"harvester", "renew": &"renew_tanker"
}
## The strike building of each faction (plan row P107, P108): the dummy builds none.
const STRIKES: Dictionary[String, StringName] = {
	"fossil": &"fossil_strike", "renew": &"renew_strike"
}


func test_the_def_loads_with_the_numbers_of_the_plan(
	faction: String, _test_parameters := _each()
) -> void:
	var def: AiDef = _def(faction)
	assert_object(def).is_not_null()
	assert_str(String(def.id)).is_equal("dummy_" + faction)
	assert_array(def.build_order).is_equal(
		FOSSIL_BUILD_ORDER if faction == "fossil" else RENEW_BUILD_ORDER
	)
	(
		assert_array([def.queue_target, def.harvesters_wanted, def.place_tries, def.think_period])
		. is_equal([2, 2, 64, 15])
	)
	assert_int(def.defend_radius_tiles).is_equal(12)
	assert_vector(def.guard_offset_tiles).is_equal(Vector2i(2, 2))
	assert_array([def.hq_type, def.harvester_type]).is_equal(
		[HEADQUARTERS[faction], HARVESTERS[faction]]
	)


func test_every_building_of_the_order_is_a_structure_with_its_requirement_before_it(
	faction: String, _test_parameters := _each()
) -> void:
	var def: AiDef = _def(faction)
	var earlier: Array[StringName] = [def.hq_type]
	for id: StringName in def.build_order:
		var unit: UnitDef = load(UNIT_DIR + String(id) + ".tres") as UnitDef
		assert_object(unit).override_failure_message("no type " + String(id)).is_not_null()
		assert_object(unit).is_instanceof(BuildingDef)
		assert_str(String(unit.type_id)).is_equal(String(id))
		assert_int(unit.tab).is_equal(World.Tab.STRUCTURES)
		assert_int(unit.cost).is_greater(0)
		var needs: StringName = unit.requires.type_id if unit.requires != null else &""
		(
			assert_bool(unit.requires == null or earlier.has(needs))
			. override_failure_message("%s needs %s before it" % [id, needs])
			. is_true()
		)
		earlier.append(id)


func test_every_type_of_the_def_is_a_type_of_its_faction_and_the_order_has_no_strike(
	faction: String, _test_parameters := _each()
) -> void:
	var def: AiDef = _def(faction)
	var own: FactionDef = load(FACTION_PATHS[faction]) as FactionDef
	var other: FactionDef = (
		load(FACTION_PATHS["renew" if faction == "fossil" else "fossil"]) as FactionDef
	)
	var ids: Array[StringName] = [def.hq_type, def.harvester_type]
	ids.append_array(def.build_order)
	for id: StringName in ids:
		var unit: UnitDef = load(UNIT_DIR + String(id) + ".tres") as UnitDef
		assert_str(String(unit.faction)).is_equal(faction)
		assert_array(_ids_of(own)).contains([id])
		assert_array(_ids_of(other)).not_contains([id])
	assert_array(def.build_order).not_contains([STRIKES[faction]])


func test_the_headquarters_and_the_harvester_are_what_the_def_says(
	faction: String, _test_parameters := _each()
) -> void:
	var def: AiDef = _def(faction)
	var hq: BuildingDef = load(UNIT_DIR + String(def.hq_type) + ".tres") as BuildingDef
	assert_object(hq).is_not_null()
	assert_int(hq.produces).is_equal(World.Tab.STRUCTURES)
	assert_int(hq.cost).is_equal(0)
	var harvester: UnitDef = load(UNIT_DIR + String(def.harvester_type) + ".tres") as UnitDef
	assert_int(harvester.harvest_capacity).is_greater(0)
	assert_int(harvester.tab).is_equal(World.Tab.VEHICLES)
	# The order's refinery (the building with a dock) brings the harvester the def counts on.
	var docks: int = 0
	for id: StringName in def.build_order:
		var building: BuildingDef = load(UNIT_DIR + String(id) + ".tres") as BuildingDef
		if building.dock != Vector2i.ZERO:
			docks += 1
			assert_object(building.free_unit).is_not_null()
			assert_str(String(building.free_unit.type_id)).is_equal(String(def.harvester_type))
	assert_int(docks).is_equal(1)


func test_the_numbers_fit_the_rules_and_the_footprints(
	faction: String, _test_parameters := _each()
) -> void:
	var def: AiDef = _def(faction)
	var rules: RulesDef = load("res://data/rules.tres") as RulesDef
	assert_int(def.queue_target).is_between(1, rules.queue_slots)
	assert_int(def.place_tries).is_greater(0)
	assert_int(def.harvesters_wanted).is_greater(0)
	# The stride is the largest footprint of the order and the Headquarters plus one free tile.
	var widest: int = 0
	var ids: Array[StringName] = [def.hq_type]
	ids.append_array(def.build_order)
	for id: StringName in ids:
		var building: BuildingDef = load(UNIT_DIR + String(id) + ".tres") as BuildingDef
		widest = maxi(widest, maxi(building.footprint.x, building.footprint.y))
	assert_int(def.place_stride_tiles).is_greater_equal(widest + 1)


func test_the_guard_point_is_beside_the_headquarters_and_within_the_defend_radius(
	faction: String, _test_parameters := _each()
) -> void:
	# Each axis is at most half the radius, which is what keeps the point within the radius (a
	# controller cuts a larger offset), and the point is off the Headquarters' centre.
	var def: AiDef = _def(faction)
	var offset: Vector2i = def.guard_offset_tiles
	assert_bool(offset != Vector2i.ZERO).is_true()
	assert_int(maxi(absi(offset.x), absi(offset.y)) * 2).is_less_equal(def.defend_radius_tiles)
	# Two tiles from the centre of the 3 x 3 Headquarters, on both axes, is the free tile between it
	# and the first slot of the spiral (the stride 4 leaves one tile past a footprint of 3).
	var hq: BuildingDef = load(UNIT_DIR + String(def.hq_type) + ".tres") as BuildingDef
	assert_vector(hq.footprint).is_equal(Vector2i(3, 3))
	assert_vector(offset).is_equal(Vector2i(2, 2))
	assert_int(def.place_stride_tiles).is_equal(4)


func test_no_player_from_2_to_4_thinks_on_the_tick_that_ends_in_a_checkpoint(
	faction: String, _test_parameters := _each()
) -> void:
	var def: AiDef = _def(faction)
	assert_int(def.think_period).is_equal(Replay.CHECKPOINT_PERIOD)
	for player: int in [2, 3, 4]:
		assert_int((def.think_tick + player - 2) % def.think_period).is_not_equal(
			Replay.CHECKPOINT_PERIOD - 1
		)


## gdUnit4's parameter sets: one case per faction (a method, since gdUnit4 writes into the sets).
func _each() -> Array[Array]:
	return [["fossil"], ["renew"]]


func _def(faction: String) -> AiDef:
	return load(DEF_PATHS[faction]) as AiDef


## The type ids of a faction's roster.
func _ids_of(faction: FactionDef) -> Array[StringName]:
	var ids: Array[StringName] = []
	for unit: UnitDef in faction.roster:
		ids.append(unit.type_id)
	return ids
