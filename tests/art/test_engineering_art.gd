extends GdUnitTestSuite
## The two engineering centres' art (plan row P249, STYLE.md "The engineering centres"): the
## Derrick League's Draft Shop (`fossil_engineering`) and the Lumen Accord's Lens Works
## (`renew_engineering`), each a 2 x 2 model with a hull, a KRITISK picture, no SKADET picture
## (ADR 0034), no moving element and one cast shadow. It pins what the row promises: the sheet's
## parts, the card, the team share at zoom 1 (the rule asks for 8 to 12 %), the KRITISK share in
## ADR 0029's band, a shadow that is one connected mark, and the silhouettes at 32 px in greyscale
## against every other building. That the bytes equal a fresh run is test_artgen.gd.

const MODEL: String = "res://assets/art/models/%s/%s.tres"
const Support: GDScript = preload("res://tests/art/building_picture_support.gd")
const DamageSupport: GDScript = preload("res://tests/art/artgen_v5_support.gd")
const IDS: Array[StringName] = [&"fossil_engineering", &"renew_engineering"]
const FACTION: Dictionary[StringName, StringName] = {
	&"fossil_engineering": &"fossil", &"renew_engineering": &"renew"
}
const VIEW_DIR: Dictionary[StringName, int] = {&"fossil": 6, &"renew": 10}
const SHARE: Vector2 = Vector2(0.08, 0.12)
const MAX_OVERLAP: float = 0.85
## The four research cards are hand-written (test_artgen.gd's HAND_CARDS leaves them out of its
## generated-file checks), so the rules of a hand-written file are pinned here.
const CARD_DIR: String = "res://assets/art/iso/icons/item_%s.svg"
const CARD_FACTION: Dictionary[String, StringName] = {
	"heavy_bombs": &"fossil",
	"plated_hull": &"fossil",
	"focus_bombs": &"renew",
	"glaze_hull": &"renew",
}
const CARD_TAGS: Array[String] = ["svg", "g", "polygon", "path", "rect", "circle"]
const CARD_BANNED: Array[String] = [
	"href", "<style", "<text", "<image", "<filter", "<script", "<pattern", "<foreignObject"
]
const CARD_MAX_BYTES: int = 28 * 1024
const HEADER_LINES: int = 32  ## The comment, the svg tag, the plate, the grid and the corner.

var _index: IsoIndex = null


func before() -> void:
	_index = load(IsoIndex.PATH) as IsoIndex


func test_a_sheet_has_a_body_a_kritisk_patch_and_a_shadow_and_the_card() -> void:
	for id: StringName in IDS:
		var model: ArtModel = load(MODEL % [FACTION[id], id]) as ArtModel
		assert_array(Array(model.problems())).override_failure_message(String(id)).is_empty()
		assert_int(model.footprint).is_equal(2)
		assert_bool(model.silhouette.contains("\n")).is_false()
		var sheet: IsoSheetDef = _index.sheet(id)
		assert_array(Array(sheet.parts)).override_failure_message(String(id)).is_equal(
			["hull", "dmg2", "shadow"]
		)
		assert_bool(sheet.has_part(&"dmg1")).is_false()  # No SKADET picture (ADR 0034).
		assert_bool(sheet.icon.ends_with("item_%s.svg" % id)).is_true()
		assert_bool(FileAccess.file_exists(sheet.icon)).is_true()


func test_the_model_matches_the_footprint_of_its_data() -> void:
	for id: StringName in IDS:
		var def: BuildingDef = load("res://data/units/%s.tres" % id) as BuildingDef
		var model: ArtModel = load(MODEL % [FACTION[id], id]) as ArtModel
		assert_that(def.footprint).is_equal(Vector2i(model.footprint, model.footprint))


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


func test_a_research_card_uses_only_the_hand_written_tags_and_stays_small() -> void:
	var tag: RegEx = RegEx.create_from_string("<([A-Za-z]+)")
	for id: String in CARD_FACTION:
		var text: String = FileAccess.get_file_as_string(CARD_DIR % id)
		assert_bool(text.length() > 0).override_failure_message(id).is_true()
		assert_int(text.to_utf8_buffer().size()).is_less_equal(CARD_MAX_BYTES)
		for banned: String in CARD_BANNED:
			assert_bool(text.contains(banned)).override_failure_message(id + banned).is_false()
		for found: RegExMatch in tag.search_all(text):
			assert_array(CARD_TAGS).override_failure_message(id).contains([found.get_string(1)])
		assert_bool(text.contains('viewBox="0 0 128 128"')).is_true()


## What a hand-written card may paint (ADR 0023 section 5 and "Research cards" in STYLE.md): from
## the first line after the plate, grid and corner, every fill and stroke is `#RRGGBB` or `none`
## (no short hex, no name, no rgb(), no single quotes), and each colour is a tone or an edge of one
## of the faction's `ArtPalette` materials or its key triad. Team colour is only the triad, so
## the key band holds without a check of its own.
func test_a_research_card_paints_only_palette_tones_and_its_key_triad() -> void:
	for id: String in CARD_FACTION:
		var faction: StringName = CARD_FACTION[id]
		var lines: PackedStringArray = FileAccess.get_file_as_string(CARD_DIR % id).split("\n")
		var picture: PackedStringArray = lines.slice(HEADER_LINES)
		(
			assert_array(Array(_colour_problems(faction, picture)))
			. override_failure_message(id)
			. is_empty()
		)
		var team: int = 0
		for level: int in 3:  # A card is no player's: its team zones wear the faction colour.
			team += "\n".join(picture).count(ArtPalette.tone(faction, ArtPalette.FACTION, level))
		assert_int(team).override_failure_message(id + " has no team colour").is_greater(0)


## The checker itself bites: each of these planted colours is refused.
func test_the_card_colour_check_refuses_a_bad_colour() -> void:
	var good: String = '<path d="M0 0" fill="#D234D2" stroke="none"/>'
	assert_array(Array(_colour_problems(&"fossil", PackedStringArray([good])))).is_empty()
	for bad: String in [
		'fill="#F94"',
		'fill="red"',
		'fill="rgb(255,0,0)"',
		"fill='#D234D2'",
		'stroke="#FF00FF"',  # Not a tone: a pure magenta in the key band.
		'fill="#D234D3"',  # A shade next to the triad, in the key band.
		'fill="#123456"',  # Not a palette tone.
		'fill="#d234d2"',  # Lower case.
	]:
		var line: PackedStringArray = PackedStringArray(['<path d="M0 0" %s/>' % bad])
		(
			assert_array(Array(_colour_problems(&"fossil", line)))
			. override_failure_message(bad)
			. is_not_empty()
		)
	# A Lumen Accord tone is not a Derrick League one.
	var other: PackedStringArray = PackedStringArray(['<path fill="#D5DBDC"/>'])
	assert_array(Array(_colour_problems(&"fossil", other))).is_not_empty()
	assert_array(Array(_colour_problems(&"renew", other))).is_empty()


## One text per fill or stroke of `lines` that is not `#RRGGBB` / `none` or not an allowed colour.
func _colour_problems(faction: StringName, lines: PackedStringArray) -> PackedStringArray:
	var allowed: Dictionary[String, bool] = {}
	for hex: String in ArtPalette.KEYS[faction]:
		allowed[hex] = true
	for material: StringName in ArtPalette.MATERIALS[faction]:
		for level: int in 3:
			allowed[ArtPalette.tone(faction, material, level)] = true
		allowed[ArtPalette.edge(faction, material, false)] = true
		allowed[ArtPalette.edge(faction, material, true)] = true
	var found: PackedStringArray = PackedStringArray()
	for line: String in lines:
		for attr: String in ["fill", "stroke"]:
			for quote: String in ["'", '"']:
				var start: int = 0
				while true:
					var at: int = line.find("%s=%s" % [attr, quote], start)
					if at < 0:
						break
					start = at + 1
					var from: int = at + attr.length() + 2
					var value: String = line.substr(from, line.find(quote, from) - from)
					if quote == "'":
						found.append("single quotes: " + value)
					elif value == "none":
						continue
					elif (
						not value.is_valid_html_color()
						or not (value.length() == 7 and value.begins_with("#"))
					):
						found.append("not #RRGGBB: " + value)
					elif value != value.to_upper() or not allowed.has(value):
						found.append("not a palette tone: " + value)
	return found


## The plate, the grid and the corner are the generator's, byte for byte: a hand card sits in the
## Build tab beside the generated ones.
func test_a_research_card_has_the_generators_plate_grid_and_corner() -> void:
	for id: String in CARD_FACTION:
		var faction: StringName = CARD_FACTION[id]
		var generated: PackedStringArray = (
			FileAccess.get_file_as_string(CARD_DIR % (String(faction) + "_engineering")).split("\n")
		)
		var hand: PackedStringArray = FileAccess.get_file_as_string(CARD_DIR % id).split("\n")
		for at: int in range(1, HEADER_LINES):
			assert_str(hand[at]).override_failure_message("%s line %d" % [id, at]).is_equal(
				generated[at]
			)


func test_a_research_card_is_a_texture_import() -> void:
	for id: String in CARD_FACTION:
		var import: String = FileAccess.get_file_as_string((CARD_DIR % id) + ".import")
		assert_str(import).contains('importer="texture"')
		assert_str(import).not_contains("keep")
