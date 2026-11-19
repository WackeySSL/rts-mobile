extends GdUnitTestSuite
## The ground look of Heron Fords (plan row P551, STYLE.md "Map looks"): water, sand and grass
## diamonds in `assets/art/svg/ground_looks/heron/` that stand in for the standard `a` and `b` of
## those three terrains on that map, and nothing else: no new terrain, the same page. The standard
## diamonds' own rules (STYLE.md "Iso ground tiles") hold for them: 128 x 64, the base colour to
## every edge with no rim, no seam, nothing outside the diamond, and the greyscale level of the
## terrain they replace.

const Support: GDScript = preload("res://tests/art/ground_art_support.gd")
const Rig: GDScript = preload("res://tests/view/support/ground_rig.gd")
const LOOK: StringName = &"heron"
const FOLDER: String = "res://assets/art/svg/ground_looks/heron"
const MAP: String = "res://data/maps/heron_fords.tres"
const IDS: Array[StringName] = [&"grass", &"sand", &"water"]
const BASE: Dictionary[StringName, String] = {
	&"grass": "#6F8F57", &"sand": "#CDB98F", &"water": "#2A5978"
}
const ZOOMS: Array[float] = [0.375, 0.5, 0.75]
const MOST_BYTES: int = 4096  ## STYLE.md: 2 to 4 KB a file.
## The two points where the current lines of the water leave a tile, in ground tiles (gx, gy) from
## its middle: the lines run along +gx at these gy, so they meet the next tile's.
const CURRENT_GY: Array[float] = [-0.24, 0.2]
const CURRENT_STROKE: String = "3c7396"


static func look_path(id: StringName, variant: String) -> String:
	return "%s/%s_%s.svg" % [FOLDER, id, variant]


func test_the_look_has_the_three_terrains_it_changes_and_no_other_file() -> void:
	var files: Array[String] = Support.FileScan.list_files(FOLDER, ".svg")
	assert_array(files).has_size(6)
	for id: StringName in IDS:
		for variant: String in ["a", "b"]:
			var path: String = look_path(id, variant)
			assert_array(files).contains([path])
			assert_int(Support.text(path).length()).override_failure_message(path).is_less(
				MOST_BYTES
			)
			var lines: PackedStringArray = Support.text(path).split("\n")
			assert_str(lines[0]).starts_with("<!--")
			assert_str(lines[1]).starts_with("<!-- Pattern: ")
			assert_str(lines[2]).contains('width="128" height="64" viewBox="0 0 128 64"')
			var size: Vector2 = (load(path) as Texture2D).get_size()
			assert_vector(size).override_failure_message(path).is_equal(Vector2(64, 32))
	for node: String in ["<text", "<image", "<filter", "Gradient", "evenodd", "href"]:
		for path: String in files:
			assert_str(Support.text(path)).override_failure_message(path).not_contains(node)


func test_a_diamond_fills_its_cell_to_every_edge_and_leaves_the_canvas_corners_clear() -> void:
	for id: StringName in IDS:
		for variant: String in ["a", "b"]:
			var image: Image = Support.raster(look_path(id, variant), 1.0)
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


## The rim rule of the standard tiles: the base colour at 0.89, 0.93 and 0.97 of the way to the
## middle of each edge.
func test_the_diamonds_have_no_rim_the_base_colour_runs_to_every_edge() -> void:
	for id: StringName in IDS:
		var base: Color = Color(BASE[id])
		for variant: String in ["a", "b"]:
			var image: Image = Support.raster(look_path(id, variant), 1.0)
			for corner: int in 4:
				for band: float in [0.89, 0.93, 0.97]:
					var at: Vector2i = Support.edge_pixel(corner, band, Support.TILE)
					var got: Color = image.get_pixel(at.x, at.y)
					var off: float = (
						absf(got.r8 - base.r8) + absf(got.g8 - base.g8) + absf(got.b8 - base.b8)
					)
					(
						assert_float(off)
						. override_failure_message("%s_%s %d %s" % [id, variant, corner, band])
						. is_less_equal(3.0)
					)


func test_a_block_of_mixed_a_and_b_tiles_has_no_seam_at_the_three_camera_zooms() -> void:
	for id: StringName in IDS:
		for scale: float in ZOOMS:
			var tile: Vector2 = Vector2(Support.TILE) * scale
			var block: Image = Image.create_empty(
				int(tile.x * 3.0), int(tile.y * 3.0), false, Image.FORMAT_RGBA8
			)
			for row: int in 3:
				for column: int in 3:
					var image: Image = Support.raster(
						look_path(id, "ab"[(column + row) % 2]), scale
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


## The look must not move a terrain's level, so the minimap and the greyscale reading of the map
## stay those of the standard tiles: each tile's mean at 32 px is within 2 levels of the standard
## one, and a and b share a level.
func test_each_tile_keeps_the_greyscale_level_of_the_terrain_it_replaces() -> void:
	var means: Dictionary[String, float] = Support.grey_means()
	for id: StringName in IDS:
		var level: float = 0.0
		for variant: String in ["a", "b"]:
			var own: float = Support.mean_grey(
				Support.raster(look_path(id, variant), Support.GREY_SCALE)
			)
			assert_float(own).override_failure_message("%s_%s" % [id, variant]).is_equal_approx(
				means["%s_%s" % [id, variant]], 2.0
			)
			level += own / 2.0
		assert_float(level).is_equal_approx(means["%s_a" % id], 2.0)


## The river's current: a and b leave the tile at the same two points, in the stroke colour, so the
## lines run on from tile to tile whichever of the two the neighbour is.
func test_the_current_lines_of_the_water_meet_at_the_same_points_in_a_and_in_b() -> void:
	for variant: String in ["a", "b"]:
		var image: Image = Support.raster(look_path(&"water", variant), 1.0)
		for gy: float in CURRENT_GY:
			for gx: float in [-0.47, 0.47]:
				var x: int = int(64.0 + (gx - gy) * 64.0)
				var y: int = int(32.0 + (gx + gy) * 32.0)
				var got: Color = image.get_pixel(x, y)
				(
					assert_str(got.to_html(false))
					. override_failure_message("%s at %s,%s" % [variant, gx, gy])
					. is_equal(CURRENT_STROKE)
				)


func test_a_and_b_differ_inside_each_tile() -> void:
	for id: StringName in IDS:
		var a: Image = Support.raster(look_path(id, "a"), 1.0)
		var b: Image = Support.raster(look_path(id, "b"), 1.0)
		var inside: int = 0
		for y: int in Support.TILE.y:
			for x: int in Support.TILE.x:
				if (
					Support.metric(x, y, Support.TILE) < 0.84
					and a.get_pixel(x, y) != b.get_pixel(x, y)
				):
					inside += 1
		assert_int(inside).override_failure_message(String(id)).is_greater(60)


func test_heron_fords_names_its_look_and_the_other_maps_name_none() -> void:
	assert_str(String((load(MAP) as MapDef).ground_look)).is_equal("heron")
	for path: String in ["res://data/maps/kestrel_flats.tres", "res://data/maps/curlew_crags.tres"]:
		(
			assert_str(String((load(path) as MapDef).ground_look))
			. override_failure_message(path)
			. is_empty()
		)


func test_the_atlas_draws_the_look_in_the_same_keys_and_on_a_page_of_the_same_size() -> void:
	var ids: Array[StringName] = [&"grass", &"sand", &"scrub", &"rock", &"water", &"ore"]
	var plain: GroundAtlas = GroundAtlas.build(ids)
	var heron: GroundAtlas = GroundAtlas.build(ids, LOOK)
	assert_that(heron.image().get_size()).is_equal(plain.image().get_size())
	for key: StringName in Rig.tile_keys():
		assert_that(heron.coords(key)).is_equal(plain.coords(key))
	for id: StringName in ids:
		for variant: String in ["a", "b"]:
			var key: StringName = StringName("%s_%s" % [id, variant])
			if IDS.has(id):
				var own: Image = (load(look_path(id, variant)) as Texture2D).get_image()
				(
					assert_bool(
						heron.image().get_region(heron.region(key)).get_data() == own.get_data()
					)
					. override_failure_message(String(key))
					. is_true()
				)
			else:
				(
					assert_bool(
						(
							heron.image().get_region(heron.region(key)).get_data()
							== plain.image().get_region(plain.region(key)).get_data()
						)
					)
					. override_failure_message(String(key))
					. is_true()
				)
	assert_bool(GroundAtlas.has_look(&"water", LOOK)).is_true()
	assert_bool(GroundAtlas.has_look(&"scrub", LOOK)).is_false()
	assert_bool(GroundAtlas.has_look(&"water", &"nowhere")).is_false()
	var unknown: GroundAtlas = GroundAtlas.build(ids, &"nowhere")
	# A look that does not exist is no look.
	assert_bool(unknown.image().get_data() == plain.image().get_data()).is_true()


func test_the_ground_layer_builds_its_page_for_the_maps_look_and_keeps_it() -> void:
	var scenario: ScenarioDef = Rig.scenario()
	var runner: MatchRunner = auto_free(Rig.runner(scenario))
	var ground: GroundLayer = auto_free(GroundLayer.new())
	ground.runner = runner
	add_child(ground)
	var plain: GroundAtlas = ground.atlas()
	assert_bool(ground.covers_map()).is_true()
	scenario.map.ground_look = LOOK
	runner.start()
	for _i: int in 2:
		await await_idle_frame()
	var heron: GroundAtlas = ground.atlas()
	assert_object(heron).is_not_same(plain)
	var key: StringName = &"water_a"
	(
		assert_bool(
			(
				heron.image().get_region(heron.region(key)).get_data()
				== (load(look_path(&"water", "a")) as Texture2D).get_image().get_data()
			)
		)
		. is_true()
	)
	assert_bool(ground.covers_map()).is_true()
	runner.start()  # The same look again: the page stays.
	for _i: int in 2:
		await await_idle_frame()
	assert_object(ground.atlas()).is_same(heron)
