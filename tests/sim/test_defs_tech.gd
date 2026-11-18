extends GdUnitTestSuite
## The engineering centres and the four upgrades (plan row P247, ADR 0036 sections 2 and 10,
## docs/GDD.md): one 2x2 centre per faction behind the airfield that produces the RESEARCH tab,
## and two bomber upgrades per faction, heavier bombs (+25 % damage dealt) and a tougher hull
## (-25 % damage taken). Data only in P247; P249 (the art row) added the roster entries and item
## cards, filled `FactionDef.upgrades` and wrote the HOW_TO_PLAY rows. The GDD gives the names,
## size, cost, power, requirement and the two percentages. Hit points (900), build time (360
## ticks), sight (5000) and the research cost and time (800 credits, 1350 ticks, equal for the
## bomb and the hull upgrade) are the lead's starting values (P26bw), in the GDD's tech note, for
## P255 to tune.
## The damage-dealt upgrades are keyed on faction, weapon and stat (P246's rule), so each names the
## bomber's own bombs. What the sim does with them is test_upgrades'.

## type id: faction, name, requires.
const CENTRES: Dictionary[String, Array] = {
	"fossil_engineering": ["fossil", "Draft Shop", "fossil_airfield"],
	"renew_engineering": ["renew", "Lens Works", "renew_airfield"],
}
## id: faction, name, centre, bomber, bombs, stat, value, cost, research ticks.
const UPGRADES: Dictionary[String, Array] = {
	"heavy_bombs":
	[
		"fossil",
		"Heavy Bombs",
		"fossil_engineering",
		"fossil_bomber",
		"drillhead_bombs",
		UpgradeDef.Stat.DAMAGE_DEALT,
		125,
		800,
		1350
	],
	"plated_hull":
	[
		"fossil",
		"Plated Hull",
		"fossil_engineering",
		"fossil_bomber",
		"drillhead_bombs",
		UpgradeDef.Stat.DAMAGE_TAKEN,
		75,
		800,
		1350
	],
	"focus_bombs":
	[
		"renew",
		"Focus Bombs",
		"renew_engineering",
		"renew_bomber",
		"sunfall_bombs",
		UpgradeDef.Stat.DAMAGE_DEALT,
		125,
		800,
		1350
	],
	"glaze_hull":
	[
		"renew",
		"Glaze Hull",
		"renew_engineering",
		"renew_bomber",
		"sunfall_bombs",
		UpgradeDef.Stat.DAMAGE_TAKEN,
		75,
		800,
		1350
	],
}
## ADR 0032: a name fits one line of the item card, at most about 11 characters.
const MAX_NAME: int = 11
const Rules: GDScript = preload("res://tests/sim/support/air_rules.gd")
const FileScan: GDScript = preload("res://tests/support/file_scan.gd")


func _building(id: String) -> BuildingDef:
	return load("res://data/units/%s.tres" % id) as BuildingDef


func _upgrade(id: String) -> UpgradeDef:
	return load("res://data/upgrades/%s.tres" % id) as UpgradeDef


func test_each_faction_has_an_engineering_centre_with_the_gdd_and_starting_numbers() -> void:
	for id: String in CENTRES:
		var def: BuildingDef = _building(id)
		assert_object(def).override_failure_message(id).is_not_null()
		assert_str(String(def.type_id)).is_equal(id)
		assert_str(String(def.faction)).is_equal(CENTRES[id][0])
		assert_str(def.display_name).is_equal(CENTRES[id][1])
		assert_str(String(def.requires.type_id)).is_equal(CENTRES[id][2])
		# GDD: size, cost, power. The tab is the structures drawer's.
		assert_array([def.footprint, def.cost, def.power, def.tab]).is_equal(
			[Vector2i(2, 2), 1200, -40, World.Tab.STRUCTURES]
		)
		assert_int(def.produces).is_equal(World.Tab.RESEARCH)
		# The lead's starting values (P26bw), GDD tech note.
		assert_array([def.max_hp, def.build_ticks, def.sight_range]).is_equal([900, 360, 5000])
		assert_array([def.speed, def.radius, def.armour, def.strike_kind, def.pads]).is_equal(
			[0, 0, World.Armour.BUILDING, 0, 0]
		)
		assert_object(def.weapon).is_null()
		assert_array(Rules.air_problems("%s.tres" % id, def)).is_empty()
		# P249 rostered the centre (art, item card).
		var faction: FactionDef = load("res://data/factions/%s.tres" % CENTRES[id][0])
		assert_bool(faction.roster.has(def)).override_failure_message(id).is_true()


func test_each_upgrade_has_its_values_and_changes_its_factions_bomber() -> void:
	assert_int(UPGRADES.size()).is_equal(4)
	for id: String in UPGRADES:
		var row: Array = UPGRADES[id]
		var up: UpgradeDef = _upgrade(id)
		assert_object(up).override_failure_message(id).is_not_null()
		assert_str(String(up.id)).is_equal(id)
		assert_str(String(up.faction)).is_equal(row[0])
		assert_str(up.display_name).is_equal(row[1])
		assert_str(String(up.requires.type_id)).is_equal(row[2])
		# GDD: the stat and the percent. Cost and time are the lead's starting values (P26bw).
		assert_array([up.stat, up.value, up.cost, up.research_ticks]).is_equal(
			[row[5], row[6], row[7], row[8]]
		)
		assert_int(up.applies_to.size()).is_equal(1)
		assert_str(String(up.applies_to[0].type_id)).is_equal(row[3])
		assert_str(String(up.applies_to[0].weapon.id)).is_equal(row[4])
		assert_array(Rules.upgrade_problems("%s.tres" % id, up, StringName(row[0]))).is_empty()


## The GDD: +25 % damage dealt and -25 % damage taken, a fixed percent each.
func test_the_percentages_are_plus_and_minus_a_quarter() -> void:
	for id: String in UPGRADES:
		var up: UpgradeDef = _upgrade(id)
		var want: int = 125 if up.stat == UpgradeDef.Stat.DAMAGE_DEALT else 75
		assert_int(up.value).override_failure_message(id).is_equal(want)


## P246's data rule: a damage-dealt upgrade is keyed on faction, weapon and stat. The catalog of
## the four upgrades, put on their factions here (as P249's shipped lists have them), has
## no clash, no repeated id and no id that is also a type id.
func test_the_catalog_rule_holds_for_the_four_upgrades() -> void:
	var units: Array[UnitDef] = []
	for path: String in FileScan.list_files("res://data/units", ".tres"):
		units.append(load(path) as UnitDef)
	var factions: Array[FactionDef] = []
	for faction_id: String in ["fossil", "renew"]:
		var shipped: FactionDef = load("res://data/factions/%s.tres" % faction_id)
		var copy: FactionDef = FactionDef.new()
		copy.id = shipped.id
		for id: String in UPGRADES:
			if UPGRADES[id][0] == faction_id:
				copy.upgrades.append(_upgrade(id))
		factions.append(copy)
	assert_array(Rules.upgrade_catalog_problems(units, factions)).is_empty()
	# Two upgrades on one weapon and stat clash.
	var twin: UpgradeDef = _upgrade("heavy_bombs").duplicate() as UpgradeDef
	twin.id = &"twin_bombs"
	factions[0].upgrades.append(twin)
	assert_array(Rules.upgrade_catalog_problems(units, factions)).is_equal(
		["heavy_bombs and twin_bombs change one stat of drillhead_bombs"]
	)


## P249 filled `FactionDef.upgrades` (the research tiles and `WorldLoad._upgrade_for` read it), two
## per faction in the Research tab's order: the bomb upgrade, then the hull upgrade.
func test_the_shipped_factions_list_their_two_upgrades() -> void:
	var want: Dictionary[String, Array] = {
		"fossil": ["heavy_bombs", "plated_hull"], "renew": ["focus_bombs", "glaze_hull"]
	}
	for faction_id: String in want:
		var faction: FactionDef = load("res://data/factions/%s.tres" % faction_id)
		var ids: Array[String] = []
		for up: UpgradeDef in faction.upgrades:
			ids.append(String(up.id))
			assert_str(String(up.faction)).is_equal(faction_id)
		assert_array(ids).override_failure_message(faction_id).is_equal(want[faction_id])


func test_the_names_fit_one_line() -> void:
	for id: String in CENTRES:
		assert_int(CENTRES[id][1].length()).override_failure_message(id).is_less_equal(MAX_NAME)
	for id: String in UPGRADES:
		assert_int(UPGRADES[id][1].length()).override_failure_message(id).is_less_equal(MAX_NAME)
