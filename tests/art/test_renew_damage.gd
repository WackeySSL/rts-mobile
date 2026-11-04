extends GdUnitTestSuite
## The eight Lumen Accord buildings in three damage stages (plan row P158b, ADR 0029).

const Support = preload("res://tests/art/artgen_v5_support.gd")
const IDS: Array[StringName] = [
	&"renew_barracks",
	&"renew_hq",
	&"renew_power",
	&"renew_refinery",
	&"renew_factory",
	&"renew_radar",
	&"renew_defence",
	&"renew_strike",
]
## The buildings with an `anim` and what it does at KRITISK (where its carrier stands or falls).
const ANIM_KRITISK: Dictionary[StringName, StringName] = {
	&"renew_barracks": &"run",
	&"renew_hq": &"hide",
	&"renew_power": &"hide",
	&"renew_radar": &"hide",
	&"renew_strike": &"run",
}

var _index: IsoIndex = load(IsoIndex.PATH) as IsoIndex


func _model(id: StringName) -> ArtModel:
	return load("res://assets/art/models/renew/%s.tres" % id) as ArtModel


func test_each_building_has_both_patches_and_a_sound_model() -> void:
	for id: StringName in IDS:
		var model: ArtModel = _model(id)
		assert_array(model.damage_parts()).override_failure_message(String(id)).is_equal(
			[&"dmg1", &"dmg2"]
		)
		assert_array(Array(model.problems())).override_failure_message(String(id)).is_empty()
		var sheet: IsoSheetDef = _index.sheet(id)
		assert_bool(sheet.has_part(&"dmg1") and sheet.has_part(&"dmg2")).is_true()
		assert_int(sheet.cuts.size()).is_equal(2)
		# No ruin picture.
		assert_bool(sheet.has_part(&"ruin")).is_false()


func test_each_building_has_two_to_four_typed_damage_points() -> void:
	var kinds: Array[StringName] = [&"damage", &"dmg_gas", &"dmg_spark"]
	for id: StringName in IDS:
		var points: int = 0
		for entry: Array in _model(id).emitter_list():
			if entry[0] in kinds:
				points += 1
		var why: String = "%s has %d points" % [id, points]
		assert_bool(points >= 2 and points <= 4).override_failure_message(why).is_true()


func test_the_key_share_of_each_stage_is_inside_the_bands() -> void:
	for id: StringName in IDS:
		var found: PackedStringArray = Support.share_problems(_model(id))
		assert_array(Array(found)).override_failure_message(String(id)).is_empty()


func test_anim_kritisk_is_set_for_each_building_with_an_anim() -> void:
	for id: StringName in IDS:
		var model: ArtModel = _model(id)
		var sheet: IsoSheetDef = _index.sheet(id)
		if ANIM_KRITISK.has(id):
			assert_bool(sheet.has_part(&"anim")).override_failure_message(String(id)).is_true()
			assert_str(String(model.anim_kritisk)).is_equal(String(ANIM_KRITISK[id]))
			assert_bool(sheet.anim_kritisk).is_equal(ANIM_KRITISK[id] == &"run")
		else:
			assert_bool(sheet.has_part(&"anim")).override_failure_message(String(id)).is_false()


func test_the_refinery_steam_emitters_name_their_groups_and_go_quiet_at_the_stage_that_breaks_them(
) -> void:
	var sheet: IsoSheetDef = _index.sheet(&"renew_refinery")
	assert_array(Array(sheet.emitters).slice(0, 2)).is_equal(["steam", "steam"])
	assert_array(Array(sheet.emitter_quiet).slice(0, 2)).is_equal([1, 2])


func test_the_collapse_shows_its_inside_and_no_stage_reaches_the_foot() -> void:
	for id: StringName in IDS:
		var model: ArtModel = _model(id)
		var materials: Array[String] = []
		for line: String in model.prims:
			if line.contains("damage=2"):
				materials.append(line.split(" ")[2])
		var why: String = "%s needs an interior at KRITISK" % id
		assert_bool("interior" in materials).override_failure_message(why).is_true()
		var body: int = _index.sheet(id).frame_size(&"hull").y
		for cut: int in _index.sheet(id).cuts:
			(
				assert_bool(cut + ArtGen.CUT_OVERLAP_PX <= body)
				. override_failure_message(String(id))
				. is_true()
			)


func test_skadet_stays_within_80_percent_of_the_hull_and_kritisk_is_deeper() -> void:
	# Michael's cap of 2026-11-04: no SKADET cut passes 80 % of the hull's rows.
	for id: StringName in IDS:
		var sheet: IsoSheetDef = _index.sheet(id)
		var rows: float = float(sheet.frame_size(&"hull").y)
		var why: String = "%s SKADET cut %d of %d rows" % [id, sheet.cuts[0], rows]
		assert_bool(sheet.cuts[0] <= 0.80 * rows).override_failure_message(why).is_true()
		assert_int(sheet.cuts[1]).override_failure_message(String(id)).is_greater(sheet.cuts[0])
