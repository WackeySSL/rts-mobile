extends GdUnitTestSuite
## `data/ai/dummy.tres` (plan row P83): the numbers the plan names, and that every type the def
## names is a shipped type of the right kind with its requirement before it in the order, so the
## dummy never waits for a building its order never builds.

const DEF_PATH: String = "res://data/ai/dummy.tres"
const UNIT_DIR: String = "res://data/units/"
const DUMMY_BUILD_ORDER: Array[StringName] = [
	&"power_plant",
	&"refinery",
	&"barracks",
	&"power_plant",
	&"vehicle_factory",
	&"defence_turret",
	&"defence_turret",
	&"power_plant",
]

var _def: AiDef


func before_test() -> void:
	_def = load(DEF_PATH) as AiDef


func test_the_dummy_def_loads_with_the_numbers_of_the_plan() -> void:
	assert_object(_def).is_not_null()
	assert_str(String(_def.id)).is_equal("dummy")
	assert_array(_def.build_order).is_equal(DUMMY_BUILD_ORDER)
	(
		assert_array(
			[_def.queue_target, _def.harvesters_wanted, _def.place_tries, _def.think_period]
		)
		. is_equal([2, 2, 64, 15])
	)
	assert_int(_def.defend_radius_tiles).is_equal(12)
	assert_vector(_def.guard_offset_tiles).is_equal(Vector2i(2, 2))
	assert_array([_def.hq_type, _def.harvester_type]).is_equal([&"headquarters", &"harvester"])


func test_every_building_of_the_order_is_a_structure_with_its_requirement_before_it() -> void:
	var earlier: Array[StringName] = [_def.hq_type]
	for id: StringName in _def.build_order:
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


func test_the_headquarters_and_the_harvester_are_what_the_def_says() -> void:
	var hq: BuildingDef = load(UNIT_DIR + String(_def.hq_type) + ".tres") as BuildingDef
	assert_object(hq).is_not_null()
	assert_int(hq.produces).is_equal(World.Tab.STRUCTURES)
	assert_int(hq.cost).is_equal(0)
	var harvester: UnitDef = load(UNIT_DIR + String(_def.harvester_type) + ".tres") as UnitDef
	assert_int(harvester.harvest_capacity).is_greater(0)
	assert_int(harvester.tab).is_equal(World.Tab.VEHICLES)


func test_the_numbers_fit_the_rules_and_the_footprints() -> void:
	var rules: RulesDef = load("res://data/rules.tres") as RulesDef
	assert_int(_def.queue_target).is_between(1, rules.queue_slots)
	assert_int(_def.place_tries).is_greater(0)
	assert_int(_def.harvesters_wanted).is_greater(0)
	# The stride is the largest footprint of the order and the Headquarters plus one free tile.
	var widest: int = 0
	var ids: Array[StringName] = [_def.hq_type]
	ids.append_array(_def.build_order)
	for id: StringName in ids:
		var building: BuildingDef = load(UNIT_DIR + String(id) + ".tres") as BuildingDef
		widest = maxi(widest, maxi(building.footprint.x, building.footprint.y))
	assert_int(_def.place_stride_tiles).is_greater_equal(widest + 1)


func test_the_guard_point_is_beside_the_headquarters_and_within_the_defend_radius() -> void:
	# Each axis is at most half the radius, which is what keeps the point within the radius (a
	# controller cuts a larger offset), and the point is off the Headquarters' centre.
	var offset: Vector2i = _def.guard_offset_tiles
	assert_bool(offset != Vector2i.ZERO).is_true()
	assert_int(maxi(absi(offset.x), absi(offset.y)) * 2).is_less_equal(_def.defend_radius_tiles)
	# Two tiles from the centre of the 3 x 3 Headquarters, on both axes, is the free tile between it
	# and the first slot of the spiral (the stride 4 leaves one tile past a footprint of 3).
	assert_vector(offset).is_equal(Vector2i(2, 2))
	assert_int(_def.place_stride_tiles).is_equal(4)


func test_no_player_from_2_to_4_thinks_on_the_tick_that_ends_in_a_checkpoint() -> void:
	assert_int(_def.think_period).is_equal(Replay.CHECKPOINT_PERIOD)
	for player: int in [2, 3, 4]:
		assert_int((_def.think_tick + player - 2) % _def.think_period).is_not_equal(
			Replay.CHECKPOINT_PERIOD - 1
		)
