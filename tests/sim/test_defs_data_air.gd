extends GdUnitTestSuite
## P231 (ADR 0036 section 2, ADR 0037 section 2): the air, repair-role and upgrade data rules of
## tests/sim/support/air_rules.gd, pinned on built defs (one field per case, exact messages, both
## sides of every boundary) and held against every shipped file. The World copies none of these
## fields yet, so the shipped checks pass vacuously until the air data ships, and the guards below
## keep them from checking nothing once it does.

const Rules: GDScript = preload("res://tests/sim/support/air_rules.gd")
const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const UNITS_DIR: String = "res://data/units"
const WEAPONS_DIR: String = "res://data/weapons"
const FACTIONS_DIR: String = "res://data/factions"


func test_the_air_only_fields_are_refused_on_a_ground_type_one_field_at_a_time() -> void:
	var air_only: String = "tank.tres: %s is for AIR only"
	var rearm: String = "tank.tres: ammo needs rearm_ticks of at least 1"
	var cases: Array = [
		["low_flying", true, [air_only % "low_flying"]],
		["ammo", 5, [air_only % "ammo", rearm]],
		["rearm_ticks", 5, [air_only % "rearm_ticks"]],
	]
	for row: Array in cases:
		var ground: UnitDef = Rules.fine_unit()
		ground.set(row[0], row[1])
		(
			assert_array(Rules.air_problems("tank.tres", ground))
			. override_failure_message(row[0])
			. is_equal(row[2])
		)
		var air: UnitDef = Rules.fine_air()
		air.ammo = 0 if row[0] == "low_flying" else air.ammo
		air.tab = World.Tab.INFANTRY if row[0] == "low_flying" else air.tab
		air.set(row[0], row[1])
		(
			assert_array(Rules.air_problems("tank.tres", air))
			. override_failure_message(row[0])
			. is_empty()
		)
	assert_array(Rules.air_problems("tank.tres", Rules.fine_unit())).is_empty()


## ADR 0036 sections 2 and 8 (P262): the carrier fields, both sides of every boundary.
func test_the_carrier_fields_are_a_pair_and_buildings_carry_nothing() -> void:
	var negative: UnitDef = Rules.fine_carrier()
	negative.carry_slots = -1
	assert_array(Rules.air_problems("t.tres", negative)).is_equal(
		["t.tres: carry_slots is negative", "t.tres: carry_classes needs carry_slots"]
	)
	for mask: int in [1, 15]:  # The edges of a move-class mask pass, 16 does not.
		var edge: UnitDef = Rules.fine_carrier()
		edge.carry_classes = mask
		assert_array(Rules.air_problems("t.tres", edge)).is_empty()
	for mask: int in [-1, 16]:
		var wide: UnitDef = Rules.fine_carrier()
		wide.carry_classes = mask
		(
			assert_array(Rules.air_problems("t.tres", wide))
			. override_failure_message(str(mask))
			. is_equal(["t.tres: carry_classes is not a move-class mask 0..15"])
		)
	assert_array(Rules.air_problems("t.tres", Rules.fine_carrier())).is_empty()
	var slots_only: UnitDef = Rules.fine_unit()
	slots_only.carry_slots = 2
	assert_array(Rules.air_problems("t.tres", slots_only)).is_equal(
		["t.tres: carry_slots needs carry_classes"]
	)
	var classes_only: UnitDef = Rules.fine_unit()
	classes_only.carry_classes = 1
	assert_array(Rules.air_problems("t.tres", classes_only)).is_equal(
		["t.tres: carry_classes needs carry_slots"]
	)
	var bunker: BuildingDef = Rules.fine_building()
	bunker.carry_slots = 2
	bunker.carry_classes = 1
	assert_array(Rules.air_problems("t.tres", bunker)).is_equal(
		["t.tres: a building carries squads"]
	)


## ADR 0036 section 9: a drone squad has no ammo and no pad. (ADR 0036 does not say that ammo above
## 0 needs the FLIGHT tab, so that rule is not made.)
func test_a_low_flying_type_has_no_ammo() -> void:
	var drone: UnitDef = Rules.fine_air()
	drone.low_flying = true
	drone.tab = World.Tab.INFANTRY
	assert_array(Rules.air_problems("drone.tres", drone)).is_equal(
		["drone.tres: a low-flying type has ammo"]
	)
	drone.ammo = 0
	drone.rearm_ticks = 0
	assert_array(Rules.air_problems("drone.tres", drone)).is_empty()


## P241: the FLIGHT cap counts queued items by tab and the pad spawn keys on the layer, so the tab
## Flight and a high-air type (AIR, not low flying) go together.
func test_the_flight_tab_and_a_high_air_type_go_together() -> void:
	var message: String = "jet.tres: the Flight tab and a high-air type differ"
	var jet: UnitDef = Rules.fine_air()
	assert_array(Rules.air_problems("jet.tres", jet)).is_empty()
	jet.tab = World.Tab.VEHICLES
	assert_array(Rules.air_problems("jet.tres", jet)).is_equal([message])
	var tank: UnitDef = Rules.fine_unit()
	tank.tab = World.Tab.FLIGHT
	assert_array(Rules.air_problems("jet.tres", tank)).is_equal([message])
	var drone: UnitDef = Rules.fine_air()
	drone.low_flying = true
	drone.ammo = 0
	drone.rearm_ticks = 0
	assert_array(Rules.air_problems("jet.tres", drone)).is_equal([message])  # Still on FLIGHT.
	drone.tab = World.Tab.INFANTRY
	assert_array(Rules.air_problems("jet.tres", drone)).is_empty()


func test_the_air_and_repair_role_rules_accept_their_edge_values_and_report_the_next() -> void:
	# Base builder, property path, values that pass, values that fail, and the messages they give.
	var rows: Array = [
		[Callable(Rules, "fine_air"), "ammo", [0, 1, 6], [-1], ["ammo is negative"]],
		[
			Callable(Rules, "fine_air"),
			"rearm_ticks",
			[1, 30],
			[0],
			["ammo needs rearm_ticks of at least 1"]
		],
		[
			Callable(Rules, "fine_air"),
			"rearm_ticks",
			[],
			[-1],
			["rearm_ticks is negative", "ammo needs rearm_ticks of at least 1"]
		],
		[
			Callable(Rules, "fine_unit"),
			"repair_period_ticks",
			[1, 15],
			[0, -1],
			["repair_period_ticks is below 1"]
		],
		[
			Callable(Rules, "fine_unit"),
			"repair_cost_percent",
			[0, 100],
			[-1, 101],
			["repair_cost_percent is not in 0..100"]
		],
		[
			Callable(Rules, "fine_unit"),
			"repair_seek_milli",
			[0, 1],
			[-1],
			["repair_seek_milli is negative"]
		],
		[
			Callable(Rules, "fine_healer"),
			"repair_classes",
			[0, 1, Rules.MASK_MAX],
			[-1, Rules.MASK_MAX + 1],
			["repair_classes is not a move-class mask 0..15"]
		],
		[Callable(Rules, "fine_healer"), "repair_hp", [1, 100], [0, -1], ["repair_hp is below 1"]],
		[
			Callable(Rules, "fine_healer"),
			"repair_reach_milli",
			[500, 2000],
			[499, 0],
			["repair_reach_milli is below 500"]
		],
		# A mobile repairer needs 1-8 slots: a medic that serves 0 rows never heals.
		[
			Callable(Rules, "fine_healer"),
			"repair_slots",
			[1, Rules.MAX_SLOTS],
			[0, Rules.MAX_SLOTS + 1, -1],
			["repair_slots is not in 1..8"]
		],
		[
			Callable(Rules, "fine_healer"),
			"tab",
			[-1, 0, World.Tab.VEHICLES],
			[Rules.RESEARCH],
			["no type is on the Research tab"]
		],
	]
	for row: Array in rows:
		for value: int in row[2] + row[3]:
			var unit: UnitDef = (row[0] as Callable).call()
			unit.set(row[1], value)
			var want: Array = []
			if row[3].has(value):
				for message: String in row[4]:
					want.append("tank.tres: " + message)
			var label: String = "%s = %d" % [row[1], value]
			(
				assert_array(Rules.air_problems("tank.tres", unit))
				. override_failure_message(label)
				. is_equal(want)
			)


func test_the_building_air_rules_accept_their_edge_values_and_report_the_next() -> void:
	assert_array(Rules.air_problems("field.tres", Rules.fine_airfield())).is_empty()
	assert_array(Rules.air_problems("depot.tres", Rules.fine_building())).is_empty()
	var outside: String = "a pad lies outside the footprint"
	# Base builder, property path, values that pass, values that fail, and the messages they give.
	var rows: Array = [
		["pads", [2], [1, 3], ["pads differs from the pad_offsets count"]],
		[
			"repair_classes",
			[Rules.AIR_BIT],
			[0, 1, 4, 6, Rules.MASK_MAX],
			["an airfield does not serve AIR only"]
		],
		["repair_reach_milli", [500, 1500], [499, 0], ["repair_reach_milli is below 500"]],
		["repair_hp", [1, 10], [0], ["repair_hp is below 1"]],
		[
			"repair_slots",
			[0, 1, Rules.MAX_SLOTS],
			[-1, Rules.MAX_SLOTS + 1],
			["repair_slots is not in 0..8"]
		],
		["repair_seek_milli", [0], [1], ["a building has repair_seek_milli"]],
		["produces", [Rules.FLIGHT], [-1, 0, 2], ["produces FLIGHT and having pads differ"]],
	]
	for row: Array in rows:
		for value: int in row[1] + row[2]:
			var field: BuildingDef = Rules.fine_airfield()
			field.set(row[0], value)
			var want: Array = []
			if row[2].has(value):
				for message: String in row[3]:
					want.append("field.tres: " + message)
			var label: String = "%s = %d" % [row[0], value]
			(
				assert_array(Rules.air_problems("field.tres", field))
				. override_failure_message(label)
				. is_equal(want)
			)
	var offsets: Array = [
		[Vector2i(2, 2), Vector2i(0, 2), Vector2i(2, 1)],
		[Vector2i(3, 0), Vector2i(-1, 0), Vector2i(0, 3), Vector2i(0, -1)]
	]
	for pass_at: int in 2:
		for at: Vector2i in offsets[pass_at]:
			var field: BuildingDef = Rules.fine_airfield()
			field.pad_offsets = [Vector2i(0, 0), at] as Array[Vector2i]
			var want: Array = ["field.tres: " + outside] if pass_at == 1 else []
			(
				assert_array(Rules.air_problems("field.tres", field))
				. override_failure_message(str(at))
				. is_equal(want)
			)
	var twin: BuildingDef = Rules.fine_airfield()
	twin.pad_offsets = [Vector2i(1, 1), Vector2i(1, 1)] as Array[Vector2i]
	assert_array(Rules.air_problems("field.tres", twin)).is_equal(
		["field.tres: two pads share a tile"]
	)
	# The other half of "produces FLIGHT if and only if pads": a FLIGHT producer with no pads.
	var hangar: BuildingDef = Rules.fine_building()
	hangar.produces = Rules.FLIGHT
	assert_array(Rules.air_problems("depot.tres", hangar)).is_equal(
		["depot.tres: produces FLIGHT and having pads differ"]
	)
	# A ground repair building (a Weld Shed) has no pads and needs 1-8 slots.
	var shed: BuildingDef = Rules.fine_building()
	shed.repair_classes = 6
	shed.repair_hp = 30
	shed.repair_period_ticks = 15
	shed.repair_reach_milli = 2700
	shed.repair_slots = 2
	assert_array(Rules.air_problems("shed.tres", shed)).is_empty()
	shed.repair_slots = 0
	assert_array(Rules.air_problems("shed.tres", shed)).is_equal(
		["shed.tres: repair_slots is not in 1..8"]
	)
	# The pads of an airfield also need a reach of 500 with the role's classes left at 0.
	var bare: BuildingDef = Rules.fine_airfield()
	bare.repair_classes = 0
	bare.repair_reach_milli = 0
	assert_array(Rules.air_problems("field.tres", bare)).is_equal(
		[
			"field.tres: repair_reach_milli is below 500",
			"field.tres: an airfield does not serve AIR only"
		]
	)


func test_a_reveal_building_has_a_charge_and_no_strike_radius_delay_length_or_weapon() -> void:
	var message: String = "sat.tres: a Reveal building has a strike radius, delay, length or weapon"
	var fine: BuildingDef = Rules.fine_building()
	fine.strike_kind = Rules.REVEAL
	fine.charge_ticks = 900
	assert_array(Rules.air_problems("sat.tres", fine)).is_empty()
	for field: String in ["strike_radius", "strike_delay", "strike_ticks"]:
		var sat: BuildingDef = Rules.fine_building()
		sat.strike_kind = Rules.REVEAL
		sat.set(field, 1)
		assert_array(Rules.air_problems("sat.tres", sat)).override_failure_message(field).is_equal(
			[message]
		)
	var armed: BuildingDef = Rules.fine_building()
	armed.strike_kind = Rules.REVEAL
	armed.strike_weapon = WeaponDef.new()
	assert_array(Rules.air_problems("sat.tres", armed)).is_equal([message])


func test_pads_lie_at_least_the_largest_flight_spacing_apart() -> void:
	var message: String = "field.tres: pads are closer than the largest FLIGHT spacing"
	var field: BuildingDef = Rules.fine_airfield()
	field.pad_offsets = [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i]
	assert_array(Rules.pad_spacing_problems("field.tres", field, 1000)).is_empty()
	assert_array(Rules.pad_spacing_problems("field.tres", field, 1001)).is_equal([message])
	field.pad_offsets = [Vector2i(0, 0), Vector2i(1, 1)] as Array[Vector2i]
	assert_array(Rules.pad_spacing_problems("field.tres", field, 1414)).is_empty()
	assert_array(Rules.pad_spacing_problems("field.tres", field, 1415)).is_equal([message])


func test_upgrade_rules_accept_their_edge_values_and_report_the_next() -> void:
	assert_array(Rules.upgrade_problems("up.tres", Rules.fine_upgrade(), &"fossil")).is_empty()
	# Property path, stat, values that pass, values that fail, and the message.
	var dealt: int = UpgradeDef.Stat.DAMAGE_DEALT
	var taken: int = UpgradeDef.Stat.DAMAGE_TAKEN
	var ammo: int = UpgradeDef.Stat.AMMO
	var rows: Array = [
		["cost", dealt, [0, 1], [-1], "cost is negative"],
		["research_ticks", dealt, [1, 900], [0, -1], "research_ticks is below 1"],
		["stat", dealt, [0, 1, 2], [-1, 3], "stat is not a stat"],
		["value", dealt, [1, 400], [0, 401], "value is not in 1..400 percent"],
		["value", taken, [1, 400], [0, 401], "value is not in 1..400 percent"],
		["value", ammo, [1, 1000], [0, -1], "an ammo upgrade adds less than 1 shot"],
	]
	for row: Array in rows:
		for value: int in row[2] + row[3]:
			var up: UpgradeDef = Rules.fine_upgrade()
			if row[0] != "stat":
				up.stat = row[1]
			up.set(row[0], value)
			var want: Array = [] if row[2].has(value) else ["up.tres: " + row[4]]
			var label: String = "%s %d = %d" % [row[0], row[1], value]
			(
				assert_array(Rules.upgrade_problems("up.tres", up, &"fossil"))
				. override_failure_message(label)
				. is_equal(want)
			)
	var up: UpgradeDef = Rules.fine_upgrade()
	up.requires = null
	assert_array(Rules.upgrade_problems("up.tres", up, &"fossil")).is_equal(
		["up.tres: requires is not set"]
	)
	up = Rules.fine_upgrade()
	up.applies_to = [] as Array[UnitDef]
	assert_array(Rules.upgrade_problems("up.tres", up, &"fossil")).is_equal(
		["up.tres: applies_to is empty"]
	)
	up.applies_to = [null] as Array[UnitDef]
	assert_array(Rules.upgrade_problems("up.tres", up, &"fossil")).is_equal(
		["up.tres: applies_to has a null entry"]
	)
	assert_array(Rules.upgrade_problems("up.tres", Rules.fine_upgrade(), &"renew")).is_equal(
		["up.tres: faction differs from its faction file"]
	)
	up = Rules.fine_upgrade()
	up.stat = ammo
	up.applies_to = [Rules.fine_unit()] as Array[UnitDef]
	assert_array(Rules.upgrade_problems("up.tres", up, &"fossil")).is_equal(
		["up.tres: an ammo upgrade applies to a type without ammo"]
	)


func test_an_upgrade_id_may_not_be_a_type_id_and_one_stat_of_a_type_has_one_upgrade() -> void:
	var faction: FactionDef = FactionDef.new()
	faction.id = &"fossil"
	var first: UpgradeDef = Rules.fine_upgrade()
	var second: UpgradeDef = Rules.fine_upgrade()
	second.id = &"more_bombs"
	var jet: UnitDef = first.applies_to[0]
	var jets: Array[UnitDef] = [jet]
	second.applies_to = [jet] as Array[UnitDef]
	faction.upgrades = [first] as Array[UpgradeDef]
	assert_array(Rules.upgrade_catalog_problems(jets, [faction] as Array[FactionDef])).is_empty()
	faction.upgrades = [first, second] as Array[UpgradeDef]
	assert_array(Rules.upgrade_catalog_problems(jets, [faction] as Array[FactionDef])).is_equal(
		["better_bombs and more_bombs change one stat of gun"]
	)
	second.stat = UpgradeDef.Stat.DAMAGE_TAKEN  # Another stat of the same type is allowed.
	assert_array(Rules.upgrade_catalog_problems(jets, [faction] as Array[FactionDef])).is_empty()
	# The key has the faction: another faction may change the same stat of the same type.
	var other: FactionDef = FactionDef.new()
	other.id = &"renew"
	var third: UpgradeDef = Rules.fine_upgrade()
	third.id = &"renew_bombs"
	third.applies_to = [jet] as Array[UnitDef]
	other.upgrades = [third] as Array[UpgradeDef]
	var both: Array[FactionDef] = [faction, other]
	assert_array(Rules.upgrade_catalog_problems(jets, both)).is_empty()
	first.id = jet.type_id
	assert_array(Rules.upgrade_catalog_problems(jets, [faction] as Array[FactionDef])).is_equal(
		["tank: upgrade id is also a type id"]
	)


func test_damage_dealt_is_keyed_on_the_weapon_and_needs_an_armed_type() -> void:
	var faction: FactionDef = FactionDef.new()
	faction.id = &"fossil"
	var first: UpgradeDef = Rules.fine_upgrade()
	var tank: UnitDef = first.applies_to[0]
	var scout: UnitDef = Rules.fine_air()
	scout.type_id = &"scout"
	scout.weapon = tank.weapon  # Two types on one weapon.
	var units: Array[UnitDef] = [tank, scout]
	var listed: Array[FactionDef] = [faction]
	faction.upgrades = [first] as Array[UpgradeDef]
	first.applies_to = [tank, scout] as Array[UnitDef]
	assert_array(Rules.upgrade_catalog_problems(units, listed)).is_equal(
		["better_bombs and better_bombs change one stat of gun"]
	)
	# Two upgrades on one weapon, through two different types.
	var second: UpgradeDef = Rules.fine_upgrade()
	second.id = &"more_bombs"
	first.applies_to = [tank] as Array[UnitDef]
	second.applies_to = [scout] as Array[UnitDef]
	faction.upgrades = [first, second] as Array[UpgradeDef]
	assert_array(Rules.upgrade_catalog_problems(units, listed)).is_equal(
		["better_bombs and more_bombs change one stat of gun"]
	)
	# An unarmed type.
	var bare: UnitDef = Rules.fine_air()
	bare.type_id = &"bare"
	first.applies_to = [bare] as Array[UnitDef]
	faction.upgrades = [first] as Array[UpgradeDef]
	assert_array(Rules.upgrade_catalog_problems([bare] as Array[UnitDef], listed)).is_equal(
		["better_bombs: a damage-dealt upgrade applies to an unarmed type"]
	)


## The catalog rules of the World's upgrade bits: ids are non-empty, an id is on one def only (the
## same def in two factions is one id), and no more than World.UPGRADES_MAX distinct ids.
func test_upgrade_ids_are_non_empty_unique_and_at_most_the_bit_count() -> void:
	var jet: UnitDef = Rules.fine_upgrade().applies_to[0]
	var jets: Array[UnitDef] = [jet]
	var faction: FactionDef = FactionDef.new()
	faction.id = &"fossil"
	var first: UpgradeDef = Rules.fine_upgrade()
	var again: UpgradeDef = Rules.fine_upgrade()  # Another def with the same id.
	faction.upgrades = [first] as Array[UpgradeDef]
	var all: Array[FactionDef] = [faction]
	var twin: FactionDef = FactionDef.new()  # The same def in a second faction: still one id.
	twin.id = &"renew"
	twin.upgrades = [first] as Array[UpgradeDef]
	(
		assert_array(Rules.upgrade_catalog_problems(jets, [faction, twin] as Array[FactionDef]))
		. is_empty()
	)
	faction.upgrades = [first, again] as Array[UpgradeDef]
	assert_array(Rules.upgrade_catalog_problems(jets, all)).contains(
		["better_bombs: upgrade id is on two defs"]
	)
	again.id = &""
	assert_array(Rules.upgrade_catalog_problems(jets, all)).contains(["an upgrade has an empty id"])
	var many: Array[UpgradeDef] = []
	for count: int in World.UPGRADES_MAX + 1:
		var up: UpgradeDef = Rules.fine_upgrade()
		up.id = StringName("up%d" % count)
		up.stat = UpgradeDef.Stat.DAMAGE_TAKEN  # No stat clash with the jet's other upgrades.
		up.applies_to = [] as Array[UnitDef]
		many.append(up)
	faction.upgrades = many.slice(0, World.UPGRADES_MAX) as Array[UpgradeDef]
	assert_array(Rules.upgrade_catalog_problems(jets, all)).is_empty()  # Exactly the most.
	faction.upgrades = many
	assert_array(Rules.upgrade_catalog_problems(jets, all)).is_equal(
		["31 upgrade ids, more than 30"]
	)


func _in_a_roster(unit: UnitDef, factions: Array[FactionDef]) -> bool:
	for faction: FactionDef in factions:
		if faction.roster.has(unit):
			return true
	return false


func test_every_shipped_file_keeps_the_air_repair_and_upgrade_rules() -> void:
	var units: Array[UnitDef] = []
	for path: String in FileScan.list_files(UNITS_DIR, ".tres"):
		units.append(load(path))
	var factions: Array[FactionDef] = []
	for path: String in FileScan.list_files(FACTIONS_DIR, ".tres"):
		factions.append(load(path))
	assert_int(units.size()).is_greater(0)
	assert_int(factions.size()).is_greater(0)
	var spacing: int = 0
	var flight_types: int = 0
	for unit: UnitDef in units:
		if unit.tab == Rules.FLIGHT:
			flight_types += 1
			spacing = maxi(spacing, unit.formation_spacing)
	var field_count: int = 0
	var research_producers: int = 0
	for unit: UnitDef in units:
		var file: String = unit.resource_path.get_file()
		assert_array(Rules.air_problems(file, unit)).is_empty()
		var building: BuildingDef = unit as BuildingDef
		if building == null:
			continue
		# P247: the engineering centres are in no roster and no faction lists its upgrades yet, so
		# a research producer counts only once a roster has it (P249 fills both together).
		if building.produces == Rules.RESEARCH and _in_a_roster(building, factions):
			research_producers += 1
		if building.pads > 0:
			field_count += 1
			assert_array(Rules.pad_spacing_problems(file, building, spacing)).is_empty()
	var upgrade_count: int = 0
	for faction: FactionDef in factions:
		for up: UpgradeDef in faction.upgrades:
			upgrade_count += 1
			(
				assert_array(Rules.upgrade_problems(up.resource_path.get_file(), up, faction.id))
				. is_empty()
			)
	assert_array(Rules.upgrade_catalog_problems(units, factions)).is_empty()
	# A Rules.FLIGHT type needs an airfield, and a research building needs something to research.
	assert_bool(flight_types == 0 or field_count > 0).is_true()
	assert_bool(research_producers == 0 or upgrade_count > 0).is_true()
	assert_int(FileScan.list_files(WEAPONS_DIR, ".tres").size()).is_greater(0)
	for file: String in FileScan.list_files(WEAPONS_DIR, ".tres"):
		var weapon: WeaponDef = load(file)
		(
			assert_bool(weapon.targets >= 1 and weapon.targets <= 7)
			. override_failure_message(file)
			. is_true()
		)
