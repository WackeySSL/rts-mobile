extends GdUnitTestSuite
## The two anti-air buildings' art (plan row P239b, STYLE.md "The anti-air buildings"): the Derrick
## League's Burst Stack (`fossil_aa`) and the Lumen Accord's Sky Needle (`renew_aa`), each a 1 x 1
## model with a head in 16 directions, a KRITISK picture, no SKADET picture (ADR 0034) and one
## cast shadow. It pins what the row and the style guide promise: the sheet's parts, the head's
## directions, the recoil rows of the two guns, the team share at zoom 1 (the rule asks for
## 8 to 12 %; the other zooms are the gallery's to judge), a shadow that is one connected mark,
## and the silhouettes at 32 px in greyscale against every other building. That the bytes equal a
## fresh run is test_artgen.gd.

const MODEL: String = "res://assets/art/models/%s/%s.tres"
const LIFE_PATH: String = "res://data/life_settings.tres"
const Support: GDScript = preload("res://tests/art/building_picture_support.gd")
const DamageSupport: GDScript = preload("res://tests/art/artgen_v5_support.gd")
const IDS: Array[StringName] = [&"fossil_aa", &"renew_aa"]
const FACTION: Dictionary[StringName, StringName] = {&"fossil_aa": &"fossil", &"renew_aa": &"renew"}
const GUN: Dictionary[StringName, StringName] = {
	&"fossil_aa": &"burst_stack_gun", &"renew_aa": &"sky_needle_gun"
}
const VIEW_DIR: Dictionary[StringName, int] = {&"fossil": 6, &"renew": 10}
## Zoom 1 of the 2x art: the zoom every building suite measures the share at.
const SCALE: float = 0.5
## The rule's band at the default view of zoom 1, and the margin the suites allow elsewhere.
const SHARE: Vector2 = Vector2(0.08, 0.12)
const SHARE_WIDE: Vector2 = Vector2(0.07, 0.13)
## How much of another building's 32 px silhouette an anti-air building may cover (both over
## either); the nearest pairs of the 18 older buildings are below it too.
const MAX_OVERLAP: float = 0.85

var _index: IsoIndex = null


func before() -> void:
	_index = load(IsoIndex.PATH) as IsoIndex


func test_a_sheet_has_a_body_a_head_in_16_directions_a_kritisk_patch_and_a_shadow() -> void:
	for id: StringName in IDS:
		var model: ArtModel = load(MODEL % [FACTION[id], id]) as ArtModel
		assert_str(String(model.art_id)).is_equal(String(id))
		assert_int(model.footprint).is_equal(1)
		var sheet: IsoSheetDef = _index.sheet(id)
		assert_array(Array(sheet.parts)).override_failure_message(String(id)).is_equal(
			["hull", "head", "dmg2", "shadow"]
		)
		assert_array(sheet.directions(&"head")).is_equal(range(16))
		assert_bool(sheet.has_part(&"anim")).is_false()
		assert_bool(sheet.has_part(&"dmg1")).is_false()  # No SKADET picture (ADR 0034).
		for dir: int in 16:
			assert_bool(FileAccess.file_exists(sheet.path(&"head", dir))).is_true()
		assert_int(sheet.boxes.size()).is_equal(16 * 4)  # One tight box per head direction.
		assert_bool(sheet.icon.ends_with("item_%s.svg" % id)).is_true()
		assert_bool(FileAccess.file_exists(sheet.icon)).is_true()


func test_each_gun_has_a_recoil_row_for_its_head() -> void:
	var life: LifeSettings = load(LIFE_PATH) as LifeSettings
	var defaults: LifeSettings = LifeSettings.new()
	for id: StringName in IDS:
		var gun: StringName = GUN[id]
		assert_bool(life.recoil_px.has(gun)).override_failure_message(String(gun)).is_true()
		assert_float(life.recoil_px[gun]).is_greater(0.0)
		assert_float(defaults.recoil_px[gun]).is_equal(life.recoil_px[gun])
		# No hull to rock: a defence's body never moves.
		assert_bool(life.rock_px.has(gun)).is_false()


func test_the_team_share_of_the_default_view_is_8_to_12_percent_at_zoom_1() -> void:
	for id: StringName in IDS:
		var share: float = _share(id, VIEW_DIR[FACTION[id]])
		assert_float(share).override_failure_message("%s team share %.3f" % [id, share]).is_between(
			SHARE.x, SHARE.y
		)


func test_the_team_share_holds_in_every_head_direction_at_zoom_1() -> void:
	for id: StringName in IDS:
		for dir: int in 16:
			var share: float = _share(id, dir)
			(
				assert_float(share)
				. override_failure_message("%s d%02d: %.3f" % [id, dir, share])
				. is_between(SHARE_WIDE.x, SHARE_WIDE.y)
			)


## ADR 0029 section 5: the KRITISK picture keeps 20 to 50 % of the intact picture's team colour
## (SKADET has no picture, ADR 0034).
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
		# The shadow is a translucent group: make every touched pixel solid for the count.
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
	assert_int(masks.size()).is_equal(26)
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


## The team share of the picture at head direction `dir` and zoom 1.
func _share(id: StringName, dir: int) -> float:
	var sheet: IsoSheetDef = _index.sheet(id)
	var picture: Image = Image.create_empty(
		Support.PAGE.x, Support.PAGE.y, false, Image.FORMAT_RGBA8
	)
	var body: Image = Support.raster(FileAccess.get_file_as_string(sheet.path(&"hull", -1)), SCALE)
	var ground: Vector2i = Support.GROUND_POINT
	picture.blend_rect(
		body,
		Rect2i(Vector2i.ZERO, body.get_size()),
		ground - Vector2i(Vector2(sheet.origin(&"hull")) * SCALE)
	)
	var head: Image = Support.raster(FileAccess.get_file_as_string(sheet.path(&"head", dir)), SCALE)
	var at: Vector2 = sheet.mount(0) - Vector2(sheet.origin(&"head"))
	picture.blend_rect(head, Rect2i(Vector2i.ZERO, head.get_size()), ground + Vector2i(at * SCALE))
	return Support.team_share(picture, FACTION[id])
