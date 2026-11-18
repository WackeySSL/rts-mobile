extends GdUnitTestSuite
## The ground carriers' and minelayers' data (plan row P290, ADR 0037 sections 7, 8 and 15,
## docs/GDD.md): per faction one carrier and one minelayer on the Vehicles tab, the two mines, the
## scout tanks' detection and the artillery on each opponent's `hold_types`. The carriers' roster
## entries came with their art (P291); the minelayers' come with P292 and are not buildable yet.
## The GDD gives the names, the carriers' cost, hit points, speed and seats, the mines' prices and
## blasts and the two sweep reaches. Starting values for the balance run, with no source in the GDD
## or the ADR: the minelayers' price, hit points, speed and armour class, the mines' damage and
## armour percents, and every build time, sight and radius. P291 removed the carriers' skips in
## test_defs_roster, test_defs_roster_renew and test_defs_factions_data; P292 removes the
## minelayers' and the is_false roster check below.
## What the sim does with these fields is test_carry_*'s and test_mines*'s.

const Rules: GDScript = preload("res://tests/sim/support/mine_rules.gd")
const WHEELED: int = World.MoveClass.WHEELED
const TRACKED: int = World.MoveClass.TRACKED
const FOOT_BIT: int = 1
const NAME_MAX: int = 10  ## ADR 0037 section 14: names are at most 10 characters.

## id: [faction, name, move class, armour, speed (milli-tiles a tick), max_hp, cost, seats, eject %]
const CARRIERS: Dictionary[String, Array] = {
	"fossil_bunk_wagon": ["fossil", "Bunk Wagon", TRACKED, World.Armour.HEAVY, 67, 700, 700, 4, 50],
	"renew_linecar": ["renew", "Linecar", WHEELED, World.Armour.LIGHT, 133, 320, 500, 2, 0],
}
## id: [faction, name, mine weapon id, mine cost, blast (milli-tiles), radar id]
const LAYERS: Dictionary[String, Array] = {
	"fossil_shot_truck": ["fossil", "Shot Truck", "shot_charge", 60, 1000, "fossil_radar"],
	"renew_seeder": ["renew", "Seeder", "pulse_seed", 50, 1500, "renew_radar"],
}
## The scout tanks of the two factions find mines within 2 tiles, the minelayers within 3.
const SCOUTS: Array[String] = ["light_tank", "renew_scout"]
const DETECT_SCOUT: int = 2000
const DETECT_LAYER: int = 3000


func test_each_faction_has_a_ground_carrier_with_the_gdd_numbers() -> void:
	for id: String in CARRIERS:
		var row: Array = CARRIERS[id]
		var def: UnitDef = _def(id)
		assert_str(String(def.faction)).is_equal(row[0])
		assert_str(def.display_name).is_equal(row[1])
		assert_array([def.move_class, def.armour, def.tab]).override_failure_message(id).is_equal(
			[row[2], row[3], World.Tab.VEHICLES]
		)
		assert_array([def.speed, def.max_hp, def.cost, def.carry_slots]).is_equal(
			[row[4], row[5], row[6], row[7]]
		)
		assert_int(def.carry_eject_percent).override_failure_message(id).is_equal(row[8])
		# Squads ride (the foot class only), and nothing fires from inside: the carrier is unarmed.
		assert_int(def.carry_classes).is_equal(FOOT_BIT)
		assert_int(def.carry_slots).is_between(1, 8)
		assert_object(def.weapon).override_failure_message(id).is_null()
		assert_object(def.mine_weapon).is_null()
		assert_array([def.mine_cost, def.detect_milli]).is_equal([0, 0])
		assert_bool(def.mine_aware).is_false()
		assert_object(def.requires).is_null()


func test_the_league_carrier_is_slower_and_tougher_and_only_it_ejects_its_squads() -> void:
	var bunk: UnitDef = _def("fossil_bunk_wagon")
	var line: UnitDef = _def("renew_linecar")
	assert_bool(bunk.speed < line.speed and bunk.max_hp > line.max_hp).is_true()
	assert_bool(bunk.carry_slots > line.carry_slots and bunk.cost > line.cost).is_true()
	assert_int(bunk.carry_eject_percent).is_equal(50)
	assert_int(line.carry_eject_percent).is_equal(0)


func test_each_faction_has_an_unarmed_minelayer_that_needs_its_radar() -> void:
	for id: String in LAYERS:
		var row: Array = LAYERS[id]
		var def: UnitDef = _def(id)
		assert_str(String(def.faction)).is_equal(row[0])
		assert_str(def.display_name).is_equal(row[1])
		assert_array([def.move_class, def.tab]).override_failure_message(id).is_equal(
			[WHEELED, World.Tab.VEHICLES]
		)
		assert_object(def.weapon).override_failure_message(id).is_null()
		assert_str(String(def.mine_weapon.id)).is_equal(row[2])
		assert_array([def.mine_cost, def.mine_weapon.blast_milli]).is_equal([row[3], row[4]])
		assert_bool(def.mine_aware).is_true()
		assert_int(def.detect_milli).is_equal(DETECT_LAYER)
		assert_int(def.carry_slots).is_equal(0)
		assert_object(def.requires).override_failure_message(id).is_same(_def(row[5]))


## ADR 0037 section 8: the League's charge hits hard in a small blast and is strong against
## vehicles; the Accord's seed hits less in a wider blast and is better against squads.
func test_the_two_mines_differ_as_the_gdd_says() -> void:
	var shot: WeaponDef = _def("fossil_shot_truck").mine_weapon
	var seed_mine: WeaponDef = _def("renew_seeder").mine_weapon
	assert_bool(shot.damage > seed_mine.damage).is_true()
	assert_bool(shot.blast_milli < seed_mine.blast_milli).is_true()
	for gun: WeaponDef in [shot, seed_mine]:
		assert_int(gun.vs_armour.size()).is_equal(World.Armour.size())
		assert_int(gun.damage).is_greater(0)
	var armour_of_vehicle: int = World.Armour.HEAVY
	assert_bool(shot.vs_armour[armour_of_vehicle] > shot.vs_armour[World.Armour.INFANTRY]).is_true()
	(
		assert_bool(
			seed_mine.vs_armour[World.Armour.INFANTRY] > seed_mine.vs_armour[armour_of_vehicle]
		)
		. is_true()
	)
	# A mine is not fired and is no unit's gun.
	for gun: WeaponDef in [shot, seed_mine]:
		assert_int(gun.range).is_equal(0)
		for id: String in ["light_tank", "renew_scout", "heavy_tank", "renew_tank"]:
			assert_object(_def(id).weapon).is_not_same(gun)


func test_only_the_minelayers_and_the_scout_tanks_detect() -> void:
	for id: String in SCOUTS:
		var def: UnitDef = _def(id)
		assert_int(def.detect_milli).override_failure_message(id).is_equal(DETECT_SCOUT)
		# A scout still sets mines off: it is a detector, not mine-aware.
		assert_bool(def.mine_aware).is_false()
		assert_object(def.mine_weapon).is_null()
	var detectors: Array[String] = []
	for file: String in DirAccess.get_files_at("res://data/units"):
		if file.ends_with(".tres") and _def(file.get_basename()).detect_milli > 0:
			detectors.append(file.get_basename())
	detectors.sort()
	assert_array(detectors).is_equal(
		["fossil_shot_truck", "light_tank", "renew_scout", "renew_seeder"]
	)


func test_the_data_breaks_no_ground_support_rule() -> void:
	for id: String in CARRIERS.keys() + LAYERS.keys() + SCOUTS:
		var def: UnitDef = _def(id)
		assert_array(Rules.mine_problems("%s.tres" % id, def)).is_empty()
		assert_object(def).override_failure_message(id).is_not_instanceof(BuildingDef)
		assert_int(def.radius).is_between(1, 500)
		assert_int(def.max_hp).is_greater(0)
		assert_int(def.build_ticks).is_greater(0)
		assert_int(def.acquire_range).is_less_equal(def.sight_range)
	for id: String in CARRIERS.keys() + LAYERS.keys():
		assert_bool(id.begins_with(String(_def(id).faction) + "_")).is_true()


func test_names_fit_the_limit_and_are_unique() -> void:
	var seen: Dictionary[String, bool] = {}
	for id: String in CARRIERS.keys() + LAYERS.keys():
		var shown: String = _def(id).display_name
		assert_int(shown.length()).override_failure_message(shown).is_between(1, NAME_MAX)
		assert_bool(seen.has(shown)).override_failure_message(shown).is_false()
		seen[shown] = true


## ADR 0037 section 15: Normal and Hard hold each faction's artillery, which has a minimum range.
func test_each_opponent_holds_its_artillery() -> void:
	for id: String in ["fossil", "renew"]:
		var def: OpponentDef = load("res://data/ai/opponent_%s.tres" % id) as OpponentDef
		assert_array(def.hold_types).override_failure_message(id).is_equal([def.artillery_type])
		var gun: UnitDef = _def(String(def.hold_types[0]))
		assert_int(gun.weapon.min_range).is_greater(0)
		assert_str(String(gun.faction)).is_equal(id)
	assert_array(OpponentDef.new().hold_types).is_equal([&"artillery"])


func test_the_carriers_are_in_the_rosters_and_the_minelayers_not_yet() -> void:
	for id: String in CARRIERS.keys():
		var def: UnitDef = _def(id)
		var faction: FactionDef = load("res://data/factions/%s.tres" % def.faction)
		# P291 added the roster entries with the art and the item cards.
		assert_bool(faction.roster.has(def)).override_failure_message(id).is_true()
	for id: String in LAYERS.keys():
		var def: UnitDef = _def(id)
		var faction: FactionDef = load("res://data/factions/%s.tres" % def.faction)
		# The roster entry comes with P292 (art, item card), as the anti-air's came with P239b.
		assert_bool(faction.roster.has(def)).override_failure_message(id).is_false()


func _def(id: String) -> UnitDef:
	var def: UnitDef = load("res://data/units/%s.tres" % id) as UnitDef
	assert_object(def).override_failure_message(id).is_not_null()
	return def
