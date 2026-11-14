extends GdUnitTestSuite
## The airfield, fighter and bomber data (plan row P242, ADR 0036 sections 2, 5 and 6, docs/GDD.md):
## one airfield, one fighter and one bomber per faction, with their guns. They are data only: the
## roster entries (art, item card) and the HOW_TO_PLAY rows come with P245b (the airfields) and P245
## (the aircraft), so none of them is buildable yet. `type_id` is the art id those rows draw. The
## GDD gives the names, size, cost, power, requirement, hit points, speed, range and ammo; the ADR
## gives the masks. The bomber range is 3 tiles (the lead, 2026-11-13: 2.5 stops at a ring corner).
## Build times, sight, the repair numbers, damage, cooldowns, armour percents,
## rearm time and armour classes are in neither: starting values for the balance run (speeds are
## the GDD's tiles per second over 15 ticks). P245b removes the airfield entries and P245 the
## aircraft entries of test_defs_roster, test_defs_roster_renew and test_defs_factions_data, and
## flips the is_false roster checks below. What the sim does with the data is test_airfield's.

const FIELDS: Dictionary[String, Array] = {
	"fossil_airfield": ["fossil", "Flight Yard", "fossil_radar"],
	"renew_airfield": ["renew", "Glide Deck", "renew_radar"],
}
## type id: faction, name, hp, speed, cost, weapon id, range, mask, ammo.
const AIRCRAFT: Dictionary[String, Array] = {
	"fossil_fighter": ["fossil", "Torchjet", 260, 200, 900, "torchjet_gun", 5000, 2, 0],
	"renew_fighter": ["renew", "Glint", 200, 240, 900, "glint_gun", 5000, 2, 0],
	"fossil_bomber": ["fossil", "Drillhead", 500, 120, 1400, "drillhead_bombs", 3000, 1, 2],
	"renew_bomber": ["renew", "Sunfall", 380, 147, 1400, "sunfall_bombs", 3000, 1, 2],
}
## ADR 0032: a name fits one line of the item card, at most about 11 characters.
const MAX_NAME: int = 11
const Rules: GDScript = preload("res://tests/sim/support/air_rules.gd")


func _building(id: String) -> BuildingDef:
	return load("res://data/units/%s.tres" % id) as BuildingDef


func _unit(id: String) -> UnitDef:
	return load("res://data/units/%s.tres" % id) as UnitDef


func test_each_faction_has_an_airfield_with_the_gdd_numbers() -> void:
	for id: String in FIELDS:
		var def: BuildingDef = _building(id)
		assert_object(def).override_failure_message(id).is_not_null()
		assert_str(String(def.type_id)).is_equal(id)
		assert_str(String(def.faction)).is_equal(FIELDS[id][0])
		assert_str(def.display_name).is_equal(FIELDS[id][1])
		assert_str(String(def.requires.type_id)).is_equal(FIELDS[id][2])
		# GDD: size, cost, power, tab (requires is checked above).
		assert_array([def.footprint, def.cost, def.power, def.tab]).is_equal(
			[Vector2i(3, 3), 1500, -40, World.Tab.STRUCTURES]
		)
		# The Flight tab, four pads at the corners, the AIR bit only. Starting values after that.
		assert_array([def.produces, def.pads, def.repair_classes]).is_equal(
			[World.Tab.FLIGHT, 4, 8]
		)
		assert_array([def.speed, def.radius, def.armour, def.strike_kind]).is_equal(
			[0, 0, World.Armour.BUILDING, 0]
		)
		assert_object(def.weapon).is_null()
		assert_array([def.max_hp, def.build_ticks, def.sight_range]).is_equal([1600, 480, 5000])
		(
			assert_array(
				[
					def.repair_hp,
					def.repair_period_ticks,
					def.repair_cost_percent,
					def.repair_reach_milli
				]
			)
			. is_equal([10, 15, 50, 1500])
		)
		# The exit is south of the 3x3 footprint, as the Heavy Yard's.
		assert_object(def.exit).is_equal(Vector2i(1, 3))
		# Not in a roster yet: the roster entry comes with P245b (art, item card).
		var faction: FactionDef = load("res://data/factions/%s.tres" % FIELDS[id][0])
		assert_bool(faction.roster.has(def)).override_failure_message(id).is_false()


## ADR 0036 section 6: the cap counts the pads, so four pads on four different tiles, each at
## least the largest FLIGHT spacing from the next, inside the footprint.
func test_the_pads_are_four_distinct_tiles_inside_the_footprint_and_apart() -> void:
	var spacing: int = 0
	for id: String in AIRCRAFT:
		spacing = maxi(spacing, _unit(id).formation_spacing)
	assert_int(spacing).is_greater(0)
	for id: String in FIELDS:
		var def: BuildingDef = _building(id)
		assert_int(def.pad_offsets.size()).is_equal(4)
		assert_array(Rules.air_problems(id, def)).override_failure_message(id).is_empty()
		assert_array(Rules.pad_spacing_problems(id, def, spacing)).is_empty()
		assert_int(def.repair_reach_milli).is_greater_equal(Rules.MIN_REACH)


func test_each_faction_has_a_fighter_and_a_bomber_with_the_gdd_numbers() -> void:
	for id: String in AIRCRAFT:
		var row: Array = AIRCRAFT[id]
		var def: UnitDef = _unit(id)
		assert_object(def).override_failure_message(id).is_not_null()
		assert_str(String(def.type_id)).is_equal(id)
		assert_str(String(def.faction)).is_equal(row[0])
		assert_str(def.display_name).is_equal(row[1])
		assert_array([def.max_hp, def.speed, def.cost]).is_equal([row[2], row[3], row[4]])
		assert_array([def.move_class, def.tab, def.low_flying]).is_equal(
			[World.MoveClass.AIR, World.Tab.FLIGHT, false]
		)
		assert_str(String(def.requires.type_id)).is_equal("%s_airfield" % row[0])
		var gun: WeaponDef = def.weapon
		assert_object(gun).override_failure_message(id).is_not_null()
		assert_str(String(gun.id)).is_equal(row[5])
		assert_array([gun.range, gun.targets]).is_equal([row[6], row[7]])
		assert_int(def.ammo).is_equal(row[8])
		# Both kinds come from the airfield, so they fly, they are not a building, and they sit on
		# a pad of the airfield: no aircraft is a harvester or a producer.
		assert_array([def.harvest_capacity, def.carry_slots, def.repair_classes]).is_equal(
			[0, 0, 0]
		)
		assert_array(Rules.air_problems(id, def)).override_failure_message(id).is_empty()
		var faction: FactionDef = load("res://data/factions/%s.tres" % row[0])
		assert_bool(faction.roster.has(def)).override_failure_message(id).is_false()


## ADR 0036 sections 5 and 6: a fighter hits high air only and has no ammo limit (so no rearm
## time); a bomber hits the ground only, carries 2 bombs and has a rearm time.
func test_fighters_have_no_ammo_and_bombers_two_bombs_with_a_rearm_time() -> void:
	for id: String in AIRCRAFT:
		var def: UnitDef = _unit(id)
		var fighter: bool = id.ends_with("fighter")
		assert_int(def.weapon.targets).override_failure_message(id).is_equal(
			World.Layer.AIR if fighter else World.Layer.GROUND
		)
		assert_int(def.ammo).override_failure_message(id).is_equal(0 if fighter else 2)
		assert_bool(def.rearm_ticks == 0).override_failure_message(id).is_equal(fighter)
		assert_int(def.weapon.vs_armour.size()).is_equal(4)
		assert_int(def.acquire_range).is_equal(def.weapon.range)
	# The bombs beat buildings and tanks, and are worse against a squad than against both.
	for id: String in ["drillhead_bombs", "sunfall_bombs"]:
		var gun: WeaponDef = load("res://data/weapons/%s.tres" % id) as WeaponDef
		assert_int(gun.vs_armour[World.Armour.BUILDING]).is_greater(
			gun.vs_armour[World.Armour.HEAVY]
		)
		assert_int(gun.vs_armour[World.Armour.INFANTRY]).is_less(gun.vs_armour[World.Armour.LIGHT])


## The two factions differ as the GDD says: the Lumen Accord's aircraft are faster and weaker.
func test_the_lumen_accord_aircraft_are_faster_and_weaker() -> void:
	for kind: String in ["fighter", "bomber"]:
		var fossil: UnitDef = _unit("fossil_" + kind)
		var renew: UnitDef = _unit("renew_" + kind)
		assert_int(renew.speed).is_greater(fossil.speed)
		assert_int(renew.max_hp).is_less(fossil.max_hp)


## ADR 0032 and the legal screen of ADR 0036 section 16: a name fits one line and is the GDD's.
func test_the_names_fit_one_line() -> void:
	for id: String in FIELDS:
		assert_int(FIELDS[id][1].length()).override_failure_message(id).is_less_equal(MAX_NAME)
	for id: String in AIRCRAFT:
		assert_int(AIRCRAFT[id][1].length()).override_failure_message(id).is_less_equal(MAX_NAME)


## The art id is the type id (WorldSort bakes by it). The models, when P245 and P245b land, are
## the data footprint for a building.
func test_the_art_model_when_present_has_the_data_footprint() -> void:
	for id: String in FIELDS:
		var path: String = "res://assets/art/models/%s/%s.tres" % [FIELDS[id][0], id]
		if not ResourceLoader.exists(path):
			continue  # P245b's art row is not merged yet.
		var model: ArtModel = load(path) as ArtModel
		assert_str(String(model.art_id)).is_equal(id)
		assert_int(model.footprint).is_equal(3)
