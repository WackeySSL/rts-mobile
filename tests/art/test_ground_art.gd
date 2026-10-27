extends GdUnitTestSuite
## The iso ground of plan row P105 (ADR 0023 sections 5 and 6, STYLE.md "Iso ground tiles"): twelve
## 128 x 64 diamonds, an a and a b for each terrain id of `data/terrain/standard.tres`, that tile
## together without a seam at the three camera zooms and have no rim (Michael, 2026-10-27: the soft
## rim of ADR 0023 section 5 read as a grid), the greyscale means that tell the six terrains apart
## at 32 px, and the off-map colour. The field stages, the wellhead and the crater are in
## test_field_art.gd; the texts are in test_ground_art_docs.gd.

const Support: GDScript = preload("res://tests/art/ground_art_support.gd")
const TerrainPage: GDScript = preload("res://game/view/art_gallery_ground.gd")
## The base colour of each terrain's diamond: the fill that reaches every edge (STYLE.md).
const BASE: Dictionary[StringName, String] = {
	&"grass": "#6F8F57",
	&"sand": "#CDB98F",
	&"scrub": "#58653F",
	&"rock": "#726E69",
	&"water": "#2A5978",
	&"ore": "#51433A",
}
const ZOOMS: Array[float] = [0.375, 0.5, 0.75]  ## 0.75, 1 and 1.5 times the base scale of 0.5.
## Rec. 601 luminance means at 32 px, as STYLE.md ("Iso ground tiles") lists them.
const GREY: Dictionary[String, int] = {
	"grass_a": 126,
	"grass_b": 126,
	"sand_a": 185,
	"sand_b": 185,
	"scrub_a": 97,
	"scrub_b": 96,
	"rock_a": 109,
	"rock_b": 110,
	"water_a": 83,
	"water_b": 83,
	"ore_a": 70,
	"ore_b": 70,
}


func test_the_terrain_ids_are_those_of_the_defs_and_each_has_an_a_and_a_b_of_128_by_64() -> void:
	var ids: Array[StringName] = []
	for terrain: TerrainDef in (load(Support.TERRAIN_SET) as TerrainSetDef).terrains:
		ids.append(terrain.id)
	assert_array(ids).is_equal(Support.TERRAIN_IDS)
	assert_array(Support.FileScan.list_files(Support.GROUND_DIR, ".svg")).has_size(12)
	for id: StringName in ids:
		for variant: String in ["a", "b"]:
			var path: String = Support.ground_path(id, variant)
			var head: String = Support.text(path).split("\n")[2]
			assert_str(head).override_failure_message(path).contains(
				'width="128" height="64" viewBox="0 0 128 64"'
			)
			# Imported at scale 0.5: one tile is 64 x 32 px in game.
			var size: Vector2 = (load(path) as Texture2D).get_size()
			assert_vector(size).override_failure_message(path).is_equal(Vector2(64, 32))


func test_a_diamond_fills_its_cell_to_every_edge_and_leaves_the_canvas_corners_clear() -> void:
	for id: StringName in Support.TERRAIN_IDS:
		for variant: String in ["a", "b"]:
			var image: Image = Support.raster(Support.ground_path(id, variant), 1.0)
			assert_vector(Vector2(image.get_size())).is_equal(Vector2(Support.TILE))
			var problems: Array[String] = []
			for y: int in Support.TILE.y:
				for x: int in Support.TILE.x:
					var m: float = Support.metric(x, y, Support.TILE)
					var alpha: float = image.get_pixel(x, y).a
					if m <= 0.99 and alpha < 0.99:
						problems.append("%d,%d is not opaque" % [x, y])
					elif m >= 1.12 and alpha > 0.02:
						problems.append("%d,%d is outside the diamond" % [x, y])
			assert_array(problems).override_failure_message("%s_%s" % [id, variant]).is_empty()


## A mix of a and b in a 3 x 3 block, at the three camera zooms: not one pixel inside the block's
## diamond is clear or half clear, so there is no hairline where two tiles meet (the base reaches
## 1 px past the diamond's edge, so the antialiased edges overlap).
func test_a_block_of_mixed_a_and_b_tiles_has_no_seam_at_the_three_camera_zooms() -> void:
	for id: StringName in Support.TERRAIN_IDS:
		for scale: float in ZOOMS:
			var tile: Vector2 = Vector2(Support.TILE) * scale
			var block: Image = Image.create_empty(
				int(tile.x * 3.0), int(tile.y * 3.0), false, Image.FORMAT_RGBA8
			)
			for row: int in 3:
				for column: int in 3:
					var image: Image = Support.raster(
						Support.ground_path(id, "ab"[(column + row) % 2]), scale
					)
					var at: Vector2i = Vector2i(
						(column - row + 2) * int(tile.x / 2.0), (column + row) * int(tile.y / 2.0)
					)
					block.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)
			var seams: int = 0
			for y: int in block.get_height():
				for x: int in block.get_width():
					if (
						Support.metric(x, y, block.get_size()) <= 0.94
						and block.get_pixel(x, y).a < 0.99
					):
						seams += 1
			assert_int(seams).override_failure_message("%s at %s" % [id, scale]).is_equal(0)


## No rim (Michael, 2026-10-27): the base colour runs unbroken to every edge, so two equal tiles
## show no line between them. Where the soft rim's two bands were (0.89 and 0.97 of the way to the
## edge, and the 0.93 between them) every pixel is the base colour, in a and in b, and the file
## has no `evenodd` band path.
func test_the_diamonds_have_no_rim_the_base_colour_runs_to_every_edge_in_a_and_in_b() -> void:
	for id: StringName in Support.TERRAIN_IDS:
		var base: Color = Color(BASE[id])
		for variant: String in ["a", "b"]:
			var path: String = Support.ground_path(id, variant)
			assert_str(Support.text(path)).override_failure_message(path).not_contains("evenodd")
			var image: Image = Support.raster(path, 1.0)
			for corner: int in 4:
				for band: float in [0.89, 0.93, 0.97]:
					var at: Vector2i = Support.edge_pixel(corner, band, Support.TILE)
					var got: Color = image.get_pixel(at.x, at.y)
					var off: float = (
						absf(got.r8 - base.r8) + absf(got.g8 - base.g8) + absf(got.b8 - base.b8)
					)
					(
						assert_float(off)
						. override_failure_message(
							"%s_%s edge %d at %s: %s" % [id, variant, corner, band, got]
						)
						. is_less_equal(3.0)
					)


func test_a_and_b_differ_inside_and_agree_on_everything_near_the_edge() -> void:
	for id: StringName in Support.TERRAIN_IDS:
		var a: Image = Support.raster(Support.ground_path(id, "a"), 1.0)
		var b: Image = Support.raster(Support.ground_path(id, "b"), 1.0)
		var inside: int = 0
		var near_edge: int = 0
		for y: int in Support.TILE.y:
			for x: int in Support.TILE.x:
				var m: float = Support.metric(x, y, Support.TILE)
				if a.get_pixel(x, y) == b.get_pixel(x, y):
					continue
				if m < 0.84:
					inside += 1
				elif m >= 0.9:
					near_edge += 1
		assert_int(inside).override_failure_message(String(id) + " is the same inside").is_greater(
			60
		)
		(
			assert_int(near_edge)
			. override_failure_message(String(id) + " differs at the edge")
			. is_equal(0)
		)


func test_the_means_at_32_px_in_greyscale_are_those_of_the_style_guide_and_the_terrains_differ(
) -> void:
	var means: Dictionary[String, float] = Support.grey_means()
	for key: String in GREY:
		assert_float(means[key]).override_failure_message(key).is_equal_approx(
			float(GREY[key]), 1.0
		)
	# The a and b of one terrain share a level, so one terrain is one level; every pair of terrains
	# is told apart by at least GAP grey levels (their texture is the second cue).
	var levels: Array[float] = []
	for id: StringName in Support.TERRAIN_IDS:
		levels.append((means["%s_a" % id] + means["%s_b" % id]) / 2.0)
	levels.sort()
	for index: int in range(1, levels.size()):
		(
			assert_float(levels[index] - levels[index - 1])
			. override_failure_message(str(levels))
			. is_greater_equal(Support.GAP)
		)


## The clear colour outside the map's diamond: darker than every ground by a wide margin, not the
## fog's black (so the map's edge shows against unexplored ground) and not a saturated colour.
func test_the_off_map_colour_is_a_dark_neutral_that_is_not_the_fogs_black() -> void:
	var color: Color = TerrainPage.OFF_MAP_COLOR
	assert_str(color.to_html(false).to_upper()).is_equal("16191D")
	var level: float = Support.luminance(color)
	assert_float(level).is_between(15.0, 35.0)
	assert_float(color.s).is_less(0.3)
	var means: Dictionary[String, float] = Support.grey_means()
	for id: StringName in Support.TERRAIN_IDS:
		assert_float(means["%s_a" % id] - level).override_failure_message(String(id)).is_greater(
			40.0
		)


func test_no_art_file_of_the_row_names_a_key_colour_of_either_faction() -> void:
	var keys: Array[String] = []
	for triad: Array in ArtPalette.KEYS.values():
		keys.append_array(triad)
	var files: Array[String] = Support.FileScan.list_files("res://assets/art/svg/ground", ".svg")
	files.append_array(Support.FileScan.list_files("res://assets/art/svg/fields", ".svg"))
	files.append_array(Support.FileScan.list_files("res://assets/art/svg/decals", ".svg"))
	assert_int(files.size()).is_equal(12 + 8 + 1)
	for path: String in files:
		for key: String in keys:
			(
				assert_str(Support.text(path).to_upper())
				. override_failure_message(path + key)
				. not_contains(key)
			)
