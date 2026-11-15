extends GdUnitTestSuite
## The two airfields' art (plan row P245b, STYLE.md "The airfields"): the Derrick League's Flight
## Yard (`fossil_airfield`) and the Lumen Accord's Glide Deck (`renew_airfield`), each a 3 x 3 model
## with four landing pads at the corners of its footprint (the cells of `BuildingDef.pad_offsets`),
## a KRITISK picture, no SKADET picture (ADR 0034) and one cast shadow. It pins what the row
## promises: the sheet's parts, the pads where the data puts them, the team share at zoom 1 (the
## rule asks for 8 to 12 %), the KRITISK share in ADR 0029's band, a shadow that is one connected
## mark, and the silhouettes at 32 px in greyscale against every other building. That the bytes
## equal a fresh run is test_artgen.gd.

const MODEL: String = "res://assets/art/models/%s/%s.tres"
const Support: GDScript = preload("res://tests/art/building_picture_support.gd")
const DamageSupport: GDScript = preload("res://tests/art/artgen_v5_support.gd")
const IDS: Array[StringName] = [&"fossil_airfield", &"renew_airfield"]
const FACTION: Dictionary[StringName, StringName] = {
	&"fossil_airfield": &"fossil", &"renew_airfield": &"renew"
}
const VIEW_DIR: Dictionary[StringName, int] = {&"fossil": 6, &"renew": 10}
const SHARE: Vector2 = Vector2(0.08, 0.12)
const MAX_OVERLAP: float = 0.85
## The pad cells of the data, 3 x 3 with the centre of the footprint at the origin.
const PAD_CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2)]

var _index: IsoIndex = null


func before() -> void:
	_index = load(IsoIndex.PATH) as IsoIndex


func test_a_sheet_has_a_body_a_kritisk_patch_and_a_shadow_and_the_card() -> void:
	for id: StringName in IDS:
		var model: ArtModel = load(MODEL % [FACTION[id], id]) as ArtModel
		assert_array(Array(model.problems())).override_failure_message(String(id)).is_empty()
		assert_int(model.footprint).is_equal(3)
		assert_bool(model.silhouette.contains("\n")).is_false()
		var sheet: IsoSheetDef = _index.sheet(id)
		assert_array(Array(sheet.parts)).override_failure_message(String(id)).is_equal(
			["hull", "dmg2", "shadow"]
		)
		assert_bool(sheet.has_part(&"dmg1")).is_false()  # No SKADET picture (ADR 0034).
		assert_bool(sheet.icon.ends_with("item_%s.svg" % id)).is_true()
		assert_bool(FileAccess.file_exists(sheet.icon)).is_true()


## The four pads sit where the airfield's data puts its pad cells: one flat team-ringed pad
## primitive group per corner cell, centred on the cell.
func test_the_four_pads_sit_on_the_pad_cells_of_the_data() -> void:
	for id: StringName in IDS:
		var def: BuildingDef = load("res://data/units/%s.tres" % id) as BuildingDef
		assert_int(def.pads).is_equal(4)
		var model: ArtModel = load(MODEL % [FACTION[id], id]) as ArtModel
		var rings: Array[Vector2] = []
		for prim: ArtPrim in model.primitives(&"hull"):
			if String(prim.group).begins_with("padring"):
				rings.append(prim.centre)
		assert_int(rings.size()).override_failure_message(String(id)).is_equal(4)
		for cell: Vector2i in def.pad_offsets:
			var want: Vector2 = Vector2(cell) - Vector2(1.0, 1.0)
			assert_bool(rings.has(want)).override_failure_message("%s %s" % [id, want]).is_true()
			assert_bool(cell in PAD_CELLS).is_true()


func test_the_team_share_of_the_default_view_is_8_to_12_percent_at_zoom_1() -> void:
	for id: StringName in IDS:
		var sheet: IsoSheetDef = _index.sheet(id)
		var picture: Image = Support.default_picture(sheet, VIEW_DIR[FACTION[id]])
		var share: float = Support.team_share(picture, FACTION[id])
		assert_float(share).override_failure_message("%s team share %.3f" % [id, share]).is_between(
			SHARE.x, SHARE.y
		)


## ADR 0029 section 5: the KRITISK picture keeps 20 to 50 % of the intact picture's team colour.
func test_the_kritisk_picture_keeps_its_team_colour_in_the_band() -> void:
	for id: StringName in IDS:
		var model: ArtModel = load(MODEL % [FACTION[id], id]) as ArtModel
		assert_array(Array(DamageSupport.share_problems(model))).is_empty()
		var share: float = DamageSupport.key_share(model, 2)
		var band: Vector2 = DamageSupport.SHARE_BANDS[1]
		assert_float(share).override_failure_message("%s: %.2f" % [id, share]).is_between(
			band.x, band.y
		)


func test_the_cast_shadow_is_one_connected_mark() -> void:
	for id: StringName in IDS:
		var sheet: IsoSheetDef = _index.sheet(id)
		var shadow: Image = Support.raster(
			FileAccess.get_file_as_string(sheet.path(&"shadow", -1)), 1.0
		)
		shadow.convert(Image.FORMAT_RGBA8)
		for y: int in shadow.get_height():
			for x: int in shadow.get_width():
				if shadow.get_pixel(x, y).a > 0.0:
					shadow.set_pixel(x, y, Color.BLACK)
		assert_int(Support.pieces(shadow)).override_failure_message(String(id)).is_equal(1)


func test_each_reads_apart_from_every_other_building_at_32_px_in_greyscale() -> void:
	var masks: Dictionary[StringName, Image] = {}
	for sheet: IsoSheetDef in _index.sheets:
		if sheet.category == &"bld":
			masks[sheet.art_id] = Support.mask_32(
				Support.default_picture(sheet, 6 if sheet.faction == &"fossil" else 10)
			)
	assert_int(masks.size()).is_equal(22)
	for id: StringName in IDS:
		var ink: int = 0
		for y: int in 32:
			for x: int in 32:
				ink += int(masks[id].get_pixel(x, y).a > 0.5)
		assert_float(float(ink) / 1024.0).override_failure_message("%s fills" % id).is_greater(0.1)
		for other: StringName in masks:
			if other == id:
				continue
			var overlap: float = Support.overlap(masks[id], masks[other])
			(
				assert_float(overlap)
				. override_failure_message("%s against %s: %.2f" % [id, other, overlap])
				. is_less(MAX_OVERLAP)
			)
