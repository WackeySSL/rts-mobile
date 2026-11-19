extends GdUnitTestSuite
## The ground look of Heron Fords (plan row P551, STYLE.md "Map looks"): water, sand and grass
## diamonds in `assets/art/svg/ground_looks/heron/`.
## The checks every look shares are in ground_look_support.gd.

const Support: GDScript = preload("res://tests/art/ground_art_support.gd")
const Look: GDScript = preload("res://tests/art/ground_look_support.gd")
const Rig: GDScript = preload("res://tests/view/support/ground_rig.gd")
const LOOK: StringName = &"heron"
const MAP: String = "res://data/maps/heron_fords.tres"
const IDS: Array[StringName] = [&"grass", &"sand", &"water"]


func test_the_look_has_the_terrains_it_changes_and_no_other_file() -> void:
	assert_array(Look.file_problems(LOOK, IDS)).is_empty()


func test_a_diamond_fills_its_cell_to_every_edge_and_leaves_the_canvas_corners_clear() -> void:
	assert_array(Look.diamond_problems(LOOK, IDS)).is_empty()


func test_the_diamonds_have_no_rim_the_base_colour_runs_to_every_edge() -> void:
	assert_array(Look.rim_problems(LOOK, IDS)).is_empty()


func test_a_block_of_mixed_a_and_b_tiles_has_no_seam_at_the_three_camera_zooms() -> void:
	assert_array(Look.seam_problems(LOOK, IDS)).is_empty()


func test_each_tile_keeps_the_greyscale_level_of_the_terrain_it_replaces() -> void:
	assert_array(Look.grey_problems(LOOK, IDS)).is_empty()


func test_a_and_b_differ_inside_each_tile() -> void:
	assert_array(Look.variant_problems(LOOK, IDS)).is_empty()


func test_the_atlas_draws_the_look_in_the_same_keys_and_on_a_page_of_the_same_size() -> void:
	assert_array(Look.atlas_problems(LOOK, IDS)).is_empty()
	assert_bool(GroundAtlas.has_look(&"water", &"nowhere")).is_false()


func test_the_ground_layer_builds_its_page_for_the_maps_look_and_keeps_it() -> void:
	var scenario: ScenarioDef = Rig.scenario()
	var runner: MatchRunner = auto_free(Rig.runner(scenario))
	var ground: GroundLayer = auto_free(GroundLayer.new())
	ground.runner = runner
	add_child(ground)
	var plain: GroundAtlas = ground.atlas()
	scenario.map.ground_look = LOOK
	runner.start()
	for _i: int in 2:
		await await_idle_frame()
	var styled: GroundAtlas = ground.atlas()
	assert_object(styled).is_not_same(plain)
	var key: StringName = StringName("%s_a" % IDS[0])
	(
		assert_bool(
			(
				styled.image().get_region(styled.region(key)).get_data()
				== (load(Look.path(LOOK, IDS[0], "a")) as Texture2D).get_image().get_data()
			)
		)
		. is_true()
	)
	assert_bool(ground.covers_map()).is_true()
	runner.start()  # The same look again: the page stays.
	for _i: int in 2:
		await await_idle_frame()
	assert_object(ground.atlas()).is_same(styled)


func test_heron_fords_names_its_look_and_the_other_maps_name_none() -> void:
	assert_str(String((load(MAP) as MapDef).ground_look)).is_equal("heron")
	(
		assert_str(String((load("res://data/maps/kestrel_flats.tres") as MapDef).ground_look))
		. is_empty()
	)


## The river's current: a and b leave the tile at the same two points, in the stroke colour, so the
## lines run on from tile to tile whichever of the two the neighbour is.
func test_the_current_lines_of_the_water_meet_at_the_same_points_in_a_and_in_b() -> void:
	for variant: String in ["a", "b"]:
		var image: Image = Support.raster(Look.path(LOOK, &"water", variant), 1.0)
		for gy: float in [-0.24, 0.2]:
			for gx: float in [-0.47, 0.47]:
				var x: int = int(64.0 + (gx - gy) * 64.0)
				var y: int = int(32.0 + (gx + gy) * 32.0)
				(
					assert_str(image.get_pixel(x, y).to_html(false))
					. override_failure_message("%s at %s,%s" % [variant, gx, gy])
					. is_equal("3c7396")
				)
