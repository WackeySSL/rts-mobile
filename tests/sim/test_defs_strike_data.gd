extends GdUnitTestSuite
## The strike numbers of the shipped data (plan row P110d, ADR 0023 sections 7 and 10, docs/GDD.md
## "Superweapons"): each faction file lists exactly one strike building, of its own kind (the
## Derrick League's Deep Bore ruptures, the Lumen Accord's Blackout Array blacks out), with every
## number its kind reads present and positive and the numbers it does not read left at 0; the
## starting values are the GDD's times and radii in ticks and milli-tiles; the rupture's weapon is a
## file of its own that no unit fires; no other file has a strike; and the perf arena, which lists
## no faction, loads none of it (its golden hashes stand on that). The checks are one function, run
## over the shipped files and over hand-built files that each break one rule. What the sim does
## with the numbers is test_strike_shipped's (on these files) and the P110 and P111 suites' (on a
## rig). The numbers are proposals for Phase 4's balance runs (ADR 0023 section 10, marked P).

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const UNITS_DIR: String = "res://data/units"
const WEAPONS_DIR: String = "res://data/weapons"
const FACTIONS_DIR: String = "res://data/factions"
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const RUPTURE: int = Strike.Kind.RUPTURE
const BLACKOUT: int = Strike.Kind.BLACKOUT
## The kind of strike each faction has, by faction id: no two share one.
const KINDS: Dictionary[String, int] = {"fossil": RUPTURE, "renew": BLACKOUT}


func test_each_faction_has_exactly_one_strike_type_of_its_own_kind_with_every_number() -> void:
	var seen: Dictionary[int, String] = {}
	var ids: Array[String] = []
	for path: String in FileScan.list_files(FACTIONS_DIR, ".tres"):
		var faction: FactionDef = load(path)
		ids.append(String(faction.id))
		assert_bool(KINDS.has(String(faction.id))).override_failure_message(path).is_true()
		var kind: int = KINDS.get(String(faction.id), -1)
		assert_array(_strike_problems(faction, kind)).override_failure_message(path).is_empty()
		assert_bool(seen.has(kind)).override_failure_message(path).is_false()
		seen[kind] = String(faction.id)
	assert_array(ids).contains_exactly_in_any_order(KINDS.keys())
	# Which building it is: the one the ADR's table gives each faction.
	assert_array(_strike_ids(load(FACTIONS_DIR + "/fossil.tres"))).is_equal(["fossil_strike"])
	assert_array(_strike_ids(load(FACTIONS_DIR + "/renew.tres"))).is_equal(["renew_strike"])


## The starting values are the GDD's: a charge of five minutes from placement, a warning of three
## seconds, a rupture within three tiles, a blackout of enemy buildings within four tiles for thirty
## seconds (ADR 0023 section 10: 4500, 45, 3000, 4000 and 450). Ticks are seconds times the tick
## rate, radii are tiles times the milli-tiles of a tile; the cost and the power are the roster's.
func test_the_strike_files_hold_the_gdd_times_and_radii_in_ticks_and_milli_tiles() -> void:
	var bore: BuildingDef = load(UNITS_DIR + "/fossil_strike.tres")
	var array: BuildingDef = load(UNITS_DIR + "/renew_strike.tres")
	var charge: int = 5 * 60 * Sim.TICK_RATE
	assert_array(_numbers(bore)).is_equal(
		[RUPTURE, charge, 3 * World.MILLI_PER_TILE, 3 * Sim.TICK_RATE, 0]
	)
	assert_array(_numbers(array)).is_equal(
		[BLACKOUT, charge, 4 * World.MILLI_PER_TILE, 0, 30 * Sim.TICK_RATE]
	)
	assert_int(bore.charge_ticks).is_equal(4500)
	assert_object(array.strike_weapon).is_null()


## The rupture's weapon: damage 600 at 100 percent against every armour class (ADR 0023 section
## 10 gives 600 and the building's 100 percent, and the GDD "heavy damage" to everything within the
## radius, own rows included, so the other classes take the same percent), in a file of its own
## named by its id. Nothing fires it from a position, so it has no range, minimum range or flight.
func test_the_rupture_weapon_file_holds_its_starting_stats() -> void:
	var weapon: WeaponDef = (load(UNITS_DIR + "/fossil_strike.tres") as BuildingDef).strike_weapon
	assert_str(weapon.resource_path).is_equal(WEAPONS_DIR + "/fossil_rupture.tres")
	assert_str(String(weapon.id)).is_equal("fossil_rupture")
	assert_int(weapon.damage).is_equal(600)
	assert_array(Array(weapon.vs_armour)).is_equal([100, 100, 100, 100])
	assert_array([weapon.range, weapon.min_range, weapon.projectile_speed]).is_equal([0, 0, 0])


## A strike weapon is nobody's gun: no unit or building file holds it as its `weapon` (the only way
## Combat and Targeting reach a weapon), and no gun has its id (the World merges weapons by id, the
## first winning). Every file but the two strike buildings has no strike at all: kind 0, the numbers
## 0 and no weapon, so a strike cannot hide in another roster entry.
func test_no_unit_fires_the_strike_weapon_and_no_other_file_has_a_strike() -> void:
	var weapon_id: StringName = &"fossil_rupture"
	var struck: Array[String] = []
	for path: String in FileScan.list_files(UNITS_DIR, ".tres"):
		var unit: UnitDef = load(path)
		var file: String = path.get_file()
		if unit.weapon != null:
			assert_bool(unit.weapon.id == weapon_id).override_failure_message(file).is_false()
		var building: BuildingDef = unit as BuildingDef
		if building == null:
			continue
		if building.strike_kind > 0:
			struck.append(file.get_basename())
			continue
		assert_array(_numbers(building)).override_failure_message(file).is_equal([0, 0, 0, 0, 0])
		assert_object(building.strike_weapon).override_failure_message(file).is_null()
	assert_array(struck).contains_exactly_in_any_order(["fossil_strike", "renew_strike"])


## The perf arena lists no faction and its three unit files name no strike, so its World has three
## types, three weapons and no strike table entry (the pads of every type): the data of this row
## never reaches it, and the golden hashes and the hash-bytes watch line of tests/perf stand as
## P109 pinned them.
func test_the_perf_arena_loads_none_of_the_strike_data() -> void:
	var world: World = World.from_scenario(load(ARENA_PATH) as ScenarioDef)
	var types: Array[StringName] = [&"light_tank", &"rifle_squad", &"rocket_squad"]
	assert_array(world.type_ids).contains_exactly_in_any_order(types)
	var weapons: Array[StringName] = [&"tank_cannon", &"rifle", &"rocket"]
	assert_array(world.weapon_ids).contains_exactly_in_any_order(weapons)
	var kinds: PackedInt32Array = world.type_strike_kind
	assert_int(kinds.size()).is_equal(types.size())
	assert_int(kinds.count(0)).is_equal(types.size())
	assert_int(world.type_strike_weapon.count(-1)).is_equal(types.size())


func test_the_strike_checks_report_the_kind_the_count_and_each_number_that_breaks_a_rule() -> void:
	assert_array(_strike_problems(_faction([_bore()]), RUPTURE)).is_empty()
	assert_array(_strike_problems(_faction([_array()]), BLACKOUT)).is_empty()
	# Not exactly one strike type: none (a plain building has kind 0), and two of one kind.
	var plain: BuildingDef = _building("plain")
	assert_array(_strike_problems(_faction([plain]), RUPTURE)).is_equal(
		["alpha: 0 strike types, not 1"]
	)
	var twice: Array = [_bore(), _bore()]
	assert_array(_strike_problems(_faction(twice), RUPTURE)).is_equal(
		["alpha: 2 strike types, not 1"]
	)
	# Another faction's kind, and each number of a rupture or a blackout that is 0, a number the
	# kind does not read that is set, a weapon that is missing and a weapon on a blackout.
	assert_array(_strike_problems(_faction([_array()]), RUPTURE)).is_equal(["array: kind 2, not 1"])
	var rupture: Array = [
		["charge_ticks", 0, "bore: charge_ticks is not above 0"],
		["strike_radius", 0, "bore: strike_radius is not above 0"],
		["strike_delay", 0, "bore: strike_delay is not above 0"],
		["strike_ticks", 1, "bore: strike_ticks is set, but a rupture does not read it"],
		["strike_weapon", null, "bore: no strike weapon"],
	]
	var blackout: Array = [
		["charge_ticks", 0, "array: charge_ticks is not above 0"],
		["strike_radius", 0, "array: strike_radius is not above 0"],
		["strike_ticks", 0, "array: strike_ticks is not above 0"],
		["strike_delay", 1, "array: strike_delay is set, but a blackout does not read it"],
		["strike_weapon", _gun(), "array: a blackout holds a strike weapon"],
	]
	for row: Array in rupture:
		var broken: BuildingDef = _bore()
		broken.set(row[0], row[1])
		var got: PackedStringArray = _strike_problems(_faction([broken]), RUPTURE)
		assert_array(got).override_failure_message(row[0]).is_equal([row[2]])
	for row: Array in blackout:
		var broken: BuildingDef = _array()
		broken.set(row[0], row[1])
		var got: PackedStringArray = _strike_problems(_faction([broken]), BLACKOUT)
		assert_array(got).override_failure_message(row[0]).is_equal([row[2]])


func test_the_strike_checks_report_each_weapon_stat_that_breaks_a_rule() -> void:
	var rows: Array = [
		["damage", 0, "bore: strike weapon damage is below 1"],
		["range", 1, "bore: strike weapon has a range, a minimum range or a flight"],
		["min_range", 1, "bore: strike weapon has a range, a minimum range or a flight"],
		["projectile_speed", 1, "bore: strike weapon has a range, a minimum range or a flight"],
		[
			"vs_armour",
			PackedInt32Array([100, 100, 100]),
			"bore: vs_armour is not 4 percents in 0..200"
		],
		[
			"vs_armour",
			PackedInt32Array([100, 100, 100, 201]),
			"bore: vs_armour is not 4 percents in 0..200"
		],
		[
			"vs_armour",
			PackedInt32Array([-1, 100, 100, 100]),
			"bore: vs_armour is not 4 percents in 0..200"
		],
		["id", &"gun", "bore: strike weapon id gun differs from its file name"],
	]
	for row: Array in rows:
		var broken: BuildingDef = _bore()
		broken.strike_weapon.set(row[0], row[1])
		var got: PackedStringArray = _strike_problems(_faction([broken]), RUPTURE)
		assert_array(got).override_failure_message(str(row[0], row[1])).is_equal([row[2]])


## One text per broken rule of the strike data of `faction` for its `kind`: exactly one building in
## the roster with a strike kind above 0, of that kind; the numbers the kind reads above 0 (the
## charge and the radius, and a rupture's warning and weapon, or a blackout's length) and the
## others 0 (a blackout holds no weapon); and the weapon with damage, four percents in 0..200, no
## range, minimum range or flight, and an id equal to its file name.
func _strike_problems(faction: FactionDef, kind: int) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var found: Array[BuildingDef] = []
	for member: UnitDef in faction.roster:
		var building: BuildingDef = member as BuildingDef
		if building != null and building.strike_kind > 0:
			found.append(building)
	if found.size() != 1:
		problems.append("%s: %d strike types, not 1" % [faction.id, found.size()])
		return problems
	var strike: BuildingDef = found[0]
	var name: String = String(strike.type_id)
	if strike.strike_kind != kind:
		problems.append("%s: kind %d, not %d" % [name, strike.strike_kind, kind])
		return problems
	var read: Dictionary[String, int] = {
		"charge_ticks": strike.charge_ticks, "strike_radius": strike.strike_radius
	}
	var unread: Dictionary[String, int] = {}
	if kind == RUPTURE:
		read["strike_delay"] = strike.strike_delay
		unread["strike_ticks"] = strike.strike_ticks
	else:
		read["strike_ticks"] = strike.strike_ticks
		unread["strike_delay"] = strike.strike_delay
	for key: String in read:
		if read[key] < 1:
			problems.append("%s: %s is not above 0" % [name, key])
	var reader: String = "rupture" if kind == RUPTURE else "blackout"
	for key: String in unread:
		if unread[key] != 0:
			problems.append("%s: %s is set, but a %s does not read it" % [name, key, reader])
	if kind == BLACKOUT:
		if strike.strike_weapon != null:
			problems.append("%s: a blackout holds a strike weapon" % name)
	elif strike.strike_weapon == null:
		problems.append("%s: no strike weapon" % name)
	else:
		problems.append_array(_weapon_problems(name, strike.strike_weapon))
	return problems


func _weapon_problems(name: String, weapon: WeaponDef) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var percents: Array = Array(weapon.vs_armour)
	if weapon.damage < 1:
		problems.append("%s: strike weapon damage is below 1" % name)
	if weapon.range != 0 or weapon.min_range != 0 or weapon.projectile_speed != 0:
		problems.append("%s: strike weapon has a range, a minimum range or a flight" % name)
	if percents.size() != 4 or percents.min() < 0 or percents.max() > 200:
		problems.append("%s: vs_armour is not 4 percents in 0..200" % name)
	var file: String = weapon.resource_path.get_file().get_basename()
	if String(weapon.id) != file:
		problems.append("%s: strike weapon id %s differs from its file name" % [name, weapon.id])
	return problems


## The ids of the faction's roster entries that have a strike kind, in roster order.
func _strike_ids(faction: FactionDef) -> Array[String]:
	var ids: Array[String] = []
	for member: UnitDef in faction.roster:
		var building: BuildingDef = member as BuildingDef
		if building != null and building.strike_kind > 0:
			ids.append(String(building.type_id))
	return ids


## The kind and the four numbers of a building's strike, in the order of its exports.
func _numbers(building: BuildingDef) -> Array[int]:
	return [
		building.strike_kind,
		building.charge_ticks,
		building.strike_radius,
		building.strike_delay,
		building.strike_ticks,
	]


func _faction(roster: Array) -> FactionDef:
	var faction: FactionDef = FactionDef.new()
	faction.id = &"alpha"
	faction.roster.assign(roster)
	return faction


func _building(id: String) -> BuildingDef:
	var building: BuildingDef = BuildingDef.new()
	building.type_id = StringName(id)
	return building


## A rupture building that breaks no rule.
func _bore() -> BuildingDef:
	var building: BuildingDef = _building("bore")
	building.strike_kind = RUPTURE
	building.charge_ticks = 4500
	building.strike_radius = 3000
	building.strike_delay = 45
	building.strike_weapon = _gun()
	return building


func _array() -> BuildingDef:
	var building: BuildingDef = _building("array")
	building.strike_kind = BLACKOUT
	building.charge_ticks = 4500
	building.strike_radius = 4000
	building.strike_ticks = 450
	return building


## A weapon that breaks no rule. It is no file, so its path and its id are both empty: the checks
## compare the one with the other, and a Resource path can be taken by one object only.
func _gun() -> WeaponDef:
	var weapon: WeaponDef = WeaponDef.new()
	weapon.damage = 600
	return weapon
