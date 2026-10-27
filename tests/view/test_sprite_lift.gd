extends GdUnitTestSuite
## SpriteLift (P117b, P114b): how far above its ground point a thing of the view stands (ADR 0023
## sections 2 and 3). A unit with a sheet is lifted by the sheet's numbers (`bar_lift_px` for its
## bar, `pick_lift_px` for the middle of its frame, `muzzle_lift_px` for its shots); a unit with no
## sheet by the default of its class, which is from the canvas Spec, section 05 (a vehicle is 16 to
## 30 px high, a figure 18, a squad spreads over its third of a tile); a weapon whose shooter has no
## sheet to say by its row of the table. The sheets are generated data, so their numbers are made up
## here; the layers' use of the answers is in test_health_bars.gd, test_effects_layer.gd,
## test_projectile_layer.gd and test_lift_sheets.gd.
## P117c: a weapon of the faction rosters has its row, and a scan of data/units fails for any
## weapon a shipped unit fires that the muzzle table lacks.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const UNITS_DIR: String = "res://data/units/"
const LIGHT: int = World.Armour.LIGHT
const HEAVY: int = World.Armour.HEAVY
const INFANTRY: int = World.Armour.INFANTRY
const BUILDING: int = World.Armour.BUILDING


func test_a_unit_with_a_sheet_is_lifted_by_the_sheets_numbers_whatever_its_armour() -> void:
	# Numbers that no class default and no half of the bar's would give.
	var sheet: IsoSheetDef = _sheet(37, 19, 15)
	for armour: int in [LIGHT, HEAVY, INFANTRY, BUILDING]:
		assert_float(SpriteLift.bar_lift_px(sheet, armour)).is_equal(37.0)
		assert_float(SpriteLift.centre_lift_px(sheet, armour)).is_equal(19.0)


func test_a_unit_without_a_sheet_gets_the_default_of_its_class() -> void:
	# A type of the rosters that has no sheet yet: infantry 24, any other class 26, the middle of
	# the frame half of that.
	var expected: Dictionary[int, float] = {
		LIGHT: 26.0, HEAVY: 26.0, BUILDING: 26.0, INFANTRY: 24.0
	}
	for armour: int in expected:
		assert_float(SpriteLift.bar_lift_px(null, armour)).is_equal(expected[armour])
		assert_float(SpriteLift.centre_lift_px(null, armour)).is_equal(expected[armour] * 0.5)


func test_a_sheet_with_a_zero_lift_says_nothing_and_the_class_default_stands() -> void:
	# A sheet that has not been given its lifts (a hand-made one) is not a frame of no height.
	var blank: IsoSheetDef = _sheet(0, 0, 0)
	assert_float(SpriteLift.bar_lift_px(blank, LIGHT)).is_equal(26.0)
	assert_float(SpriteLift.bar_lift_px(blank, INFANTRY)).is_equal(24.0)
	assert_float(SpriteLift.centre_lift_px(blank, INFANTRY)).is_equal(12.0)
	var only_bar: IsoSheetDef = _sheet(40, 0, 0)  # The pick lift alone is missing: half the bar's.
	assert_float(SpriteLift.bar_lift_px(only_bar, LIGHT)).is_equal(40.0)
	assert_float(SpriteLift.centre_lift_px(only_bar, LIGHT)).is_equal(20.0)


func test_every_sheet_of_the_index_gives_its_own_numbers() -> void:
	var index: IsoIndex = load(IsoIndex.PATH) as IsoIndex
	assert_int(index.sheets.size()).is_greater(0)
	for sheet: IsoSheetDef in index.sheets:
		var note: String = String(sheet.art_id)
		assert_float(SpriteLift.bar_lift_px(sheet, LIGHT)).override_failure_message(note).is_equal(
			float(sheet.bar_lift_px)
		)
		(
			assert_float(SpriteLift.centre_lift_px(sheet, LIGHT))
			. override_failure_message(note)
			. is_equal(float(sheet.pick_lift_px))
		)
		assert_int(sheet.bar_lift_px).override_failure_message(note).is_greater(0)
		assert_int(sheet.pick_lift_px).override_failure_message(note).is_greater(0)


func test_a_shot_is_lifted_by_the_sheet_then_by_the_weapons_row_then_by_the_default() -> void:
	var ids: Array[StringName] = [&"tank_cannon", &"heavy_cannon", &"plasma_lance"]
	assert_float(SpriteLift.muzzle_lift_px(ids, 0, 9.0)).is_equal(9.0)  # The sheet's wins.
	assert_float(SpriteLift.muzzle_lift_px(ids, 0)).is_equal(14.0)  # A sheet that says nothing: 0.
	assert_float(SpriteLift.muzzle_lift_px(ids, 1, 0.0)).is_equal(17.0)  # The row.
	assert_float(SpriteLift.muzzle_lift_px(ids, 2)).is_equal(14.0)  # A name the table lacks.
	assert_float(SpriteLift.muzzle_lift_px(ids, 99)).is_equal(14.0)  # An index past the table.
	assert_float(SpriteLift.muzzle_lift_px(ids, -1)).is_equal(14.0)  # No weapon.
	assert_float(SpriteLift.muzzle_lift_px(ids, 99, 9.0)).is_equal(9.0)  # The sheet needs no row.


func test_the_rows_of_the_weapon_table_are_the_interim_numbers() -> void:
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


func test_the_defaults_stay_inside_the_canvas_spec_ranges() -> void:
	# Spec section 05: combat vehicles and cars are 16 to 30 px high, an infantry figure 18 px (a
	# squad's frame holds three, so its top is a little higher), and a muzzle is below the top of
	# the frame it is on.
	assert_float(SpriteLift.VEHICLE_BAR_PX).is_between(16.0, 30.0)
	assert_float(SpriteLift.INFANTRY_BAR_PX).is_between(18.0, 30.0)
	for weapon_id: StringName in [
		&"tank_cannon", &"heavy_cannon", &"artillery_gun", &"arcline_gun"
	]:
		assert_float(SpriteLift.MUZZLE_PX[weapon_id]).is_less(SpriteLift.VEHICLE_BAR_PX)
	for weapon_id: StringName in [&"rocket", &"rifle", &"breaker_rocket"]:
		assert_float(SpriteLift.MUZZLE_PX[weapon_id]).is_less(SpriteLift.INFANTRY_BAR_PX)
	assert_float(SpriteLift.MUZZLE_DEFAULT_PX).is_less(SpriteLift.VEHICLE_BAR_PX)


## A sheet with only its three lifts set.
func _sheet(bar: int, pick: int, muzzle: int) -> IsoSheetDef:
	var made: IsoSheetDef = IsoSheetDef.new()
	made.bar_lift_px = bar
	made.pick_lift_px = pick
	made.muzzle_lift_px = muzzle
	return made
