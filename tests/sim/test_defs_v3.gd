extends GdUnitTestSuite
## Phase 3 definitions (plan P69, ADR 0018 section 9): the script defaults of the new UnitDef,
## BuildingDef and TerrainDef fields. The 18 new RulesDef ints are pinned in test_defs and their
## file in test_defs_data. World copies these fields into its tables (plan row P70, test_world_v2)
## and no rule reads them before its row, so no rule moves.

## The names UnitDef gained and BuildingDef adds, in declaration order.
const UNIT_FIELDS: Array[String] = ["cost", "build_ticks", "tab", "requires", "harvest_capacity"]
const BUILDING_FIELDS: Array[String] = [
	"footprint", "power", "produces", "free_unit", "dock", "exit"
]
## The six strike exports BuildingDef gained in P109 (ADR 0023 section 10), after those.
const STRIKE_FIELDS: Array[String] = [
	"strike_kind", "charge_ticks", "strike_radius", "strike_delay", "strike_ticks", "strike_weapon"
]
const TAB_HINT: String = "None:-1,Structures:0,Infantry:1,Vehicles:2"
const STRIKE_HINT: String = "None:0,Rupture:1,Blackout:2"


func test_unit_def_defaults_are_not_buildable_and_not_a_harvester() -> void:
	var unit: UnitDef = UnitDef.new()
	assert_array([unit.cost, unit.build_ticks, unit.tab]).is_equal([0, 0, -1])
	assert_object(unit.requires).is_null()
	assert_int(unit.harvest_capacity).is_equal(0)


func test_unit_def_gains_exactly_its_five_fields_and_they_are_stored() -> void:
	var plain: Array[String] = _own_fields(Resource.new(), UnitDef.new())
	assert_bool(plain.has("type_id")).is_true()  # The Phase 2 fields are still there.
	assert_array(plain.slice(plain.size() - UNIT_FIELDS.size())).is_equal(UNIT_FIELDS)
	var types: Dictionary[String, int] = {}
	for info: Dictionary in UnitDef.new().get_property_list():
		types[String(info["name"])] = int(info["type"])
	(
		assert_array([types["cost"], types["build_ticks"], types["tab"], types["harvest_capacity"]])
		. is_equal([TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT])
	)
	assert_int(types["requires"]).is_equal(TYPE_OBJECT)
	assert_str(_hint_string(UnitDef.new(), "requires")).is_equal("UnitDef")
	assert_str(_hint_string(UnitDef.new(), "tab")).is_equal(TAB_HINT)


func test_building_def_is_a_unit_def_with_a_one_tile_footprint_and_nothing_else_set() -> void:
	var building: BuildingDef = BuildingDef.new()
	assert_bool(building is UnitDef).is_true()
	assert_that(building.footprint).is_equal(Vector2i(1, 1))
	assert_array([building.power, building.produces]).is_equal([0, -1])
	assert_object(building.free_unit).is_null()
	assert_array([building.dock, building.exit]).is_equal([Vector2i.ZERO, Vector2i.ZERO])
	# What a building inherits keeps the unit defaults: a data file sets speed, radius and armour.
	assert_array([building.speed, building.radius, building.armour]).is_equal([0, 0, 0])
	assert_array([building.cost, building.tab, building.harvest_capacity]).is_equal([0, -1, 0])


func test_building_def_adds_exactly_its_twelve_fields_to_a_unit_def() -> void:
	assert_array(_own_fields(UnitDef.new(), BuildingDef.new())).is_equal(
		BUILDING_FIELDS + STRIKE_FIELDS
	)
	var types: Dictionary[String, int] = {}
	for info: Dictionary in BuildingDef.new().get_property_list():
		types[String(info["name"])] = int(info["type"])
	for field: String in ["footprint", "dock", "exit"]:
		assert_int(types[field]).override_failure_message(field).is_equal(TYPE_VECTOR2I)
	for field: String in ["power", "produces"]:
		assert_int(types[field]).override_failure_message(field).is_equal(TYPE_INT)
	assert_int(types["free_unit"]).is_equal(TYPE_OBJECT)
	assert_str(_hint_string(BuildingDef.new(), "free_unit")).is_equal("UnitDef")
	assert_str(_hint_string(BuildingDef.new(), "produces")).is_equal(TAB_HINT)


## A building is no strike building until its data says so: kind none, no lengths, no weapon. The
## kind is an enum export (the inspector lists none, rupture and blackout), the rest are ints and
## the weapon is a WeaponDef; the sim copies them into the six type_strike_* tables (test_world_v3).
func test_a_building_def_has_no_strike_unless_its_data_says_so() -> void:
	var building: BuildingDef = BuildingDef.new()
	var numbers: Array[int] = [building.strike_kind, building.charge_ticks, building.strike_radius]
	numbers.append_array([building.strike_delay, building.strike_ticks])
	assert_array(numbers).is_equal([0, 0, 0, 0, 0])
	assert_object(building.strike_weapon).is_null()
	var types: Dictionary[String, int] = {}
	for info: Dictionary in BuildingDef.new().get_property_list():
		types[String(info["name"])] = int(info["type"])
	for field: String in STRIKE_FIELDS.slice(0, 5):
		assert_int(types[field]).override_failure_message(field).is_equal(TYPE_INT)
	assert_int(types["strike_weapon"]).is_equal(TYPE_OBJECT)
	assert_str(_hint_string(BuildingDef.new(), "strike_weapon")).is_equal("WeaponDef")
	assert_str(_hint_string(BuildingDef.new(), "strike_kind")).is_equal(STRIKE_HINT)


func test_a_scenario_roster_takes_a_building_def_because_it_is_a_unit_def() -> void:
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.roster.append(BuildingDef.new())
	assert_int(scenario.roster.size()).is_equal(1)
	assert_bool(scenario.roster[0] is BuildingDef).is_true()


func test_a_terrain_is_not_buildable_unless_its_data_says_so() -> void:
	var terrain: TerrainDef = TerrainDef.new()
	assert_bool(terrain.buildable).is_false()
	terrain.buildable = true
	assert_bool(terrain.buildable).is_true()
	var found: bool = false
	for info: Dictionary in terrain.get_property_list():
		if info["name"] == "buildable":
			found = true
			assert_int(int(info["type"])).is_equal(TYPE_BOOL)
	assert_bool(found).is_true()


## The names `derived` declares beyond `base`, in declaration order (script variables only).
func _own_fields(base: Object, derived: Object) -> Array[String]:
	var inherited: Dictionary[String, bool] = {}
	for info: Dictionary in base.get_property_list():
		inherited[String(info["name"])] = true
	var fields: Array[String] = []
	for info: Dictionary in derived.get_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if not inherited.has(String(info["name"])):
			fields.append(String(info["name"]))
	return fields


func _hint_string(object: Object, property: String) -> String:
	for info: Dictionary in object.get_property_list():
		if info["name"] == property:
			return String(info["hint_string"])
	return "no such property: " + property
