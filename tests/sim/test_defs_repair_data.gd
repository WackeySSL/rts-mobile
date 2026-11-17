extends GdUnitTestSuite
## The repair buildings' and medic squads' data (plan row P278, ADR 0037 sections 5 and 6,
## docs/GDD.md): per faction one repair building and one medic squad. The roster entries come with
## the art rows P279 (buildings) and P280 (medics): none is buildable yet.
## The GDD and the ADR give the names, costs, power, requirements, classes, hp per period, reach,
## slots and cost percents of the buildings, and the medics' hit points, speed (the Menders'),
## reach, hp per period, slots, seek and cost. Starting values with no source: every build time,
## sight and radius, the buildings' hit points and armour, the repair period (15 ticks, the
## ADR's "per 15 ticks"), and the Patchers' speed (the rifle squads' 67).
## What the sim does with these fields is test_repair_run's and test_repair_reach's (the reach
## rule is held against every shipped file there).

const NAME_MAX: int = 10  ## ADR 0037 section 14: names are at most 10 characters.
const GROUND_CLASSES: int = 6  ## WHEELED 2 + TRACKED 4: the AIR bit (8) stays off.
const FOOT_BIT: int = 1

## id: [faction, name, requires, power, hp, reach, slots, cost percent]
const SHEDS: Dictionary[String, Array] = {
	"fossil_weld_shed": ["fossil", "Weld Shed", "vehicle_factory", -20, 30, 2700, 2, 25],
	"renew_drone_dock": ["renew", "Drone Dock", "renew_factory", -30, 12, 5000, 4, 35],
}
## id: [faction, name, speed, max_hp, hp per period, reach, slots, seek]
const MEDICS: Dictionary[String, Array] = {
	"fossil_patchers": ["fossil", "Patchers", 67, 110, 6, 1500, 1, 4000],
	"renew_menders": ["renew", "Menders", 80, 70, 8, 2500, 2, 6000],
}


func test_each_faction_has_a_repair_building_with_the_gdd_numbers() -> void:
	for id: String in SHEDS:
		var row: Array = SHEDS[id]
		var def: BuildingDef = _def(id) as BuildingDef
		assert_object(def).override_failure_message(id).is_not_null()
		assert_str(String(def.faction)).is_equal(row[0])
		assert_str(def.display_name).is_equal(row[1])
		assert_str(String(def.requires.type_id)).is_equal(row[2])
		(
			assert_array([def.cost, def.power, def.footprint, def.tab])
			. override_failure_message(id)
			. is_equal([800, row[3], Vector2i(2, 2), World.Tab.STRUCTURES])
		)
		(
			assert_array(
				[
					def.repair_classes,
					def.repair_hp,
					def.repair_period_ticks,
					def.repair_reach_milli,
					def.repair_slots,
					def.repair_cost_percent
				]
			)
			. override_failure_message(id)
			. is_equal([GROUND_CLASSES, row[4], 15, row[5], row[6], row[7]])
		)
		# A repair building has no pads (the air rule) and produces nothing.
		assert_int(def.pads).is_equal(0)
		assert_int(def.produces).is_less(0)
		assert_int(def.repair_seek_milli).is_equal(0)


func test_the_league_shed_is_faster_and_shorter_and_the_accord_dock_wider_and_slower() -> void:
	var shed: BuildingDef = _def("fossil_weld_shed") as BuildingDef
	var dock: BuildingDef = _def("renew_drone_dock") as BuildingDef
	assert_bool(shed.repair_hp > dock.repair_hp).is_true()
	assert_bool(shed.repair_reach_milli < dock.repair_reach_milli).is_true()
	assert_bool(shed.repair_slots < dock.repair_slots).is_true()
	assert_bool(shed.repair_cost_percent < dock.repair_cost_percent).is_true()
	assert_bool(shed.power > dock.power).is_true()


func test_each_faction_has_an_unarmed_foot_medic_from_the_barracks() -> void:
	for id: String in MEDICS:
		var row: Array = MEDICS[id]
		var def: UnitDef = _def(id)
		assert_str(String(def.faction)).is_equal(row[0])
		assert_str(def.display_name).is_equal(row[1])
		(
			assert_array([def.speed, def.max_hp, def.cost, def.tab])
			. override_failure_message(id)
			. is_equal([row[2], row[3], 300, World.Tab.INFANTRY])
		)
		(
			assert_array(
				[
					def.repair_classes,
					def.repair_hp,
					def.repair_period_ticks,
					def.repair_reach_milli,
					def.repair_slots,
					def.repair_seek_milli,
					def.repair_cost_percent
				]
			)
			. override_failure_message(id)
			. is_equal([FOOT_BIT, row[4], 15, row[5], row[6], row[7], 0])
		)
		assert_object(def.weapon).override_failure_message(id).is_null()
		assert_object(def.requires).override_failure_message(id).is_null()
		assert_int(def.move_class).is_equal(World.MoveClass.FOOT)
		assert_int(def.carry_slots).is_equal(0)
		assert_object(def).is_not_instanceof(BuildingDef)


## ADR 0037 section 6: the Menders are frailer and quicker, reach further, heal more squads and
## seek from further than the Patchers.
func test_the_menders_are_frailer_and_reach_further_than_the_patchers() -> void:
	var patchers: UnitDef = _def("fossil_patchers")
	var menders: UnitDef = _def("renew_menders")
	assert_bool(menders.max_hp < patchers.max_hp and menders.speed > patchers.speed).is_true()
	assert_bool(menders.repair_reach_milli > patchers.repair_reach_milli).is_true()
	assert_bool(menders.repair_slots > patchers.repair_slots).is_true()
	assert_bool(menders.repair_seek_milli > patchers.repair_seek_milli).is_true()
	assert_bool(menders.repair_hp > patchers.repair_hp).is_true()


func test_the_data_breaks_no_repair_rule() -> void:
	for id: String in SHEDS.keys() + MEDICS.keys():
		var def: UnitDef = _def(id)
		(
			assert_bool(id.begins_with(String(def.faction) + "_"))
			. override_failure_message(id)
			. is_true()
		)
		assert_int(def.repair_slots).override_failure_message(id).is_between(1, 8)
		assert_int(def.repair_hp).is_greater(0)
		assert_int(def.repair_period_ticks).is_greater(0)
		assert_int(def.repair_reach_milli).is_greater_equal(500)
		assert_int(def.max_hp).is_greater(0)
		assert_int(def.build_ticks).is_greater(0)
		assert_int(def.radius).is_between(0 if def is BuildingDef else 1, 500)
		assert_int(def.acquire_range).is_less_equal(def.sight_range)
		assert_int(def.repair_classes & 8).override_failure_message(id).is_equal(0)
		assert_int(def.ammo).is_equal(0)
		assert_int(def.mine_cost).is_equal(0)


func test_names_fit_the_limit_and_are_unique() -> void:
	var seen: Dictionary[String, bool] = {}
	for id: String in SHEDS.keys() + MEDICS.keys():
		var shown: String = _def(id).display_name
		assert_int(shown.length()).override_failure_message(shown).is_between(1, NAME_MAX)
		assert_bool(seen.has(shown)).override_failure_message(shown).is_false()
		seen[shown] = true


func test_not_in_a_roster_yet() -> void:
	for id: String in SHEDS.keys() + MEDICS.keys():
		var def: UnitDef = _def(id)
		var faction: FactionDef = load("res://data/factions/%s.tres" % def.faction)
		# The roster entries come with P279 (buildings) and P280 (medics), as the anti-air's did.
		assert_bool(faction.roster.has(def)).override_failure_message(id).is_false()


func _def(id: String) -> UnitDef:
	var def: UnitDef = load("res://data/units/%s.tres" % id) as UnitDef
	assert_object(def).override_failure_message(id).is_not_null()
	return def
