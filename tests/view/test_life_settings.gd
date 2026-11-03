extends GdUnitTestSuite
## The numbers of the unit life (plan P136, ADR 0027 section 8): `LifeSettings` holds the field of
## every core row (P136 to P145) with its default, `data/life_settings.tres` writes every default
## out, every life consumer falls back to that file when its `life` is unset and keeps one it is
## given, every weapon that a turreted vehicle or a defence fires has a recoil row, and the
## simulation never loads the file (view only, not in `defs_hash`).

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const PATH: String = "res://data/life_settings.tres"
const UNITS_DIR: String = "res://data/units/"
## Every field of the core rows with its default, typed again here so a changed default or a lost
## field fails. The dictionaries are listed below, apart.
const SCALARS: Dictionary[StringName, Variant] = {
	&"reduced": false,
	&"recoil_out_ms": 50,
	&"recoil_back_ms": 200,
	&"kick_slots": 128,
	&"shake_px": 0.5,
	&"shake_ms": 80,
	&"look_every_ms": 6000,
	&"look_every_spread_ms": 4000,
	&"look_ms": 900,
	&"sweep_frames": 2,
	&"sweep_ms": 700,
	&"idle_after_ms": 1500,
	&"idle_every_ms": 4000,
	&"idle_every_spread_ms": 3000,
	&"idle_ms": 600,
	&"dust_every_milli": 700,
	&"dust_life_ms": 600,
	&"dust_slots": 48,
	&"launch_ms": 700,
	&"fall_ms": 600,
	&"net_land_ms": 600,
	&"strike_slots": 8,
	&"low_power_rate": 0.5,
	&"emit_rise_px": 24.0,
	&"emit_drift_px": 6.0,
	&"emitter_slots": 80,
	&"dust_back_milli": 300,
	&"dust_alpha": 0.8,
	&"dust_grow_from": 0.6,
	&"dust_grow_to": 1.2,
	&"strike_rise_px": 96.0,
	&"launch_flash_ms": 250,
	&"fall_shadow_from": 0.4,
	&"fall_shadow_alpha": 0.5,
	&"net_scale_from": 1.6,
	&"net_alpha": 0.9,
	&"net_settle_ms": 500,
	&"launch_ring_grow_to": 2.0,
}
const RECOIL: Dictionary[StringName, float] = {
	&"tank_cannon": 3.0,
	&"heavy_cannon": 4.0,
	&"turret_gun": 2.5,
	&"artillery_gun": 5.0,
	&"redoubt_gun": 2.5,
	&"arcline_gun": 4.0,
}
const ROCK: Dictionary[StringName, float] = {
	&"heavy_cannon": 1.0,
	&"artillery_gun": 1.5,
	&"arcline_gun": 1.0,
}
const EMIT_MS: Dictionary[StringName, int] = {&"smoke": 700, &"steam": 600, &"flare": 500}
const EMIT_LIFE_MS: Dictionary[StringName, int] = {&"smoke": 1800, &"steam": 1200, &"flare": 700}


func test_the_script_defaults_are_the_documented_ones() -> void:
	_check(LifeSettings.new())


func test_the_data_file_writes_every_default_out() -> void:
	var file: LifeSettings = load(PATH) as LifeSettings
	assert_object(file).is_not_null()
	_check(file)
	# Written out, not left to the script's defaults: every field is a line of the file, as
	# input_settings.tres has them, so a tuner sees all of them.
	var text: String = FileAccess.get_file_as_string(PATH)
	for field: StringName in SCALARS:
		assert_str(text).override_failure_message(String(field)).contains("\n%s = " % field)
	for field: String in ["recoil_px", "rock_px", "emit_ms", "emit_life_ms"]:
		assert_str(text).override_failure_message(field).contains("\n%s = " % field)


func test_the_settings_have_exactly_the_fields_of_the_core_rows() -> void:
	var fields: Array[String] = []
	for property: Dictionary in LifeSettings.new().get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
			fields.append(String(property["name"]))
	fields.sort()
	var expected: Array[String] = ["recoil_px", "rock_px", "emit_ms", "emit_life_ms"]
	for field: StringName in SCALARS:
		expected.append(String(field))
	expected.sort()
	assert_array(fields).is_equal(expected)


func test_a_consumer_without_settings_falls_back_to_the_data_file_and_keeps_one_it_is_given(
) -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var file: LifeSettings = load(PATH) as LifeSettings
	var units: UnitLayer = auto_free(UnitLayer.new())
	units.runner = runner
	add_child(units)
	assert_object(units.life).is_same(file)
	var buildings: BuildingLayer = auto_free(BuildingLayer.new())
	buildings.runner = runner
	add_child(buildings)
	assert_object(buildings.life).is_same(file)
	var own: LifeSettings = file.duplicate() as LifeSettings
	var given: UnitLayer = auto_free(UnitLayer.new())
	given.runner = runner
	given.life = own
	add_child(given)
	assert_object(given.life).is_same(own)
	var given_buildings: BuildingLayer = auto_free(BuildingLayer.new())
	given_buildings.runner = runner
	given_buildings.life = own
	add_child(given_buildings)
	assert_object(given_buildings.life).is_same(own)


func test_every_weapon_a_turreted_vehicle_or_a_defence_fires_has_a_recoil_row() -> void:
	# The scan reads data/units and the sheets, not a list typed here: a roster that adds a turreted
	# unit with a new weapon and no row would kick nothing.
	var turreted: Dictionary[StringName, bool] = {}
	for sheet: IsoSheetDef in IsoAtlas.load_sheets():
		if sheet.has_part(&"turret") or sheet.has_part(&"head"):
			turreted[sheet.art_id] = true
	var file: LifeSettings = load(PATH) as LifeSettings
	var found: int = 0
	for path: String in FileScan.list_files(UNITS_DIR, ".tres"):
		var unit: UnitDef = load(path) as UnitDef
		if unit.weapon == null or not turreted.has(unit.type_id):
			continue
		found += 1
		var note: String = "%s fires %s" % [unit.type_id, unit.weapon.id]
		assert_bool(file.recoil_px.has(unit.weapon.id)).override_failure_message(note).is_true()
		assert_float(file.recoil_px[unit.weapon.id]).override_failure_message(note).is_greater(0.0)
	assert_int(found).is_equal(8)  # 4 tanks and 2 artillery pieces, and the 2 defences.


func test_the_simulation_and_the_ai_know_nothing_of_the_life_numbers() -> void:
	var names: Array[String] = ["LifeSettings", "life_settings", "LifeClock", "RigLife"]
	for dir: String in ["res://game/sim", "res://game/ai", "res://native/sim_kernels/src"]:
		for path: String in FileScan.list_files(dir, ".gd") + FileScan.list_files(dir, ".cpp"):
			var text: String = FileAccess.get_file_as_string(path)
			for name: String in names:
				assert_bool(text.contains(name)).override_failure_message(path).is_false()


## `settings` holds every default of the tables above.
func _check(settings: LifeSettings) -> void:
	for field: StringName in SCALARS:
		var note: String = String(field)
		assert_that(settings.get(field)).override_failure_message(note).is_equal(SCALARS[field])
	assert_dict(settings.recoil_px).is_equal(RECOIL)
	assert_dict(settings.rock_px).is_equal(ROCK)
	assert_dict(settings.emit_ms).is_equal(EMIT_MS)
	assert_dict(settings.emit_life_ms).is_equal(EMIT_LIFE_MS)
	for kind: StringName in settings.emit_ms:  # ADR 0027 section 3: at most 4 puffs alive.
		assert_int(settings.emit_ms[kind]).is_greater_equal(500)
		assert_int(settings.emit_life_ms[kind]).is_less_equal(2000)
	assert_int(settings.recoil_back_ms).is_greater(settings.recoil_out_ms)
