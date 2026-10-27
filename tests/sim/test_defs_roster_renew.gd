extends GdUnitTestSuite
## The Lumen Accord's roster (plan row P108, ADR 0023 sections 6, 7 and 10, docs/GDD.md): its eight
## buildings, six units and the two weapons of its own as literals (the ADR's starting numbers,
## marked P: proposals for Phase 4's balance runs), the rules that span its files (the requirement
## chains, the free Fuel Runner, the dock and exit cells, the tabs) and how it differs from the
## Derrick League: only where the ADR's table says so. test_defs_roster pins the Derrick League's
## files the same way. The rules every file obeys and the faction rules are test_defs_data's and
## test_defs_factions_data's, which run over these files too.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const Cells: GDScript = preload("res://tests/sim/support/roster_cells.gd")
const UNITS_DIR: String = "res://data/units"
const WEAPONS_DIR: String = "res://data/weapons"
const FACTION_PATH: String = "res://data/factions/renew.tres"
## The faction whose files these cases read (UnitDef.faction).
const FACTION: StringName = &"renew"
## The sidebar tabs (World.Tab).
const STRUCTURES: int = 0
const INFANTRY: int = 1
const VEHICLES: int = 2
## The Derrick League file and the Lumen Accord file of each role, in the roster's order (ADR 0023
## section 7's table).
const PAIRS: Array[Array] = [
	["headquarters", "renew_hq"],
	["power_plant", "renew_power"],
	["refinery", "renew_refinery"],
	["barracks", "renew_barracks"],
	["vehicle_factory", "renew_factory"],
	["fossil_radar", "renew_radar"],
	["defence_turret", "renew_defence"],
	["fossil_strike", "renew_strike"],
	["rifle_squad", "renew_rifle"],
	["rocket_squad", "renew_rocket"],
	["light_tank", "renew_scout"],
	["heavy_tank", "renew_tank"],
	["artillery", "renew_artillery"],
	["harvester", "renew_tanker"],
]
## The fields in which a role does not differ (the ADR's asymmetries are numbers, never the class
## of armour or movement, the size of the figure or the place in the sidebar).
const SAME_FIELDS: Array[String] = [
	"tab", "armour", "move_class", "radius", "selection_radius", "formation_spacing"
]
## Where the table says the Lumen Accord differs: the Derrick League file, the Lumen Accord file,
## the field and the sign of (Lumen value minus Derrick value). Cheaper, weaker, faster, tougher.
const CHARACTER: Array[Array] = [
	["power_plant", "renew_power", "cost", -1],
	["power_plant", "renew_power", "power", -1],
	["rifle_squad", "renew_rifle", "speed", 1],
	["rifle_squad", "renew_rifle", "max_hp", -1],
	["light_tank", "renew_scout", "speed", 1],
	["light_tank", "renew_scout", "max_hp", -1],
	["heavy_tank", "renew_tank", "speed", 1],
	["heavy_tank", "renew_tank", "max_hp", -1],
	["artillery", "renew_artillery", "max_hp", -1],
	["harvester", "renew_tanker", "speed", 1],
	["harvester", "renew_tanker", "harvest_capacity", -1],
]


func test_the_faction_file_lists_the_eight_buildings_and_the_six_units_in_the_adr_order() -> void:
	var wanted: Array[String] = [
		"renew_hq",
		"renew_power",
		"renew_refinery",
		"renew_barracks",
		"renew_factory",
		"renew_radar",
		"renew_defence",
		"renew_strike",
		"renew_rifle",
		"renew_rocket",
		"renew_scout",
		"renew_tank",
		"renew_artillery",
		"renew_tanker",
	]
	var faction: FactionDef = load(FACTION_PATH)
	var listed: Array[String] = []
	for member: UnitDef in faction.roster:
		listed.append(String(member.type_id))
	assert_array(listed).is_equal(wanted)
	for at: int in wanted.size():
		var member: UnitDef = faction.roster[at]
		assert_bool(member is BuildingDef).override_failure_message(wanted[at]).is_equal(at < 8)
		assert_str(member.resource_path).is_equal("%s/%s.tres" % [UNITS_DIR, wanted[at]])
		assert_str(String(member.faction)).override_failure_message(wanted[at]).is_equal("renew")
	# The files that name the faction are those fourteen and no other.
	var files: Array[String] = []
	for path: String in _own_files():
		files.append(path.get_file().get_basename())
	assert_array(files).contains_exactly_in_any_order(wanted)


func test_the_eight_building_files_hold_the_gdd_table_and_the_adr_starting_values() -> void:
	# id, footprint, cost, power, requires, produces (a tab, -1 none), tab (-1 = not buildable),
	# build_ticks, max_hp, weapon. The Wind Park costs 250 and makes +80 (ADR 0023 section 7); the
	# Rail Battery fires the anti-vehicle gun that the Redoubt gave up.
	var expected: Array = [
		["renew_hq", Vector2i(3, 3), 0, 20, "", STRUCTURES, -1, 0, 2000, ""],
		["renew_power", Vector2i(2, 2), 250, 80, "renew_hq", -1, STRUCTURES, 150, 800, ""],
		["renew_refinery", Vector2i(3, 3), 1400, -30, "renew_power", -1, STRUCTURES, 375, 1500, ""],
		[
			"renew_barracks",
			Vector2i(2, 2),
			400,
			-20,
			"renew_power",
			INFANTRY,
			STRUCTURES,
			150,
			1000,
			"",
		],
		[
			"renew_factory",
			Vector2i(3, 3),
			1800,
			-40,
			"renew_refinery",
			VEHICLES,
			STRUCTURES,
			450,
			1600,
			"",
		],
		["renew_radar", Vector2i(2, 2), 800, -30, "renew_refinery", -1, STRUCTURES, 300, 800, ""],
		[
			"renew_defence",
			Vector2i(1, 1),
			600,
			-20,
			"renew_barracks",
			-1,
			STRUCTURES,
			225,
			900,
			"turret_gun",
		],
		["renew_strike", Vector2i(3, 3), 2500, -60, "renew_radar", -1, STRUCTURES, 600, 1500, ""],
	]
	var got: Array = []
	for row: Array in expected:
		got.append(_building_row(row[0]))
	assert_array(got).is_equal(expected)


func test_the_buildings_see_around_them_and_only_the_rail_battery_acquires() -> void:
	# id, display_name, sight_range, acquire_range. A building sees (fog) and the battery fires at
	# what its weapon reaches, so its acquire_range covers the range and its sight covers that.
	var expected: Array = [
		["renew_hq", "Grid Hub", 7000, 0],
		["renew_power", "Wind Park", 5000, 0],
		["renew_refinery", "Synthesis Works", 5000, 0],
		["renew_barracks", "Crew Hall", 5000, 0],
		["renew_factory", "Motor Works", 5000, 0],
		["renew_radar", "Relay Tower", 5000, 0],
		["renew_defence", "Rail Battery", 7000, 5500],
		["renew_strike", "Blackout Array", 5000, 0],
	]
	var got: Array = []
	for row: Array in expected:
		var unit: UnitDef = _unit(row[0])
		got.append([row[0], unit.display_name, unit.sight_range, unit.acquire_range])
	assert_array(got).is_equal(expected)
	assert_int(_unit("renew_defence").weapon.range).is_less_equal(
		_unit("renew_defence").acquire_range
	)


func test_the_six_unit_files_hold_the_gdd_costs_build_times_tabs_and_ranges() -> void:
	# id, tab, cost, build_ticks, weapon id ("" = unarmed), weapon range, weapon min_range. Ranges
	# in milli-tiles: Breakers 5.5 tiles, Arcline 10 (minimum 3).
	var expected: Array = [
		["renew_rifle", INFANTRY, 100, 75, "rifle", 4000, 0],
		["renew_rocket", INFANTRY, 300, 150, "breaker_rocket", 5500, 0],
		["renew_scout", VEHICLES, 600, 225, "tank_cannon", 4500, 0],
		["renew_tank", VEHICLES, 1000, 330, "heavy_cannon", 5000, 0],
		["renew_artillery", VEHICLES, 900, 300, "arcline_gun", 10000, 3000],
		["renew_tanker", VEHICLES, 1200, 300, "", 0, 0],
	]
	var got: Array = []
	for row: Array in expected:
		var unit: UnitDef = _unit(row[0])
		var weapon: WeaponDef = unit.weapon
		(
			got
			. append(
				[
					row[0],
					unit.tab,
					unit.cost,
					unit.build_ticks,
					"" if weapon == null else String(weapon.id),
					0 if weapon == null else weapon.range,
					0 if weapon == null else weapon.min_range,
				]
			)
		)
	assert_array(got).is_equal(expected)


func test_the_six_unit_files_hold_their_body_stats() -> void:
	# id, display_name, speed, radius, selection_radius, formation_spacing, max_hp, armour (0
	# infantry, 1 light, 2 heavy), move_class (0 foot, 2 tracked: one field per goal for a mixed
	# group), sight_range, acquire_range. The Fuel Runner is unarmed, so it acquires nothing;
	# Linemen 80 hp, Swift 220, Torque 520, Arcline 160 (ADR 0023 section 7).
	var expected: Array = [
		["renew_rifle", "Linemen", 73, 300, 350, 900, 80, 0, 0, 6000, 5000],
		["renew_rocket", "Breakers", 60, 300, 350, 900, 90, 0, 0, 6000, 6000],
		["renew_scout", "Swift", 147, 400, 500, 1200, 220, 1, 2, 7000, 5500],
		["renew_tank", "Torque", 93, 450, 500, 1300, 520, 2, 2, 7000, 5500],
		["renew_artillery", "Arcline", 67, 400, 500, 1200, 160, 1, 2, 10000, 10000],
		["renew_tanker", "Fuel Runner", 93, 450, 650, 1400, 800, 1, 2, 5000, 0],
	]
	var got: Array = []
	for row: Array in expected:
		var unit: UnitDef = _unit(row[0])
		(
			got
			. append(
				[
					row[0],
					unit.display_name,
					unit.speed,
					unit.radius,
					unit.selection_radius,
					unit.formation_spacing,
					unit.max_hp,
					unit.armour,
					unit.move_class,
					unit.sight_range,
					unit.acquire_range,
				]
			)
		)
	assert_array(got).is_equal(expected)


## Speeds are milli-tiles per tick, rounded in the data (the skill rts-sim-conventions): the GDD's
## tiles per second in thousandths, over the tick rate, rounded half up.
@warning_ignore("integer_division")
func test_every_speed_is_the_gdd_tiles_per_second_rounded_to_milli_tiles_per_tick() -> void:
	# id, speed in milli-tiles per second: Linemen 1.1, Breakers 0.9, Swift 2.2, Torque 1.4,
	# Arcline 1.0 and Fuel Runner 1.4 tiles/s.
	var per_second: Array = [
		["renew_rifle", 1100],
		["renew_rocket", 900],
		["renew_scout", 2200],
		["renew_tank", 1400],
		["renew_artillery", 1000],
		["renew_tanker", 1400],
	]
	for row: Array in per_second:
		var rounded: int = (2 * row[1] + Sim.TICK_RATE) / (2 * Sim.TICK_RATE)
		assert_int(_unit(row[0]).speed).override_failure_message(row[0]).is_equal(rounded)


func test_the_two_weapon_files_of_its_own_hold_their_starting_stats_and_the_rest_are_shared(
) -> void:
	# id, range, min_range, damage, cooldown_ticks, projectile_speed (0 = hitscan), then the
	# percent of damage against infantry, light, heavy and building armour. The Breakers' rocket
	# reaches 5.5 tiles and the Arcline's gun 10; the other four weapons are the Derrick League's
	# own files, where the number is the same (the Rail Battery's is the one the Redoubt gave up).
	var weapons: Dictionary[String, Array] = {
		"breaker_rocket": ["breaker_rocket", 5500, 0, 50, 45, 300, [20, 100, 100, 80]],
		"arcline_gun": ["arcline_gun", 10000, 3000, 80, 60, 300, [60, 60, 50, 150]],
	}
	for id: String in weapons:
		assert_array(_weapon_row(id)).override_failure_message(id).is_equal(weapons[id])
	var shared: Dictionary[String, String] = {
		"renew_rifle": "rifle",
		"renew_rocket": "breaker_rocket",
		"renew_scout": "tank_cannon",
		"renew_tank": "heavy_cannon",
		"renew_artillery": "arcline_gun",
		"renew_defence": "turret_gun",
	}
	for id: String in shared:
		assert_str(_unit(id).weapon.resource_path).override_failure_message(id).is_equal(
			"%s/%s.tres" % [WEAPONS_DIR, shared[id]]
		)


## The requirement chains of ADR 0023 section 7: the power plant after the Headquarters, the
## refinery and the barracks after the power plant, the factory and the radar after the refinery,
## the defence after the barracks, artillery and the strike after the radar. Every one reaches the
## Grid Hub and stays in the faction (test_defs_factions_data runs that over every faction).
func test_every_requirement_chain_follows_the_adr_and_reaches_the_grid_hub() -> void:
	assert_array(_chain(_unit("renew_defence"))).is_equal(
		["renew_defence", "renew_barracks", "renew_power", "renew_hq"]
	)
	assert_array(_chain(_unit("renew_factory"))).is_equal(
		["renew_factory", "renew_refinery", "renew_power", "renew_hq"]
	)
	assert_array(_chain(_unit("renew_radar"))).is_equal(
		["renew_radar", "renew_refinery", "renew_power", "renew_hq"]
	)
	assert_array(_chain(_unit("renew_artillery"))).is_equal(
		["renew_artillery", "renew_radar", "renew_refinery", "renew_power", "renew_hq"]
	)
	assert_array(_chain(_unit("renew_strike"))).is_equal(
		["renew_strike", "renew_radar", "renew_refinery", "renew_power", "renew_hq"]
	)
	assert_array(_chain(_unit("renew_hq"))).is_equal(["renew_hq"])
	# A unit that names no requirement is gated by the producer of its tab alone.
	for id: String in ["renew_rifle", "renew_rocket", "renew_scout", "renew_tank", "renew_tanker"]:
		assert_object(_unit(id).requires).override_failure_message(id).is_null()


## The Lumen Accord mirrors the Derrick League's roles (ADR 0023 section 7: "same role"): the same
## footprint, producer, class of armour and movement, size and tab, the dock and exit cells, and a
## requirement that is the twin of the Derrick League's. Read from the Derrick League's files.
func test_each_role_mirrors_the_derrick_leagues_in_everything_but_the_numbers_the_adr_names(
) -> void:
	var twin_of: Dictionary[String, String] = {}
	for pair: Array in PAIRS:
		twin_of[pair[0]] = pair[1]
	for pair: Array in PAIRS:
		var fossil: UnitDef = _unit(pair[0])
		var renew: UnitDef = _unit(pair[1])
		var label: String = pair[1]
		for field: String in SAME_FIELDS:
			assert_int(renew.get(field)).override_failure_message(label + " " + field).is_equal(
				fossil.get(field)
			)
		assert_bool(renew.weapon == null).override_failure_message(label).is_equal(
			fossil.weapon == null
		)
		var want_requires: String = ""
		if fossil.requires != null:
			want_requires = twin_of[String(fossil.requires.type_id)]
		var got_requires: String = ""
		if renew.requires != null:
			got_requires = String(renew.requires.type_id)
		assert_str(got_requires).override_failure_message(label).is_equal(want_requires)
		assert_bool(renew is BuildingDef).override_failure_message(label).is_equal(
			fossil is BuildingDef
		)
		if fossil is BuildingDef:
			var fossil_building: BuildingDef = fossil
			var renew_building: BuildingDef = renew
			assert_that(renew_building.footprint).override_failure_message(label).is_equal(
				fossil_building.footprint
			)
			assert_int(renew_building.produces).override_failure_message(label).is_equal(
				fossil_building.produces
			)
			assert_that(renew_building.dock).override_failure_message(label).is_equal(
				fossil_building.dock
			)
			assert_that(renew_building.exit).override_failure_message(label).is_equal(
				fossil_building.exit
			)


## Fast, precise and fragile (ADR 0023 section 7, docs/GDD.md): where the table makes the Lumen
## Accord differ it goes the stated way, and no Lumen unit is slower or tougher than its twin. The
## directions are read from the Derrick League's files, so a balance change keeps the faction's
## character as long as it keeps the sign.
func test_the_lumen_accord_differs_from_the_derrick_league_the_way_the_adr_says() -> void:
	for row: Array in CHARACTER:
		var fossil: UnitDef = _unit(row[0])
		var renew: UnitDef = _unit(row[1])
		var difference: int = int(renew.get(row[2])) - int(fossil.get(row[2]))
		assert_int(signi(difference)).override_failure_message("%s %s" % [row[1], row[2]]).is_equal(
			row[3]
		)
	# Longer reach: Breakers against Wildcatters, Arcline against the Mortar Rig.
	assert_int(_unit("renew_rocket").weapon.range).is_greater(_unit("rocket_squad").weapon.range)
	assert_int(_unit("renew_artillery").weapon.range).is_greater(_unit("artillery").weapon.range)
	for pair: Array in PAIRS:
		var fossil: UnitDef = _unit(pair[0])
		var renew: UnitDef = _unit(pair[1])
		if fossil is BuildingDef:
			continue
		assert_int(renew.speed).override_failure_message(pair[1]).is_greater_equal(fossil.speed)
		assert_int(renew.max_hp).override_failure_message(pair[1]).is_less_equal(fossil.max_hp)


## The Rail Battery fights vehicles (ADR 0023 section 7): its gun's percent is at least 80 against
## both vehicle classes and higher there than against infantry and buildings, and it does more
## damage a second to a vehicle and less to a squad than the Redoubt's anti-infantry gun. The
## expectations are read from the tables.
func test_the_rail_batterys_gun_is_strong_against_vehicles_and_weak_against_infantry() -> void:
	var rail: WeaponDef = _unit("renew_defence").weapon
	var redoubt: WeaponDef = _unit("defence_turret").weapon
	var percent: PackedInt32Array = rail.vs_armour
	assert_int(percent.size()).is_equal(World.Armour.size())
	for armour: int in [World.Armour.LIGHT, World.Armour.HEAVY]:
		assert_int(percent[armour]).override_failure_message(str(armour)).is_greater_equal(80)
		assert_int(percent[armour]).override_failure_message(str(armour)).is_greater(
			percent[World.Armour.INFANTRY]
		)
		assert_int(percent[armour]).override_failure_message(str(armour)).is_greater(
			percent[World.Armour.BUILDING]
		)
		assert_int(_per_second(rail, armour)).override_failure_message(str(armour)).is_greater(
			_per_second(redoubt, armour)
		)
	assert_int(_per_second(rail, World.Armour.INFANTRY)).is_less(
		_per_second(redoubt, World.Armour.INFANTRY)
	)


func test_the_fuel_runner_carries_450_is_unarmed_and_only_the_synthesis_works_brings_one() -> void:
	var tanker: UnitDef = _unit("renew_tanker")
	assert_int(tanker.harvest_capacity).is_equal(450)
	assert_object(tanker.weapon).is_null()
	var refinery: BuildingDef = _unit("renew_refinery") as BuildingDef
	assert_object(refinery.free_unit).is_not_null()
	assert_str(refinery.free_unit.resource_path).is_equal(tanker.resource_path)
	assert_str(String(refinery.free_unit.type_id)).is_equal("renew_tanker")
	# No other file of the faction carries ore or comes free with a building.
	for path: String in _own_files():
		var unit: UnitDef = load(path)
		var file: String = path.get_file()
		var carries: bool = unit.harvest_capacity > 0
		assert_bool(carries).override_failure_message(file).is_equal(file == "renew_tanker.tres")
		var free: bool = unit is BuildingDef and (unit as BuildingDef).free_unit != null
		assert_bool(free).override_failure_message(file).is_equal(file == "renew_refinery.tres")


func test_the_dock_and_exit_cells_are_the_middle_cell_south_of_the_footprint() -> void:
	# file, the offset it sets (dock or exit), where. The formula is the Derrick League's: column
	# footprint.x / 2, row footprint.y (P68c).
	var rows: Array = [
		["renew_refinery", "dock", Vector2i(1, 3)],
		["renew_factory", "exit", Vector2i(1, 3)],
		["renew_barracks", "exit", Vector2i(1, 2)],
	]
	var named: Dictionary[String, bool] = {}
	for row: Array in rows:
		var building: BuildingDef = _unit(row[0]) as BuildingDef
		var cell: Vector2i = building.get(row[1])
		assert_that(cell).override_failure_message("%s %s" % [row[0], row[1]]).is_equal(row[2])
		assert_that(cell).is_equal(Cells.south_middle(building.footprint))
		assert_bool(Cells.touches_footprint(building.footprint, cell)).is_true()
		named[row[0] + "." + row[1]] = true
	# Every other offset keeps the default, which no rule reads.
	for path: String in _own_files():
		var unit: UnitDef = load(path)
		if not unit is BuildingDef:
			continue
		var building: BuildingDef = unit
		var file: String = path.get_file().get_basename()
		if not named.has(file + ".dock"):
			assert_that(building.dock).override_failure_message(file + " dock").is_equal(
				Vector2i.ZERO
			)
		if not named.has(file + ".exit"):
			assert_that(building.exit).override_failure_message(file + " exit").is_equal(
				Vector2i.ZERO
			)


func test_every_buildable_file_has_a_tab_that_exactly_one_building_produces() -> void:
	var producers: Dictionary[int, Array] = {STRUCTURES: [], INFANTRY: [], VEHICLES: []}
	var buildable: Dictionary[int, Array] = {STRUCTURES: [], INFANTRY: [], VEHICLES: []}
	for path: String in _own_files():
		var unit: UnitDef = load(path)
		var id: String = String(unit.type_id)
		if unit is BuildingDef and (unit as BuildingDef).produces >= 0:
			producers[(unit as BuildingDef).produces].append(id)
		if unit.tab >= 0:
			buildable[unit.tab].append(id)
	assert_array(producers[STRUCTURES]).is_equal(["renew_hq"])
	assert_array(producers[INFANTRY]).is_equal(["renew_barracks"])
	assert_array(producers[VEHICLES]).is_equal(["renew_factory"])
	(
		assert_array(buildable[STRUCTURES])
		. is_equal(
			[
				"renew_barracks",
				"renew_defence",
				"renew_factory",
				"renew_power",
				"renew_radar",
				"renew_refinery",
				"renew_strike",
			]
		)
	)
	assert_array(buildable[INFANTRY]).is_equal(["renew_rifle", "renew_rocket"])
	assert_array(buildable[VEHICLES]).is_equal(
		["renew_artillery", "renew_scout", "renew_tank", "renew_tanker"]
	)


## What one hit of `gun` against armour class `armour` does in a second with no pause but the
## cooldown (a hit does `max(1, damage * percent / 100)`, as Combat has it).
@warning_ignore("integer_division")
func _per_second(gun: WeaponDef, armour: int) -> int:
	var hit: int = maxi(1, gun.damage * gun.vs_armour[armour] / 100)
	return hit * Sim.TICK_RATE / gun.cooldown_ticks


## The paths of the unit files that name the faction, in file order.
func _own_files() -> Array[String]:
	var found: Array[String] = []
	for path: String in FileScan.list_files(UNITS_DIR, ".tres"):
		if (load(path) as UnitDef).faction == FACTION:
			found.append(path)
	return found


## The type_ids from `unit` along `requires` to the end of the chain.
func _chain(unit: UnitDef) -> Array[String]:
	var ids: Array[String] = [String(unit.type_id)]
	var at: UnitDef = unit
	while at.requires != null and ids.size() < 16:
		at = at.requires
		ids.append(String(at.type_id))
	return ids


func _unit(id: String) -> UnitDef:
	var unit: UnitDef = load("%s/%s.tres" % [UNITS_DIR, id])
	assert_object(unit).override_failure_message("missing unit: " + id).is_not_null()
	return unit


func _building_row(id: String) -> Array:
	var building: BuildingDef = _unit(id) as BuildingDef
	if building == null:
		return ["not a building: " + id]
	return [
		id,
		building.footprint,
		building.cost,
		building.power,
		"" if building.requires == null else String(building.requires.type_id),
		building.produces,
		building.tab,
		building.build_ticks,
		building.max_hp,
		"" if building.weapon == null else String(building.weapon.id),
	]


func _weapon_row(id: String) -> Array:
	var weapon: WeaponDef = load("%s/%s.tres" % [WEAPONS_DIR, id])
	if weapon == null:
		return ["missing weapon: " + id]
	return [
		String(weapon.id),
		weapon.range,
		weapon.min_range,
		weapon.damage,
		weapon.cooldown_ticks,
		weapon.projectile_speed,
		Array(weapon.vs_armour),
	]
