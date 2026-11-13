extends GdUnitTestSuite
## The transports' and drone squads' data (plan row P264, ADR 0036 sections 2, 8, 9 and 16,
## docs/GDD.md): per faction one air transport on the Flight tab and one low-flying drone squad on
## the Infantry tab. The roster entries come with P266 (art, item card): none is buildable yet.
## The GDD gives names, cost, hit points, speed (tiles a second, here milli-tiles a tick at 15 Hz),
## the squads a transport holds and the Hoist Crew's range. Build times, sight, radii, armour of
## the transports, the guns' damage, cooldown and armour percents are starting values for the
## balance run. The Kite Crew's range is the Hoist Crew's. P266 removes the skips in
## test_defs_roster, test_defs_roster_renew and test_defs_factions_data and the is_false roster
## checks below. What the sim does with the carrier fields is test_carry_*'s.

const Rules: GDScript = preload("res://tests/sim/support/air_rules.gd")
const AIR: int = World.MoveClass.AIR
const FOOT_BIT: int = 1

## id: [faction, name, speed, max_hp, cost, slots, armour (ADR 0036 section 8)]
const TRANSPORTS: Dictionary[String, Array] = {
	"fossil_transport": ["fossil", "Skyhauler", 107, 600, 1000, 3, World.Armour.HEAVY],
	"renew_transport": ["renew", "Ferrywing", 160, 380, 800, 2, World.Armour.LIGHT],
}
## id: [faction, name, speed, max_hp, cost, weapon id, damage]
const DRONES: Dictionary[String, Array] = {
	"fossil_drone": ["fossil", "Hoist Crew", 93, 140, 350, "hoist_crew_gun", 14],
	"renew_drone": ["renew", "Kite Crew", 133, 90, 300, "kite_crew_gun", 12],
}
## The longest name a one-line caption holds (ADR 0036 section 16: at most about 11 characters).
const NAME_MAX: int = 11


func test_each_faction_has_a_transport_with_the_gdd_numbers() -> void:
	for id: String in TRANSPORTS:
		var row: Array = TRANSPORTS[id]
		var def: UnitDef = _def(id)
		assert_str(String(def.type_id)).is_equal(id)
		assert_str(String(def.faction)).is_equal(row[0])
		assert_str(def.display_name).is_equal(row[1])
		assert_array([def.speed, def.max_hp, def.cost, def.carry_slots]).is_equal(
			[row[2], row[3], row[4], row[5]]
		)
		assert_array([def.move_class, def.tab, def.low_flying, def.armour]).is_equal(
			[AIR, World.Tab.FLIGHT, false, row[6]]
		)
		# Unarmed, and no ammo: a transport has nothing to reload.
		assert_object(def.weapon).override_failure_message(id).is_null()
		assert_array([def.ammo, def.rearm_ticks]).is_equal([0, 0])


func test_a_transport_carries_foot_squads_only_and_is_no_building() -> void:
	for id: String in TRANSPORTS:
		var def: UnitDef = _def(id)
		assert_object(def).override_failure_message(id).is_not_instanceof(BuildingDef)
		assert_int(def.carry_classes).override_failure_message(id).is_equal(FOOT_BIT)
		# ADR 0036 section 2: 1..8 slots, and a drone squad (AIR) cannot board.
		assert_int(def.carry_slots).is_between(1, Rules.MAX_SLOTS)
		assert_int(def.carry_classes & (1 << AIR)).is_equal(0)
		# ADR 0036 section 2: a transport is light or heavy, never the infantry class.
		assert_bool(def.armour in [World.Armour.LIGHT, World.Armour.HEAVY]).is_true()


func test_each_faction_has_a_low_flying_drone_squad_on_the_infantry_tab() -> void:
	for id: String in DRONES:
		var row: Array = DRONES[id]
		var def: UnitDef = _def(id)
		assert_str(String(def.type_id)).is_equal(id)
		assert_str(String(def.faction)).is_equal(row[0])
		assert_str(def.display_name).is_equal(row[1])
		assert_array([def.speed, def.max_hp, def.cost]).is_equal([row[2], row[3], row[4]])
		assert_array([def.move_class, def.low_flying, def.tab, def.armour]).is_equal(
			[AIR, true, World.Tab.INFANTRY, World.Armour.INFANTRY]
		)
		# ADR 0036 section 9: no ammo, no pad, and not a carrier.
		assert_array([def.ammo, def.rearm_ticks, def.carry_slots, def.carry_classes]).is_equal(
			[0, 0, 0, 0]
		)


## ADR 0036 section 9: the gun hits the ground only, from 4 tiles (the GDD's Hoist Crew range).
func test_the_drone_guns_hit_the_ground_only_from_four_tiles() -> void:
	for id: String in DRONES:
		var gun: WeaponDef = _def(id).weapon
		assert_object(gun).override_failure_message(id).is_not_null()
		assert_str(String(gun.id)).is_equal(DRONES[id][5])
		assert_array([gun.targets, gun.range, gun.damage]).is_equal(
			[World.Layer.GROUND, 4000, DRONES[id][6]]
		)
		assert_int(gun.cooldown_ticks).is_greater(0)
		assert_int(gun.vs_armour.size()).is_equal(4)
		assert_int(gun.vs_armour[World.Armour.INFANTRY]).is_greater(0)
		assert_int(_def(id).acquire_range).is_less_equal(gun.range + 1000)


## ADR 0037 section 7: the passengers' hit points survive a carrier's death only on a ground
## carrier. An aircraft keeps 0 (they die with it), and a drone squad has no such field either.
func test_carry_eject_percent_is_absent_on_every_aircraft() -> void:
	for id: String in TRANSPORTS.keys() + DRONES.keys():
		assert_int(_def(id).carry_eject_percent).override_failure_message(id).is_equal(0)
		assert_int(_def(id).mine_cost).override_failure_message(id).is_equal(0)


func test_the_data_breaks_no_air_rule_and_the_faction_matches_the_file() -> void:
	for id: String in TRANSPORTS.keys() + DRONES.keys():
		var def: UnitDef = _def(id)
		assert_array(Rules.air_problems("%s.tres" % id, def)).is_empty()
		assert_bool(id.begins_with(String(def.faction) + "_")).is_true()
		assert_int(def.radius).is_between(1, 500)
		assert_int(def.max_hp).is_greater(0)
		assert_int(def.build_ticks).is_greater(0)


## The names are the GDD's and fit one caption line (ADR 0036 section 16).
func test_names_fit_one_line_and_are_unique() -> void:
	var seen: Dictionary[String, bool] = {}
	for id: String in TRANSPORTS.keys() + DRONES.keys():
		var shown: String = _def(id).display_name
		assert_int(shown.length()).override_failure_message(shown).is_between(1, NAME_MAX)
		assert_bool(seen.has(shown)).override_failure_message(shown).is_false()
		seen[shown] = true


## Both types require their faction's airfield (ADR 0036 sections 8 and 9).
func test_each_type_requires_its_factions_airfield() -> void:
	for id: String in TRANSPORTS.keys() + DRONES.keys():
		var def: UnitDef = _def(id)
		var field: BuildingDef = load("res://data/units/%s_airfield.tres" % def.faction)
		assert_object(def.requires).override_failure_message(id).is_same(field)
		assert_int(field.pads).is_greater(0)


func test_not_in_a_roster_yet() -> void:
	for id: String in TRANSPORTS.keys() + DRONES.keys():
		var def: UnitDef = _def(id)
		var faction: FactionDef = load("res://data/factions/%s.tres" % def.faction)
		# The roster entry comes with P266 (art, item card), as the anti-air's came with P239b.
		assert_bool(faction.roster.has(def)).override_failure_message(id).is_false()


func _def(id: String) -> UnitDef:
	var def: UnitDef = load("res://data/units/%s.tres" % id) as UnitDef
	assert_object(def).override_failure_message(id).is_not_null()
	return def
