extends GdUnitTestSuite
## P285 (ADR 0037 sections 7 and 8): the ground-support data rules of
## tests/sim/support/mine_rules.gd on built defs (one field per case, both sides of every boundary)
## and held against every shipped file, plus the script defaults of the new fields and rules. The
## shipped data holds no layer or ejecting carrier yet, so the shipped checks only keep every file
## inside the rules (and a blast on every weapon some file lays as a mine, once one does).

const Rules: GDScript = preload("res://tests/sim/support/mine_rules.gd")
const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const FILE: String = "res://data/weapons/shot_charge.tres"
const UNITS_DIR: String = "res://data/units"


func test_the_new_fields_default_to_inert_values_of_their_types() -> void:
	var unit: UnitDef = UnitDef.new()
	assert_array([unit.carry_eject_percent, unit.mine_cost, unit.detect_milli]).is_equal([0, 0, 0])
	assert_bool(unit.mine_aware).is_false()
	assert_object(unit.mine_weapon).is_null()
	assert_int(WeaponDef.new().blast_milli).is_equal(0)
	var rules: RulesDef = RulesDef.new()
	# mine_cap 0 means no mine can be laid; the other numbers are ADR 0037's starting values.
	assert_array([rules.mine_cap, rules.mine_lay_ticks, rules.mine_arm_ticks]).is_equal([0, 22, 15])
	assert_array([rules.sweep_ticks, rules.mine_known_cap]).is_equal([30, 24])
	for field: String in [
		"carry_eject_percent", "mine_cost", "mine_aware", "detect_milli", "mine_weapon"
	]:
		var found: bool = false
		for info: Dictionary in unit.get_property_list():
			if info["name"] == field:
				found = true
				var want: int = TYPE_BOOL if field == "mine_aware" else TYPE_INT
				want = TYPE_OBJECT if field == "mine_weapon" else want
				assert_int(int(info["type"])).override_failure_message(field).is_equal(want)
		assert_bool(found).override_failure_message(field).is_true()


func test_fine_defs_break_no_rule_and_a_plain_unit_neither() -> void:
	assert_array(Rules.mine_problems("t.tres", Rules.fine_unit())).is_empty()
	assert_array(Rules.mine_problems("t.tres", Rules.fine_layer())).is_empty()
	assert_array(Rules.mine_problems("t.tres", Rules.fine_carrier())).is_empty()


func test_each_field_is_refused_one_rule_at_a_time_and_accepted_at_its_edges() -> void:
	var cost_zero: UnitDef = Rules.fine_layer()
	cost_zero.mine_cost = 0
	assert_array(Rules.mine_problems("t.tres", cost_zero)).is_equal(
		["t.tres: mine_cost is below 1"]
	)
	var cost_negative: UnitDef = Rules.fine_layer()
	cost_negative.mine_cost = -1
	assert_array(Rules.mine_problems("t.tres", cost_negative)).is_equal(
		["t.tres: mine_cost is negative", "t.tres: mine_cost is below 1"]
	)
	var cost_alone: UnitDef = Rules.fine_unit()
	cost_alone.mine_cost = 5
	assert_array(Rules.mine_problems("t.tres", cost_alone)).is_equal(
		["t.tres: mine_cost needs a mine_weapon"]
	)
	var detect: UnitDef = Rules.fine_unit()
	detect.detect_milli = 0
	assert_array(Rules.mine_problems("t.tres", detect)).is_empty()
	detect.detect_milli = -1
	assert_array(Rules.mine_problems("t.tres", detect)).is_equal(
		["t.tres: detect_milli is negative"]
	)
	for percent: int in [0, 1, 100]:
		var edge: UnitDef = Rules.fine_carrier()
		edge.carry_eject_percent = percent
		assert_array(Rules.mine_problems("t.tres", edge)).is_empty()
	for percent: int in [-1, 101]:
		var wide: UnitDef = Rules.fine_carrier()
		wide.carry_eject_percent = percent
		assert_array(Rules.mine_problems("t.tres", wide)).is_equal(
			["t.tres: carry_eject_percent is not in 0..100"]
		)
	var no_seats: UnitDef = Rules.fine_unit()
	no_seats.carry_eject_percent = 50
	assert_array(Rules.mine_problems("t.tres", no_seats)).is_equal(
		["t.tres: carry_eject_percent needs carry_slots"]
	)


func test_an_aircraft_never_ejects() -> void:
	var flyer: UnitDef = Rules.fine_carrier()
	flyer.move_class = World.MoveClass.AIR
	assert_array(Rules.mine_problems("t.tres", flyer)).is_equal(
		["t.tres: carry_eject_percent on an aircraft"]
	)
	flyer.carry_eject_percent = 0
	assert_array(Rules.mine_problems("t.tres", flyer)).is_empty()


func test_a_mine_weapon_needs_a_blast_and_is_not_the_gun() -> void:
	var dud: UnitDef = Rules.fine_layer()
	dud.mine_weapon.blast_milli = 0
	assert_array(Rules.mine_problems("t.tres", dud)).is_equal(
		["t.tres: a mine weapon has no blast"]
	)
	dud.mine_weapon.blast_milli = 1
	assert_array(Rules.mine_problems("t.tres", dud)).is_empty()
	var armed: UnitDef = Rules.fine_layer()
	armed.weapon = armed.mine_weapon
	assert_array(Rules.mine_problems("t.tres", armed)).is_equal(
		["t.tres: a mine weapon is also the gun"]
	)


func test_a_building_has_none_of_the_ground_support_fields() -> void:
	var building: BuildingDef = BuildingDef.new()
	assert_array(Rules.mine_problems("b.tres", building)).is_empty()
	building.mine_aware = true
	building.detect_milli = 1000
	assert_array(Rules.mine_problems("b.tres", building)).is_equal(
		["b.tres: a building is mine-aware", "b.tres: a building detects mines"]
	)


func test_every_shipped_unit_file_keeps_the_ground_support_rules() -> void:
	var paths: Array[String] = FileScan.list_files(UNITS_DIR, ".tres")
	assert_int(paths.size()).is_greater_equal(3)
	var units: Array[UnitDef] = []
	for path: String in paths:
		var unit: UnitDef = load(path)
		assert_array(Rules.mine_problems(path.get_file(), unit)).is_empty()
		units.append(unit)
		# A weapon laid as a mine is a file of its own, so World merges it by id like a gun.
		if unit.mine_weapon != null:
			assert_bool(unit.mine_weapon.resource_path.begins_with("res://data/weapons")).is_true()
			(
				assert_array(
					Rules.mine_weapon_problems(
						path.get_file(), unit.mine_weapon, unit.mine_weapon.resource_path
					)
				)
				. is_empty()
			)
	assert_array(Rules.weapon_id_problems(units)).is_empty()


func test_a_mine_weapon_file_is_held_to_the_strike_weapon_rules_one_at_a_time() -> void:
	var fine: WeaponDef = Rules.fine_layer().mine_weapon
	assert_array(Rules.mine_weapon_problems("w.tres", fine, FILE)).is_empty()
	var cases: Array = [
		["damage", 0, "mine weapon damage is below 1", 1],
		["range", 1, "mine weapon has a range, a minimum range or a flight", 0],
		["min_range", 1, "mine weapon has a range, a minimum range or a flight", 0],
		["projectile_speed", 1, "mine weapon has a range, a minimum range or a flight", 0],
	]
	for row: Array in cases:
		var weapon: WeaponDef = Rules.fine_layer().mine_weapon
		var good: Variant = weapon.get(row[0])
		weapon.set(row[0], row[1])
		(
			assert_array(Rules.mine_weapon_problems("w.tres", weapon, FILE))
			. override_failure_message(row[0])
			. is_equal(["w.tres: " + row[2]])
		)
		weapon.set(row[0], good)
		assert_array(Rules.mine_weapon_problems("w.tres", weapon, FILE)).is_empty()
	var armour: String = "w.tres: vs_armour is not 4 percents in 0..200"
	for percents: Array in [[0, 200, 0, 200], [100, 100, 100, 100]]:
		fine.vs_armour = PackedInt32Array(percents)
		assert_array(Rules.mine_weapon_problems("w.tres", fine, FILE)).is_empty()
	for percents: Array in [[1, 1, 1], [1, 1, 1, 1, 1], [100, 201, 100, 100], [-1, 100, 100, 100]]:
		fine.vs_armour = PackedInt32Array(percents)
		assert_array(Rules.mine_weapon_problems("w.tres", fine, FILE)).is_equal([armour])
	fine.vs_armour = PackedInt32Array([])
	assert_array(Rules.mine_weapon_problems("w.tres", fine, FILE)).is_equal([armour])
	fine.vs_armour = PackedInt32Array([100, 100, 100, 100])
	fine.id = &"gun"
	assert_array(Rules.mine_weapon_problems("w.tres", fine, FILE)).is_equal(
		["w.tres: mine weapon id gun differs from its file name"]
	)


func test_a_weapon_id_belongs_to_one_file_across_guns_strikes_and_mines() -> void:
	var layer: UnitDef = Rules.fine_layer()
	layer.resource_path = "res://data/units/layer.tres"
	layer.mine_weapon.resource_path = "res://data/weapons/shot_charge.tres"
	var rifle: UnitDef = Rules.fine_unit()
	rifle.resource_path = "res://data/units/rifle.tres"
	rifle.weapon = WeaponDef.new()
	rifle.weapon.id = &"shot_charge"
	rifle.weapon.resource_path = "res://data/weapons/rifle_gun.tres"
	assert_array(Rules.weapon_id_problems([layer, rifle])).is_equal(
		["rifle.tres: weapon id shot_charge is used twice"]
	)
	# The same file twice is one weapon, as two units may share a gun file.
	rifle.weapon = layer.mine_weapon
	assert_array(Rules.weapon_id_problems([layer, rifle])).is_empty()
	# A strike weapon counts too.
	var bore: BuildingDef = BuildingDef.new()
	bore.resource_path = "res://data/units/bore.tres"
	bore.strike_weapon = WeaponDef.new()
	bore.strike_weapon.id = &"shot_charge"
	bore.strike_weapon.resource_path = "res://data/weapons/other.tres"
	assert_array(Rules.weapon_id_problems([layer, bore])).is_equal(
		["bore.tres: weapon id shot_charge is used twice"]
	)
