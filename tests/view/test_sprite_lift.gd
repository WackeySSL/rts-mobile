extends GdUnitTestSuite
## SpriteLift (P117b): how far above its ground point a thing of the view stands until the iso
## sheets say it (ADR 0023 sections 2 and 3, P113). A bar is lifted by the top of its unit's frame,
## a burst by the middle of it, a flash, a tracer, a shell and a puff by the muzzle height of their
## weapon. The numbers are the canvas Spec's, section 05 (a vehicle is 16 to 30 px high, a figure
## 18 px, a squad spreads over its third of a tile), typed again here as literals so that a changed
## table fails. The layers' use of them is in test_health_bars.gd, test_effects_layer.gd and
## test_projectile_layer.gd. P117c: a weapon of the faction rosters has its row, and a scan of
## data/units fails for any weapon a shipped unit fires that the muzzle table lacks.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const UNITS_DIR: String = "res://data/units/"
const LIGHT: int = World.Armour.LIGHT
const HEAVY: int = World.Armour.HEAVY
const INFANTRY: int = World.Armour.INFANTRY
const BUILDING: int = World.Armour.BUILDING


func test_a_type_with_a_row_gets_its_own_lift() -> void:
	var ids: Array[StringName] = [
		&"light_tank", &"heavy_tank", &"artillery", &"harvester", &"rifle_squad", &"rocket_squad"
	]
	var armours: PackedInt32Array = [LIGHT, HEAVY, LIGHT, LIGHT, INFANTRY, INFANTRY]
	var expected: Array[float] = [24.0, 30.0, 28.0, 26.0, 24.0, 24.0]
	for type: int in ids.size():
		var note: String = String(ids[type])
		(
			assert_float(SpriteLift.bar_lift_px(ids, armours, type))
			. override_failure_message(note)
			. is_equal(expected[type])
		)
		(
			assert_float(SpriteLift.centre_lift_px(ids, armours, type))
			. override_failure_message(note)
			. is_equal(expected[type] * 0.5)
		)


func test_a_type_without_a_row_gets_the_default_of_its_class() -> void:
	# A type of the Phase 3 rosters that has no row yet: infantry 24, any other class 26.
	var ids: Array[StringName] = [&"flarejack", &"bullhead", &"a_gun", &"a_wall"]
	var armours: PackedInt32Array = [INFANTRY, HEAVY, LIGHT, BUILDING]
	var expected: Array[float] = [24.0, 26.0, 26.0, 26.0]
	for type: int in ids.size():
		(
			assert_float(SpriteLift.bar_lift_px(ids, armours, type))
			. override_failure_message(String(ids[type]))
			. is_equal(expected[type])
		)


func test_a_type_the_tables_lack_counts_as_a_vehicle() -> void:
	var ids: Array[StringName] = [&"light_tank"]
	var armours: PackedInt32Array = [INFANTRY]
	# Past the armour table and below zero: the vehicle default, whatever the ids hold.
	assert_float(SpriteLift.bar_lift_px(ids, armours, 3)).is_equal(26.0)
	assert_float(SpriteLift.bar_lift_px(ids, armours, -1)).is_equal(26.0)
	assert_float(SpriteLift.centre_lift_px(ids, armours, 3)).is_equal(13.0)
	# A type that has an armour and no id (the tables are the snapshot's, so only a hand-made one).
	var armours_two: PackedInt32Array = [LIGHT, INFANTRY]
	assert_float(SpriteLift.bar_lift_px(ids, armours_two, 1)).is_equal(24.0)


func test_a_weapon_has_its_muzzle_height_and_an_unknown_one_the_default() -> void:
	var ids: Array[StringName] = [
		&"tank_cannon",
		&"heavy_cannon",
		&"artillery_gun",
		&"rocket",
		&"rifle",
		&"turret_gun",
		&"redoubt_gun",
		&"breaker_rocket",
		&"arcline_gun",
	]
	var expected: Array[float] = [14.0, 17.0, 18.0, 13.0, 11.0, 30.0, 30.0, 13.0, 18.0]
	for weapon: int in ids.size():
		(
			assert_float(SpriteLift.muzzle_lift_px(ids, weapon))
			. override_failure_message(String(ids[weapon]))
			. is_equal(expected[weapon])
		)
	var unknown: Array[StringName] = [&"plasma_lance"]
	assert_float(SpriteLift.muzzle_lift_px(unknown, 0)).is_equal(14.0)  # A name the table lacks.
	assert_float(SpriteLift.muzzle_lift_px(ids, 99)).is_equal(14.0)  # An index past the table.
	assert_float(SpriteLift.muzzle_lift_px(ids, -1)).is_equal(14.0)  # No weapon.


func test_every_weapon_a_shipped_unit_fires_has_a_muzzle_row() -> void:
	# Scans data/units, not a list typed here: a weapon that a roster adds without a row would
	# start its shots and flashes at the default height (the Redoubt's redoubt_gun did, after P107).
	var fired: Dictionary[StringName, String] = {}
	for path: String in FileScan.list_files(UNITS_DIR, ".tres"):
		var unit: UnitDef = load(path) as UnitDef
		assert_object(unit).override_failure_message(path).is_not_null()
		if unit.weapon != null:
			fired[unit.weapon.id] = path.get_file()
	# The scan reaches the units of both factions, so it cannot pass by finding nothing.
	assert_bool(fired.has(&"turret_gun") and fired.has(&"redoubt_gun")).is_true()
	assert_bool(fired.has(&"breaker_rocket") and fired.has(&"arcline_gun")).is_true()
	for weapon_id: StringName in fired:
		(
			assert_bool(SpriteLift.MUZZLE_PX.has(weapon_id))
			. override_failure_message(
				"%s (fired by %s) has no MUZZLE_PX row" % [weapon_id, fired[weapon_id]]
			)
			. is_true()
		)


func test_a_faction_weapon_stands_as_high_as_the_old_weapon_of_its_kind_of_shooter() -> void:
	# The interim rule of the table: the same kind of shooter, the same height, whichever faction.
	var pairs: Array[PackedStringArray] = [
		PackedStringArray(["defence_turret", "renew_defence"]),
		PackedStringArray(["rocket_squad", "renew_rocket"]),
		PackedStringArray(["artillery", "renew_artillery"]),
	]
	for pair: PackedStringArray in pairs:
		var ids: Array[StringName] = []
		for unit_id: String in pair:
			var unit: UnitDef = load(UNITS_DIR.path_join(unit_id + ".tres")) as UnitDef
			ids.append(unit.weapon.id)
		(
			assert_float(SpriteLift.muzzle_lift_px(ids, 1))
			. override_failure_message("%s and %s" % [pair[0], pair[1]])
			. is_equal(SpriteLift.muzzle_lift_px(ids, 0))
		)


func test_the_numbers_stay_inside_the_canvas_spec_ranges() -> void:
	# Spec section 05: combat vehicles and cars are 16 to 30 px high, an infantry figure 18 px (a
	# squad's frame holds three, so its top is a little higher), and a muzzle is below the top of
	# the frame it is on.
	var vehicles: Array[StringName] = [&"light_tank", &"heavy_tank", &"artillery", &"harvester"]
	for type_id: StringName in vehicles:
		assert_float(SpriteLift.BAR_PX[type_id]).is_between(16.0, 30.0)
	assert_float(SpriteLift.VEHICLE_BAR_PX).is_between(16.0, 30.0)
	assert_float(SpriteLift.INFANTRY_BAR_PX).is_between(18.0, 30.0)
	for weapon_id: StringName in [
		&"tank_cannon", &"heavy_cannon", &"artillery_gun", &"arcline_gun"
	]:
		assert_float(SpriteLift.MUZZLE_PX[weapon_id]).is_less(SpriteLift.VEHICLE_BAR_PX)
	for weapon_id: StringName in [&"rocket", &"rifle", &"breaker_rocket"]:
		assert_float(SpriteLift.MUZZLE_PX[weapon_id]).is_less(SpriteLift.INFANTRY_BAR_PX)
	assert_float(SpriteLift.MUZZLE_DEFAULT_PX).is_less(SpriteLift.VEHICLE_BAR_PX)
