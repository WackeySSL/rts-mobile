extends GdUnitTestSuite
## The Phase 3 roster (plan rows P72 and P107, ADR 0018 sections 8 and 9, ADR 0023 section 7,
## docs/GDD.md): the eight Derrick League buildings, the six units and the four weapons of the
## roster as literals, and the rules that span files: the requirement chains, the free tanker, the
## dock and exit cells. A type's art is pinned in tests/art from P99 on. The rules every single file
## obeys (a building has speed 0, radius 0 and armour Building; a mobile unit has a radius in
## 1..500; a weapon reaches the ring corner; a footprint is square) and the faction rules are
## test_defs_data's and test_defs_factions_data's, which run them over these files too. The unit
## files hold the Lumen Accord's fourteen as well (P108): the cases here that walk the files take
## the Derrick League's by their faction, and test_defs_roster_renew holds the other roster to the
## same rules.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const Cells: GDScript = preload("res://tests/sim/support/roster_cells.gd")
const UNITS_DIR: String = "res://data/units"
const WEAPONS_DIR: String = "res://data/weapons"
const HEADQUARTERS: String = "headquarters"
## The faction whose files these cases read (UnitDef.faction).
const FACTION: StringName = &"fossil"
## The sidebar tabs (World.Tab) and the movement class of tanks (World.MoveClass).
const STRUCTURES: int = 0
const INFANTRY: int = 1
const VEHICLES: int = 2


func test_the_data_holds_the_eight_buildings_and_the_six_units() -> void:
	var ids: Array[String] = []
	for path: String in _own_files():
		ids.append(path.get_file().get_basename())
	var wanted: Array[String] = [
		"headquarters",
		"power_plant",
		"refinery",
		"barracks",
		"vehicle_factory",
		"fossil_radar",
		"defence_turret",
		"fossil_strike",
		"rifle_squad",
		"rocket_squad",
		"light_tank",
		"heavy_tank",
		"artillery",
		"harvester",
	]
	assert_array(ids).contains_exactly_in_any_order(wanted)
	for id: String in wanted:
		var unit: UnitDef = _unit(id)
		assert_str(String(unit.type_id)).is_equal(id)
		assert_bool(unit is BuildingDef).override_failure_message(id).is_equal(
			id in wanted.slice(0, 8)
		)


func test_the_eight_building_files_hold_the_gdd_table_and_the_plan_starting_values() -> void:
	# id, footprint, cost, power, requires, produces (a tab, -1 none), tab (-1 = not buildable),
	# build_ticks, max_hp, weapon.
	var expected: Array = [
		["headquarters", Vector2i(3, 3), 0, 20, "", STRUCTURES, -1, 0, 2000, ""],
		["power_plant", Vector2i(2, 2), 300, 100, "headquarters", -1, STRUCTURES, 150, 800, ""],
		["refinery", Vector2i(3, 3), 1400, -30, "power_plant", -1, STRUCTURES, 375, 1500, ""],
		["barracks", Vector2i(2, 2), 400, -20, "power_plant", INFANTRY, STRUCTURES, 150, 1000, ""],
		[
			"vehicle_factory",
			Vector2i(3, 3),
			1800,
			-40,
			"refinery",
			VEHICLES,
			STRUCTURES,
			450,
			1600,
			"",
		],
		[
			"fossil_radar",
			Vector2i(2, 2),
			800,
			-30,
			"refinery",
			-1,
			STRUCTURES,
			300,
			800,
			"",
		],
		[
			"defence_turret",
			Vector2i(1, 1),
			600,
			-20,
			"barracks",
			-1,
			STRUCTURES,
			225,
			900,
			"redoubt_gun",
		],
		[
			"fossil_strike",
			Vector2i(3, 3),
			2500,
			-60,
			"fossil_radar",
			-1,
			STRUCTURES,
			600,
			1500,
			"",
		],
	]
	var got: Array = []
	for row: Array in expected:
		got.append(_building_row(row[0]))
	assert_array(got).is_equal(expected)


func test_the_buildings_see_around_them_and_only_the_turret_acquires() -> void:
	# id, display_name, sight_range, acquire_range. A building sees (fog) and the turret fires at
	# what its weapon reaches, so its acquire_range covers the range and its sight covers that.
	var expected: Array = [
		["headquarters", "Rigworks", 7000, 0],
		["power_plant", "Turbine Hall", 5000, 0],
		["refinery", "Cracking Plant", 5000, 0],
		["barracks", "Bunkhouse", 5000, 0],
		["vehicle_factory", "Heavy Yard", 5000, 0],
		["fossil_radar", "Signal Mast", 5000, 0],
		["defence_turret", "Redoubt", 7000, 5500],
		["fossil_strike", "Deep Bore", 5000, 0],
	]
	var got: Array = []
	for row: Array in expected:
		var unit: UnitDef = _unit(row[0])
		got.append([row[0], unit.display_name, unit.sight_range, unit.acquire_range])
	assert_array(got).is_equal(expected)


func test_the_six_unit_files_hold_the_gdd_costs_build_times_tabs_and_ranges() -> void:
	# id, tab, cost, build_ticks, max_hp, speed (milli-tiles per tick: tiles/s x 1000 / 15),
	# weapon id ("" = unarmed), weapon range, weapon min_range.
	var expected: Array = [
		["rifle_squad", INFANTRY, 100, 75, 100, 67, "rifle", 4000, 0],
		["rocket_squad", INFANTRY, 300, 150, 90, 60, "rocket", 5000, 0],
		["light_tank", VEHICLES, 600, 225, 300, 120, "tank_cannon", 4500, 0],
		["heavy_tank", VEHICLES, 1000, 330, 650, 73, "heavy_cannon", 5000, 0],
		["artillery", VEHICLES, 900, 300, 200, 67, "artillery_gun", 9000, 3000],
		["harvester", VEHICLES, 1200, 300, 800, 73, "", 0, 0],
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
					unit.max_hp,
					unit.speed,
					"" if weapon == null else String(weapon.id),
					0 if weapon == null else weapon.range,
					0 if weapon == null else weapon.min_range,
				]
			)
		)
	assert_array(got).is_equal(expected)


func test_the_three_new_unit_files_hold_their_starting_stats() -> void:
	# speed, radius, selection_radius, formation_spacing, max_hp, armour (1 light, 2 heavy),
	# move_class (2 tracked: one field per goal for a mixed group), sight_range, acquire_range,
	# display_name. The harvester is unarmed, so it acquires nothing.
	assert_array(_stat_row("heavy_tank")).is_equal(
		[73, 450, 500, 1300, 650, 2, 2, 7000, 5500, "Bullhead"]
	)
	assert_array(_stat_row("artillery")).is_equal(
		[67, 400, 500, 1200, 200, 1, 2, 9000, 9000, "Mortar Rig"]
	)
	assert_array(_stat_row("harvester")).is_equal(
		[73, 450, 650, 1400, 800, 1, 2, 5000, 0, "Tanker"]
	)


func test_the_new_weapon_files_hold_their_starting_stats() -> void:
	# id, range, min_range, damage, cooldown_ticks, projectile_speed (0 = hitscan), then the
	# percent of damage against infantry, light, heavy and building armour. Artillery has no
	# splash in Phase 3 (ADR 0018 section 8); the turret gun is the anti-vehicle gun, which the
	# Redoubt gave up for its own anti-infantry gun (ADR 0023 section 7) and the Rail Battery of
	# P108 takes up.
	var weapons: Dictionary[String, Array] = {
		"heavy_cannon": ["heavy_cannon", 5000, 0, 60, 30, 600, [30, 100, 70, 50]],
		"artillery_gun": ["artillery_gun", 9000, 3000, 80, 60, 300, [60, 60, 50, 150]],
		"turret_gun": ["turret_gun", 5500, 0, 40, 30, 600, [40, 100, 80, 20]],
		"redoubt_gun": ["redoubt_gun", 5500, 0, 20, 15, 600, [150, 30, 15, 20]],
	}
	for id: String in weapons:
		assert_array(_weapon_row(id)).override_failure_message(id).is_equal(weapons[id])
	# Every weapon file is one of the seven here, the Lumen Accord's own two (breaker_rocket and
	# arcline_gun, test_defs_roster_renew) or the Deep Bore's rupture (fossil_rupture, P110d: no
	# gun, test_defs_strike_data), each used by the unit or building that names it.
	var files: Array[String] = FileScan.list_files(WEAPONS_DIR, ".tres")
	assert_int(files.size()).is_equal(10)
	assert_str(_unit("heavy_tank").weapon.resource_path).is_equal(
		WEAPONS_DIR + "/heavy_cannon.tres"
	)
	assert_str(_unit("artillery").weapon.resource_path).is_equal(
		WEAPONS_DIR + "/artillery_gun.tres"
	)
	assert_str(_unit("defence_turret").weapon.resource_path).is_equal(
		WEAPONS_DIR + "/redoubt_gun.tres"
	)


## The Redoubt fights infantry (ADR 0023 section 7, docs/GDD.md): its gun's percent is highest and
## at least full against the infantry armour class, low against both vehicle classes, and what a
## shot does (Combat: max(1, damage * percent / 100)) kills a squad of each shipped infantry type
## in fewer ticks than it kills any shipped vehicle. The expectations are read from the tables.
func test_the_redoubts_gun_is_strong_against_infantry_and_weak_against_vehicles() -> void:
	var gun: WeaponDef = _unit("defence_turret").weapon
	var percent: PackedInt32Array = gun.vs_armour
	assert_int(percent[World.Armour.INFANTRY]).is_greater_equal(100)
	assert_int(percent.size()).is_equal(World.Armour.size())
	for armour: int in [World.Armour.LIGHT, World.Armour.HEAVY, World.Armour.BUILDING]:
		assert_int(percent[armour]).override_failure_message(str(armour)).is_less(
			percent[World.Armour.INFANTRY]
		)
	for armour: int in [World.Armour.LIGHT, World.Armour.HEAVY]:
		assert_int(percent[armour]).override_failure_message(str(armour)).is_less_equal(50)
	var infantry_ticks: Array[int] = []
	var vehicle_ticks: Array[int] = []
	for id: String in ["rifle_squad", "rocket_squad", "light_tank", "heavy_tank", "artillery"]:
		var target: UnitDef = _unit(id)
		var ticks: int = _ticks_to_kill(gun, target)
		if target.armour == World.Armour.INFANTRY:
			infantry_ticks.append(ticks)
		else:
			vehicle_ticks.append(ticks)
	assert_array(infantry_ticks).has_size(2)
	assert_array(vehicle_ticks).has_size(3)
	assert_int(infantry_ticks.max()).is_less(vehicle_ticks.min())
	# The anti-vehicle gun it replaced stays as it is, and it is the other way round: no better
	# against infantry than against light vehicles.
	var anti_vehicle: WeaponDef = load(WEAPONS_DIR + "/turret_gun.tres")
	assert_int(anti_vehicle.vs_armour[World.Armour.INFANTRY]).is_less(
		anti_vehicle.vs_armour[World.Armour.LIGHT]
	)
	assert_int(_ticks_to_kill(anti_vehicle, _unit("light_tank"))).is_less(
		_ticks_to_kill(gun, _unit("light_tank"))
	)
	assert_int(_ticks_to_kill(gun, _unit("rifle_squad"))).is_less(
		_ticks_to_kill(anti_vehicle, _unit("rifle_squad"))
	)


func test_every_requirement_chain_reaches_the_headquarters_without_visiting_a_file_twice() -> void:
	var units: Array[UnitDef] = []
	for path: String in _own_files():
		units.append(load(path))
	assert_array(_chain_problems(units)).is_empty()
	# The chains the plan names, followed from the file that ends them: the turret asks for a
	# barracks, which asks for a power plant, which asks for the Headquarters; the radar comes after
	# the refinery, and artillery and the strike after the radar (ADR 0023 section 7).
	assert_array(_chain(_unit("defence_turret"))).is_equal(
		["defence_turret", "barracks", "power_plant", "headquarters"]
	)
	assert_array(_chain(_unit("vehicle_factory"))).is_equal(
		["vehicle_factory", "refinery", "power_plant", "headquarters"]
	)
	assert_array(_chain(_unit("fossil_radar"))).is_equal(
		["fossil_radar", "refinery", "power_plant", "headquarters"]
	)
	assert_array(_chain(_unit("artillery"))).is_equal(
		["artillery", "fossil_radar", "refinery", "power_plant", "headquarters"]
	)
	assert_array(_chain(_unit("fossil_strike"))).is_equal(
		["fossil_strike", "fossil_radar", "refinery", "power_plant", "headquarters"]
	)
	assert_array(_chain(_unit("headquarters"))).is_equal(["headquarters"])


func test_the_chain_rule_reports_a_cycle_a_wrong_end_and_a_self_reference() -> void:
	var hq: BuildingDef = _made(HEADQUARTERS)
	var plant: BuildingDef = _made("plant")
	plant.requires = hq
	var depot: BuildingDef = _made("depot")
	depot.requires = plant
	assert_array(_chain_problems([hq, plant, depot])).is_empty()
	# A chain that ends at another file than the Headquarters.
	var orphan: BuildingDef = _made("orphan")
	var yard: BuildingDef = _made("yard")
	yard.requires = orphan
	assert_array(_chain_problems([yard])).is_equal(
		["yard: the chain ends at orphan, not at headquarters"]
	)
	# A cycle is reported once per file on it, and the walk ends.
	var left: BuildingDef = _made("left")
	var right: BuildingDef = _made("right")
	left.requires = right
	right.requires = left
	(
		assert_array(_chain_problems([left, right]))
		. is_equal(
			[
				"left: the chain visits left twice",
				"right: the chain visits right twice",
			]
		)
	)
	var itself: BuildingDef = _made("itself")
	itself.requires = itself
	assert_array(_chain_problems([itself])).is_equal(["itself: the chain visits itself twice"])
	left.requires = null  # A reference cycle would never be freed.
	itself.requires = null


func test_the_harvester_carries_500_and_is_unarmed_and_only_the_refinery_brings_one() -> void:
	var harvester: UnitDef = _unit("harvester")
	assert_int(harvester.harvest_capacity).is_equal(500)
	assert_object(harvester.weapon).is_null()
	var refinery: BuildingDef = _unit("refinery") as BuildingDef
	assert_object(refinery.free_unit).is_not_null()
	assert_str(refinery.free_unit.resource_path).is_equal(harvester.resource_path)
	assert_str(String(refinery.free_unit.type_id)).is_equal("harvester")
	# No other file carries ore or comes free with a building.
	for path: String in _own_files():
		var unit: UnitDef = load(path)
		var file: String = path.get_file()
		var carries: bool = unit.harvest_capacity > 0
		assert_bool(carries).override_failure_message(file).is_equal(file == "harvester.tres")
		var free: bool = unit is BuildingDef and (unit as BuildingDef).free_unit != null
		assert_bool(free).override_failure_message(file).is_equal(file == "refinery.tres")


func test_the_dock_and_exit_cells_are_the_middle_cell_south_of_the_footprint() -> void:
	# file, the offset it sets (dock or exit), where. The formula is one for every dock and exit:
	# column footprint.x / 2, row footprint.y (P68c); P91's art draws the funnel and the bay there.
	var rows: Array = [
		["refinery", "dock", Vector2i(1, 3)],
		["vehicle_factory", "exit", Vector2i(1, 3)],
		["barracks", "exit", Vector2i(1, 2)],
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


func test_the_cell_rule_accepts_the_ring_of_a_footprint_and_reports_inside_and_beyond() -> void:
	var three: Vector2i = Vector2i(3, 3)
	# Ring cells of 3x3: the 16 cells at distance one, corners included.
	for cell: Vector2i in [Vector2i(1, 3), Vector2i(3, 3), Vector2i(-1, -1), Vector2i(-1, 1)]:
		(
			assert_bool(Cells.touches_footprint(three, cell))
			. override_failure_message(str(cell))
			. is_true()
		)
	# Inside the footprint, and one cell further out than the ring.
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(1, 2), Vector2i(2, 2), Vector2i(1, 4)]:
		(
			assert_bool(Cells.touches_footprint(three, cell))
			. override_failure_message(str(cell))
			. is_false()
		)
	for cell: Vector2i in [Vector2i(4, 0), Vector2i(-2, 1), Vector2i(0, -2)]:
		(
			assert_bool(Cells.touches_footprint(three, cell))
			. override_failure_message(str(cell))
			. is_false()
		)
	# A 2x2 footprint: (1, 2) is the cell below its right column, (1, 1) is inside it.
	assert_bool(Cells.touches_footprint(Vector2i(2, 2), Vector2i(1, 2))).is_true()
	assert_bool(Cells.touches_footprint(Vector2i(2, 2), Vector2i(1, 1))).is_false()
	assert_that(Cells.south_middle(Vector2i(2, 2))).is_equal(Vector2i(1, 2))
	assert_that(Cells.south_middle(Vector2i(3, 3))).is_equal(Vector2i(1, 3))
	assert_that(Cells.south_middle(Vector2i(1, 1))).is_equal(Vector2i(0, 1))


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
	assert_array(producers[STRUCTURES]).is_equal(["headquarters"])
	assert_array(producers[INFANTRY]).is_equal(["barracks"])
	assert_array(producers[VEHICLES]).is_equal(["vehicle_factory"])
	assert_array(buildable[STRUCTURES]).is_equal(
		[
			"barracks",
			"defence_turret",
			"fossil_radar",
			"fossil_strike",
			"power_plant",
			"refinery",
			"vehicle_factory"
		]
	)
	assert_array(buildable[INFANTRY]).is_equal(["rifle_squad", "rocket_squad"])
	assert_array(buildable[VEHICLES]).is_equal(
		["artillery", "harvester", "heavy_tank", "light_tank"]
	)


## The paths of the unit files of the faction these cases read, in file order.
func _own_files() -> Array[String]:
	var found: Array[String] = []
	for path: String in FileScan.list_files(UNITS_DIR, ".tres"):
		if (load(path) as UnitDef).faction == FACTION:
			found.append(path)
	return found


## One text per file whose requirement chain does not reach the Headquarters, or visits a file
## twice on the way. A file without `requires` has no chain (a unit is gated by the building that
## produces its tab, ADR 0018 section 5); the building rows of the tables pin which files those are.
func _chain_problems(units: Array[UnitDef]) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	for unit: UnitDef in units:
		if unit.requires == null:
			continue
		var seen: Dictionary[String, bool] = {String(unit.type_id): true}
		var at: UnitDef = unit
		var twice: bool = false
		while at.requires != null and not twice:
			at = at.requires
			twice = seen.has(String(at.type_id))
			seen[String(at.type_id)] = true
			if twice:
				problems.append("%s: the chain visits %s twice" % [unit.type_id, at.type_id])
		if not twice and String(at.type_id) != HEADQUARTERS:
			problems.append(
				"%s: the chain ends at %s, not at %s" % [unit.type_id, at.type_id, HEADQUARTERS]
			)
	return problems


## The ticks `gun` needs to kill `target` from full hit points with no pause but its cooldown: the
## shots (a hit does `max(1, damage * percent / 100)`, as Combat has it) minus the first, which
## needs no wait, times the cooldown.
@warning_ignore("integer_division")
func _ticks_to_kill(gun: WeaponDef, target: UnitDef) -> int:
	var hit: int = maxi(1, gun.damage * gun.vs_armour[target.armour] / 100)
	var shots: int = (target.max_hp + hit - 1) / hit
	return (shots - 1) * gun.cooldown_ticks


## The type_ids from `unit` along `requires` to the end of the chain.
func _chain(unit: UnitDef) -> Array[String]:
	var ids: Array[String] = [String(unit.type_id)]
	var at: UnitDef = unit
	while at.requires != null and ids.size() < 16:
		at = at.requires
		ids.append(String(at.type_id))
	return ids


## A building that only has a type_id, for the chain rule.
func _made(id: String) -> BuildingDef:
	var building: BuildingDef = BuildingDef.new()
	building.type_id = StringName(id)
	return building


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


func _stat_row(id: String) -> Array:
	var unit: UnitDef = _unit(id)
	return [
		unit.speed,
		unit.radius,
		unit.selection_radius,
		unit.formation_spacing,
		unit.max_hp,
		unit.armour,
		unit.move_class,
		unit.sight_range,
		unit.acquire_range,
		unit.display_name,
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
