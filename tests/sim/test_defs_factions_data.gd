extends GdUnitTestSuite
## The faction data (plan rows P107 and P108, ADR 0023 sections 6 and 7): every unit file names a
## faction whose file lists it, every `requires` chain stays inside its faction and reaches that
## faction's Headquarters, each faction has the three producers, its key triad and its names, and
## the producer-faction rule of Production.apply_queue accepts every buildable type of a faction at
## the producers the data gives it. The rules run over every file of data/units and
## data/factions, so a faction that a later row adds is held to them without a new case.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const Rig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const UNITS_DIR: String = "res://data/units"
const FACTIONS_DIR: String = "res://data/factions"
## The sidebar tabs (World.Tab): the Headquarters is the building that produces STRUCTURES.
const STRUCTURES: int = 0
const TABS: int = 3
## The map of the queue cases: a row of buildings four tiles apart leaves room for a 3x3 footprint.
const COLS: int = 40
const ROWS: int = 8
const PITCH: int = 4
const CREDITS: int = 100000


func test_every_unit_file_names_a_faction_whose_file_lists_it() -> void:
	var factions: Array[FactionDef] = _factions()
	assert_int(factions.size()).is_greater_equal(1)
	assert_array(_faction_problems(_units(), factions)).is_empty()
	for faction: FactionDef in factions:
		assert_array(faction.roster).is_not_empty()


func test_every_requires_chain_stays_in_its_faction_and_reaches_its_headquarters() -> void:
	assert_array(_chain_problems(_factions())).is_empty()
	# The Derrick League's chains, which ADR 0023 section 7 gives: the radar after the refinery,
	# artillery and the strike after the radar.
	var fossil: Dictionary[String, String] = _requires_of(load(FACTIONS_DIR + "/fossil.tres"))
	(
		assert_dict(fossil)
		. is_equal(
			{
				"power_plant": "headquarters",
				"refinery": "power_plant",
				"barracks": "power_plant",
				"vehicle_factory": "refinery",
				"fossil_radar": "refinery",
				"defence_turret": "barracks",
				"fossil_strike": "fossil_radar",
				"artillery": "fossil_radar",
			}
		)
	)


func test_the_faction_checks_report_a_missing_unknown_and_unlisted_faction() -> void:
	var alpha: FactionDef = _faction(&"alpha")
	var plain: UnitDef = _unit("plain", &"alpha")
	var loose: UnitDef = _unit("loose", &"")
	var lost: UnitDef = _unit("lost", &"gamma")
	var stray: UnitDef = _unit("stray", &"beta")
	alpha.roster = [plain, stray] as Array[UnitDef]
	var units: Array[UnitDef] = [plain, loose, lost, stray]
	(
		assert_array(_faction_problems(units, [alpha] as Array[FactionDef]))
		. is_equal(
			[
				"loose: no faction",
				"lost: faction gamma has no file",
				"stray: faction beta has no file",
				"alpha: the roster lists stray of faction beta",
			]
		)
	)
	# A roster that lists a type twice, a type that is no file, and a faction defined twice.
	var beta: FactionDef = _faction(&"beta")
	beta.roster = [stray, stray, _unit("ghost", &"beta")] as Array[UnitDef]
	alpha.roster = [plain] as Array[UnitDef]
	var again: FactionDef = _faction(&"alpha")
	again.roster = [plain] as Array[UnitDef]
	(
		assert_array(_faction_problems([plain, stray], [alpha, beta, again] as Array[FactionDef]))
		. is_equal(
			[
				"alpha: defined twice",
				"beta: the roster lists stray twice",
				"beta: the roster lists ghost, which is no file of data/units",
			]
		)
	)
	assert_array(_faction_problems([plain], [alpha] as Array[FactionDef])).is_empty()


func test_the_chain_checks_report_a_foreign_a_cyclic_and_a_wrongly_ended_chain() -> void:
	var hq: BuildingDef = _building("hq", &"alpha", -1, STRUCTURES, null)
	var plant: BuildingDef = _building("plant", &"alpha", STRUCTURES, -1, hq)
	var camp: BuildingDef = _building("camp", &"alpha", STRUCTURES, 1, plant)
	var yard: BuildingDef = _building("yard", &"alpha", STRUCTURES, 2, plant)
	var alpha: FactionDef = _faction(&"alpha")
	alpha.roster = [hq, plant, camp, yard] as Array[UnitDef]
	var fine: Array[FactionDef] = [alpha]
	assert_array(_chain_problems(fine)).is_empty()
	# A requirement of another faction, one that ends at another building than the Headquarters,
	# a structure that asks for nothing and a chain that visits a building twice.
	var foreign: BuildingDef = _building("foreign", &"beta", STRUCTURES, -1, null)
	var orphan: BuildingDef = _building("orphan", &"alpha", -1, -1, null)
	plant.requires = foreign
	camp.requires = orphan
	yard.requires = null
	(
		assert_array(_chain_problems(fine))
		. is_equal(
			[
				"plant: the chain asks for foreign of faction beta",
				"camp: the chain ends at orphan, not at hq",
				"yard: a buildable structure asks for nothing",
			]
		)
	)
	plant.requires = camp
	camp.requires = plant
	yard.requires = plant
	(
		assert_array(_chain_problems(fine))
		. is_equal(
			[
				"plant: the chain visits plant twice",
				"camp: the chain visits camp twice",
				"yard: the chain visits plant twice",
			]
		)
	)
	plant.requires = null  # A reference cycle would never be freed.
	camp.requires = null


func test_the_chain_checks_report_the_headquarters_and_producers_a_faction_needs() -> void:
	var hq: BuildingDef = _building("hq", &"alpha", -1, STRUCTURES, null)
	var alpha: FactionDef = _faction(&"alpha")
	alpha.roster = [hq] as Array[UnitDef]
	# One building that produces each tab, and no more: the unit tabs need theirs.
	var missing: Array[String] = [
		"alpha: 0 producers of tab 1, not 1",
		"alpha: 0 producers of tab 2, not 1",
	]
	assert_array(_chain_problems([alpha] as Array[FactionDef])).is_equal(missing)
	var barracks: BuildingDef = _building("barracks", &"alpha", STRUCTURES, 1, hq)
	var factory: BuildingDef = _building("factory", &"alpha", STRUCTURES, 2, hq)
	alpha.roster = [hq, barracks, factory] as Array[UnitDef]
	assert_array(_chain_problems([alpha] as Array[FactionDef])).is_empty()
	var second: BuildingDef = _building("second", &"alpha", STRUCTURES, 1, hq)
	alpha.roster = [hq, barracks, factory, second] as Array[UnitDef]
	assert_array(_chain_problems([alpha] as Array[FactionDef])).is_equal(
		["alpha: 2 producers of tab 1, not 1"]
	)
	# Two Headquarters, and none: the chains are not followed without exactly one.
	var twin: BuildingDef = _building("twin", &"alpha", -1, STRUCTURES, null)
	alpha.roster = [hq, twin, barracks, factory] as Array[UnitDef]
	assert_array(_chain_problems([alpha] as Array[FactionDef])).is_equal(
		["alpha: 2 Headquarters, not 1"]
	)
	alpha.roster = [barracks, factory] as Array[UnitDef]
	assert_array(_chain_problems([alpha] as Array[FactionDef])).is_equal(
		["alpha: 0 Headquarters, not 1"]
	)


## A faction file holds its id (the file name), a display name, an emblem art id and a key triad of
## three `#RRGGBB` strings in capitals (the bake replaces exact strings, ADR 0023 section 5) from
## light to dark; no two factions share a name, an emblem or a colour. The Derrick League's values
## are the ADR's (sections 5 and 6).
func test_every_faction_file_holds_its_id_names_emblem_and_key_triad() -> void:
	var names: Dictionary[String, String] = {}
	var emblems: Dictionary[String, String] = {}
	var colours: Dictionary[String, String] = {}
	for path: String in FileScan.list_files(FACTIONS_DIR, ".tres"):
		var faction: FactionDef = load(path)
		var file: String = path.get_file().get_basename()
		assert_str(String(faction.id)).override_failure_message(file).is_equal(file)
		assert_str(faction.display_name).override_failure_message(file).is_not_empty()
		assert_str(String(faction.emblem)).override_failure_message(file).is_not_empty()
		assert_bool(names.has(faction.display_name)).override_failure_message(file).is_false()
		assert_bool(emblems.has(faction.emblem)).override_failure_message(file).is_false()
		names[faction.display_name] = file
		emblems[faction.emblem] = file
		assert_int(faction.key_triad.size()).override_failure_message(file).is_equal(3)
		var luminance: Array[float] = []
		for hex: String in faction.key_triad:
			var well_formed: bool = (
				hex.length() == 7
				and hex.begins_with("#")
				and hex.is_valid_html_color()
				and hex == hex.to_upper()
			)
			assert_bool(well_formed).override_failure_message(file + " " + hex).is_true()
			assert_bool(colours.has(hex)).override_failure_message(file + " " + hex).is_false()
			colours[hex] = file
			luminance.append(Color.html(hex).get_luminance())
		assert_bool(luminance[0] > luminance[1] and luminance[1] > luminance[2]).is_true()
	var fossil: FactionDef = load(FACTIONS_DIR + "/fossil.tres")
	assert_array([fossil.id, fossil.display_name, fossil.emblem]).is_equal(
		[&"fossil", "Derrick League", &"emblem_fossil"]
	)
	assert_array(Array(fossil.key_triad)).is_equal(["#FF9446", "#E8681F", "#B04B12"])


## The names the player reads: every unit and building file has one (an empty name would read as
## the capitalised id), and no two files share one, in any faction.
func test_every_unit_file_has_a_display_name_that_no_other_file_has() -> void:
	var seen: Dictionary[String, String] = {}
	for path: String in FileScan.list_files(UNITS_DIR, ".tres"):
		var unit: UnitDef = load(path)
		var file: String = path.get_file()
		assert_str(unit.display_name).override_failure_message(file).is_not_empty()
		var key: String = unit.display_name.to_lower()
		(
			assert_bool(seen.has(key))
			. override_failure_message("%s shares its name with %s" % [file, seen.get(key, "")])
			. is_false()
		)
		seen[key] = file


## The rule of Production.apply_queue (ADR 0023 section 6) against the data: in a world built from a
## faction's roster, whose player owns one building of each kind, a QUEUE of every buildable type
## is accepted at the producer of its tab, and the types the producer-faction rule drops for
## another faction's producer are exactly those of another faction.
func test_every_buildable_type_of_a_faction_is_queued_at_its_own_producers() -> void:
	for faction: FactionDef in _factions():
		for member: UnitDef in faction.roster:
			if member.tab < 0:
				continue
			var world: World = _owned(faction)
			var type: int = Worlds.type_of(world, String(member.type_id))
			assert_int(world.type_faction[type]).override_failure_message(member.type_id).is_equal(
				world.faction_ids.find(faction.id)
			)
			Rig.step(world, [Rig.queue(world, 1, String(member.type_id))])
			assert_int(world.dropped_commands).override_failure_message(member.type_id).is_equal(0)
			(
				assert_array(Rig.items(world, 1, member.tab))
				. override_failure_message(member.type_id)
				. is_equal([type])
			)
			# The same item of a type that has another faction is dropped at this producer.
			world.type_faction[type] = world.faction_ids.size()
			world.queue_count[Rig.queue_of(1, member.tab)] = 0
			Rig.step(world, [Rig.queue(world, 1, String(member.type_id))])
			assert_int(world.dropped_commands).override_failure_message(member.type_id).is_equal(1)


## One text per broken rule between the unit files and the faction files; empty when they agree:
## every unit has a faction that has a file and lists it; a faction is defined once, lists each of
## its types once, lists only files of data/units and only types of its own faction.
func _faction_problems(units: Array[UnitDef], factions: Array[FactionDef]) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var by_id: Dictionary[String, FactionDef] = {}
	for faction: FactionDef in factions:
		var id: String = String(faction.id)
		if by_id.has(id):
			problems.append("%s: defined twice" % id)
		by_id[id] = faction
	for unit: UnitDef in units:
		var name: String = String(unit.type_id)
		var id: String = String(unit.faction)
		if id.is_empty():
			problems.append("%s: no faction" % name)
		elif not by_id.has(id):
			problems.append("%s: faction %s has no file" % [name, id])
		elif not by_id[id].roster.has(unit):
			problems.append("%s: not in the roster of %s" % [name, id])
	for faction: FactionDef in factions:
		var listed: Dictionary[String, bool] = {}
		for member: UnitDef in faction.roster:
			var name: String = String(member.type_id)
			if member.faction != faction.id:
				problems.append(
					"%s: the roster lists %s of faction %s" % [faction.id, name, member.faction]
				)
			if listed.has(name):
				problems.append("%s: the roster lists %s twice" % [faction.id, name])
			elif not units.has(member):
				problems.append(
					"%s: the roster lists %s, which is no file of data/units" % [faction.id, name]
				)
			listed[name] = true
	return problems


## One text per broken chain rule of the factions: exactly one Headquarters (a building that
## produces the structures tab) and exactly one producer of each tab; a buildable structure that
## asks for nothing; a requirement chain that leaves its faction, visits a type twice or ends at
## another building than the Headquarters. A unit has no chain of its own unless it names one (the
## artillery asks for the radar); the producer of its tab gates the rest (ADR 0018 section 5).
func _chain_problems(factions: Array[FactionDef]) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	for faction: FactionDef in factions:
		var head: Array[UnitDef] = []
		var producers: Array[int] = [0, 0, 0]
		for member: UnitDef in faction.roster:
			var building: BuildingDef = member as BuildingDef
			if building == null or building.produces < 0:
				continue
			producers[building.produces] += 1
			if building.produces == STRUCTURES:
				head.append(building)
		if head.size() != 1:
			problems.append("%s: %d Headquarters, not 1" % [faction.id, head.size()])
			continue
		for tab: int in range(1, TABS):
			if producers[tab] != 1:
				problems.append(
					"%s: %d producers of tab %d, not 1" % [faction.id, producers[tab], tab]
				)
		for member: UnitDef in faction.roster:
			problems.append_array(_chain_of(faction, member, head[0]))
	return problems


## The chain problems of one roster entry: see _chain_problems.
func _chain_of(faction: FactionDef, member: UnitDef, head: UnitDef) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var name: String = String(member.type_id)
	if member.requires == null:
		if member.tab == STRUCTURES:
			problems.append("%s: a buildable structure asks for nothing" % name)
		return problems
	var seen: Dictionary[String, bool] = {name: true}
	var at: UnitDef = member
	while at.requires != null:
		at = at.requires
		if at.faction != faction.id:
			problems.append(
				"%s: the chain asks for %s of faction %s" % [name, at.type_id, at.faction]
			)
			return problems
		if seen.has(String(at.type_id)):
			problems.append("%s: the chain visits %s twice" % [name, at.type_id])
			return problems
		seen[String(at.type_id)] = true
	if at != head:
		problems.append("%s: the chain ends at %s, not at %s" % [name, at.type_id, head.type_id])
	return problems


## The type_id each requirement of a faction's roster names, by the type that asks (file order).
func _requires_of(faction: FactionDef) -> Dictionary[String, String]:
	var found: Dictionary[String, String] = {}
	for member: UnitDef in faction.roster:
		if member.requires != null:
			found[String(member.type_id)] = String(member.requires.type_id)
	return found


## A world of the faction's roster in which player 1 owns one building of every kind it has, in a
## row, with credits for any item. The roster's file names are its type ids (test_defs_data).
func _owned(faction: FactionDef) -> World:
	var ids: Array[String] = []
	for member: UnitDef in faction.roster:
		ids.append(String(member.type_id))
	var world: World = Worlds.open(COLS, ROWS, ids)
	var at: int = 0
	for member: UnitDef in faction.roster:
		if member is BuildingDef:
			var type: int = Worlds.type_of(world, String(member.type_id))
			var id: int = world.add_building(1, type, 1 + at * PITCH, 1)
			assert_int(id).override_failure_message(String(member.type_id)).is_greater(0)
			at += 1
	world.credits[1] = CREDITS
	return world


func _units() -> Array[UnitDef]:
	var units: Array[UnitDef] = []
	for path: String in FileScan.list_files(UNITS_DIR, ".tres"):
		units.append(load(path))
	return units


func _factions() -> Array[FactionDef]:
	var found: Array[FactionDef] = []
	for path: String in FileScan.list_files(FACTIONS_DIR, ".tres"):
		found.append(load(path))
	return found


func _faction(id: StringName) -> FactionDef:
	var faction: FactionDef = FactionDef.new()
	faction.id = id
	return faction


func _unit(id: String, faction: StringName) -> UnitDef:
	var unit: UnitDef = UnitDef.new()
	unit.type_id = StringName(id)
	unit.faction = faction
	return unit


## A building of `faction` with the tab it is built on (-1 none), the tab it produces and what it
## requires.
func _building(
	id: String, faction: StringName, tab: int, produces: int, requires: UnitDef
) -> BuildingDef:
	var building: BuildingDef = BuildingDef.new()
	building.type_id = StringName(id)
	building.faction = faction
	building.tab = tab
	building.produces = produces
	building.requires = requires
	return building
