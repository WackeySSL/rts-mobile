extends GdUnitTestSuite
## The oil and gas fields of plan row P105 (ADR 0023 sections 6 and 11, STYLE.md "Fields"): the six
## stages, the neutral wellhead and its shadow, and the crater decal. The stages are overlays on
## the ore ground that run together when full; they are told apart from the six terrains and from
## each other at 32 px in greyscale (oil is dark, gas bright). The wellhead stands on its anchor,
## carries no team colour and has one cast shadow; the crater is a 2:1 ground circle.

const Support: GDScript = preload("res://tests/art/ground_art_support.gd")
## Rec. 601 luminance of a stage over `ore_a` at 32 px, as STYLE.md ("Fields") lists them.
const FIELD_GREY: Dictionary[String, int] = {
	"oil_full": 30,
	"oil_half": 44,
	"oil_dry": 57,
	"gas_full": 213,
	"gas_half": 166,
	"gas_dry": 143,
}
const WELLHEAD: Vector2i = Vector2i(112, 116)  ## Canvas at 2x.
const WELLHEAD_ANCHOR: Vector2i = Vector2i(56, 88)  ## The middle of the pad on the ground.
const SHADOW: Vector2i = Vector2i(140, 72)
const SHADOW_ANCHOR: Vector2i = Vector2i(56, 31)
const CRATER: Vector2i = Vector2i(288, 144)
const CRATER_ANCHOR: Vector2i = Vector2i(144, 72)  ## The middle of the pit; radius 1.5 tiles.
const GRASS: Color = Color("6F8F57")
const SAND: Color = Color("CDB98F")


func test_the_six_stages_the_wellhead_with_its_shadow_and_the_crater_are_where_style_md_says(
) -> void:
	var files: Array[String] = Support.FileScan.list_files(Support.FIELDS_DIR, ".svg")
	assert_array(files).has_size(8)
	assert_array(Support.FileScan.list_files(Support.DECALS_DIR, ".svg")).has_size(1)
	var sizes: Dictionary[String, Vector2i] = {
		Support.FIELDS_DIR + "/wellhead.svg": WELLHEAD,
		Support.FIELDS_DIR + "/wellhead_shadow.svg": SHADOW,
		Support.DECALS_DIR + "/crater.svg": CRATER,
	}
	for kind: String in Support.KINDS:
		for stage: String in Support.STAGES:
			sizes[Support.field_path(kind, stage)] = Support.TILE
	assert_int(sizes.size()).is_equal(files.size() + 1)
	for path: String in sizes:
		var size: Vector2i = sizes[path]
		var head: String = Support.text(path).split("\n")[2]
		var canvas: String = (
			'width="%d" height="%d" viewBox="0 0 %d %d"' % [size.x, size.y, size.x, size.y]
		)
		assert_str(head).override_failure_message(path).contains(canvas)
		# Imported at scale 0.5: one tile is 64 x 32 px in game.
		var imported: Vector2 = (load(path) as Texture2D).get_size()
		assert_vector(imported).override_failure_message(path).is_equal(Vector2(size) / 2.0)


## A stage is an overlay on its cell: nothing in the canvas corners, nothing past the diamond but
## the 1 px the full stages reach so that two full cells have no seam.
func test_a_stage_stays_inside_its_cell_and_the_canvas_corners_are_clear() -> void:
	for kind: String in Support.KINDS:
		for stage: String in Support.STAGES:
			var path: String = Support.field_path(kind, stage)
			var image: Image = Support.raster(path, 1.0)
			var outside: int = 0
			for y: int in Support.TILE.y:
				for x: int in Support.TILE.x:
					if (
						Support.metric(x, y, Support.TILE) >= 1.12
						and image.get_pixel(x, y).a > 0.02
					):
						outside += 1
			assert_int(outside).override_failure_message(path).is_equal(0)


## Full cells run together into one lake or crust: the stage fills its diamond. A half and a dry
## cell stand apart: they stop short of the middle of all four sides.
func test_a_full_stage_fills_its_cell_and_a_half_or_dry_stage_stops_short_of_the_sides() -> void:
	for kind: String in Support.KINDS:
		for stage: String in Support.STAGES:
			var path: String = Support.field_path(kind, stage)
			var image: Image = Support.raster(path, 1.0)
			if stage == "full":
				var gaps: int = 0
				for y: int in Support.TILE.y:
					for x: int in Support.TILE.x:
						if (
							Support.metric(x, y, Support.TILE) <= 0.99
							and image.get_pixel(x, y).a < 0.99
						):
							gaps += 1
				assert_int(gaps).override_failure_message(path).is_equal(0)
				continue
			for corner: int in 4:
				var at: Vector2i = Support.edge_pixel(corner, 1.0, Support.TILE)
				(
					assert_float(image.get_pixel(at.x, at.y).a)
					. override_failure_message("%s edge %d" % [path, corner])
					. is_less(0.5)
				)


func test_the_stages_are_told_apart_from_the_terrains_and_from_each_other_at_32_px_in_greyscale(
) -> void:
	var means: Dictionary[String, float] = Support.grey_means()
	for key: String in FIELD_GREY:
		assert_float(means[key]).override_failure_message(key).is_equal_approx(
			float(FIELD_GREY[key]), 1.0
		)
	var problems: Array[String] = []
	for key: String in FIELD_GREY:
		for other: String in means:
			if other != key and absf(means[key] - means[other]) < Support.GAP:
				problems.append("%s %.1f and %s %.1f" % [key, means[key], other, means[other]])
	assert_array(problems).is_empty()
	# Oil is dark and gas bright, and each kind is ordered by its stage.
	assert_float(means["oil_full"]).is_less(means["oil_half"])
	assert_float(means["oil_half"]).is_less(means["oil_dry"])
	assert_float(means["gas_dry"]).is_less(means["gas_half"])
	assert_float(means["gas_half"]).is_less(means["gas_full"])
	for stage: String in Support.STAGES:
		assert_float(means["gas_" + stage] - means["oil_" + stage]).is_greater(80.0)


func test_the_wellhead_has_no_team_colour_and_stands_on_its_pad_at_the_anchor() -> void:
	var path: String = Support.FIELDS_DIR + "/wellhead.svg"
	var hex: RegEx = RegEx.create_from_string("#[0-9A-Fa-f]{6}")
	for found: RegExMatch in hex.search_all(Support.text(path)):
		(
			assert_float(Color(found.get_string()).s)
			. override_failure_message(found.get_string())
			. is_less(0.3)
		)
	var box: Rect2i = _bounds(Support.raster(path, 1.0), 0.5)
	# The pad is a 0.78 tile square: 100 px wide and 50 px of ground above the front corner.
	assert_int(box.end.y - WELLHEAD_ANCHOR.y).is_between(25, 27)
	assert_int(WELLHEAD_ANCHOR.x - box.position.x).is_between(50, 52)
	assert_int(box.end.x - WELLHEAD_ANCHOR.x).is_between(50, 52)
	# The valve tree is tall (about a tile) and the lamp does not touch the canvas.
	assert_int(WELLHEAD_ANCHOR.y - box.position.y).is_between(78, 86)
	assert_int(box.position.y).is_greater_equal(2)


func test_the_wellhead_shadow_is_one_group_at_35_percent_falling_to_the_south_east() -> void:
	var path: String = Support.FIELDS_DIR + "/wellhead_shadow.svg"
	assert_str(Support.text(path)).contains('<g opacity="0.35" fill="#000000">')
	var image: Image = Support.raster(path, 1.0)
	var box: Rect2i = _bounds(image, 0.2)
	var peak: float = 0.0
	for y: int in image.get_height():
		for x: int in image.get_width():
			peak = maxf(peak, image.get_pixel(x, y).a)
	assert_float(peak).is_equal_approx(0.35, 0.02)
	# Along +gx it reaches 0.8 x the height past the pad: the right end is 79 px from the anchor,
	# the pad's own 50 px and the lamp's 53 px further on the way.
	assert_int(box.end.x - SHADOW_ANCHOR.x).is_between(77, 81)
	assert_int(SHADOW_ANCHOR.x - box.position.x).is_between(48, 52)
	assert_int(SHADOW_ANCHOR.y - box.position.y).is_between(24, 27)
	assert_int(box.end.y - SHADOW_ANCHOR.y).is_between(38, 42)
	var body: Rect2i = _bounds(Support.raster(Support.FIELDS_DIR + "/wellhead.svg", 1.0), 0.5)
	assert_int(box.end.x - SHADOW_ANCHOR.x).is_greater(body.end.x - WELLHEAD_ANCHOR.x + 20)


func test_the_wellhead_reads_as_a_tall_object_at_32_px_in_greyscale_on_grass_and_sand() -> void:
	for ground: Color in [GRASS, SAND]:
		var picture: Image = Image.create_empty(48, 48, false, Image.FORMAT_RGBA8)
		picture.fill(ground)
		var at: Vector2i = Vector2i(24, 36)
		_blit(picture, Support.FIELDS_DIR + "/wellhead_shadow.svg", at - SHADOW_ANCHOR / 4)
		_blit(picture, Support.FIELDS_DIR + "/wellhead.svg", at - WELLHEAD_ANCHOR / 4)
		var base: float = Support.luminance(ground)
		var differing: int = 0
		var lums: Array[float] = []
		for y: int in picture.get_height():
			for x: int in picture.get_width():
				var level: float = Support.luminance(picture.get_pixel(x, y))
				if absf(level - base) > 25.0:
					differing += 1
					lums.append(level)
		# A body of its own, and tones of its own (the pad, the steel, the dark wheels and lamp).
		assert_int(differing).override_failure_message(str(ground)).is_greater_equal(150)
		lums.sort()
		var spread: float = lums[int(lums.size() * 0.95)] - lums[int(lums.size() * 0.05)]
		assert_float(spread).override_failure_message(str(ground)).is_greater_equal(50.0)


func test_the_crater_is_a_two_to_one_ground_circle_round_its_anchor_and_darker_than_both_grounds(
) -> void:
	var path: String = Support.DECALS_DIR + "/crater.svg"
	var image: Image = Support.raster(path, 1.0)
	var box: Rect2i = _bounds(image, 0.1)
	# A circle of radius 1.5 tiles: 271 px across and 136 px high at 2x, within the ragged edge.
	assert_int(box.size.x).is_between(250, 286)
	assert_float(float(box.size.x) / box.size.y).is_between(1.85, 2.15)
	assert_vector(Vector2(box.get_center())).is_equal_approx(Vector2(CRATER_ANCHOR), Vector2(5, 5))
	var pit: Color = image.get_pixel(CRATER_ANCHOR.x, CRATER_ANCHOR.y)
	assert_float(pit.a).is_greater(0.99)
	for ground: Color in [GRASS, SAND]:
		var shown: Color = ground.blend(pit)
		assert_float(Support.luminance(ground) - Support.luminance(shown)).is_greater(60.0)
	# The decal is flat: the corners of the canvas are clear.
	for corner: Vector2i in [
		Vector2i(0, 0), Vector2i(287, 0), Vector2i(0, 143), Vector2i(287, 143)
	]:
		assert_float(image.get_pixel(corner.x, corner.y).a).is_equal(0.0)


## The pixels of `image` whose alpha is above `min_alpha`, as a rectangle.
func _bounds(image: Image, min_alpha: float) -> Rect2i:
	var low: Vector2i = image.get_size()
	var high: Vector2i = Vector2i(-1, -1)
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a > min_alpha:
				low = Vector2i(mini(low.x, x), mini(low.y, y))
				high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	return Rect2i(low, high - low + Vector2i.ONE)


func _blit(picture: Image, path: String, at: Vector2i) -> void:
	var frame: Image = Support.raster(path, Support.GREY_SCALE)
	picture.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), at)
