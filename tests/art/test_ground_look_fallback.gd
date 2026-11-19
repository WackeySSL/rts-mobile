extends GdUnitTestSuite
## The rule of a ground look (STYLE.md "Map looks", plan row P551): a terrain takes the look's
## diamonds only when the look has both its a and its b; a look with one of the two is no look for
## that terrain, so no cell is left empty. The fixture look `halfway` (`tests/art/fixtures/
## ground_looks/`) holds only `water_a`, a copy of the standard water diamond.

const Rig: GDScript = preload("res://tests/view/support/ground_rig.gd")
const ROOT: String = "res://tests/art/fixtures/ground_looks"
const LOOK: StringName = &"halfway"


func test_a_look_with_only_one_variant_of_a_terrain_is_no_look_for_it() -> void:
	assert_bool(ResourceLoader.exists("%s/halfway/water_a.svg" % ROOT)).is_true()
	assert_bool(ResourceLoader.exists("%s/halfway/water_b.svg" % ROOT)).is_false()
	assert_bool(GroundAtlas.has_look(&"water", LOOK, ROOT)).is_false()
	for variant: String in ["a", "b"]:
		assert_str(GroundAtlas.path_of(&"water", variant, LOOK, ROOT)).is_equal(
			GroundAtlas.GROUND_PATH % [&"water", variant]
		)


func test_the_atlas_falls_back_to_the_standard_pair_and_keeps_every_tile() -> void:
	var ids: Array[StringName] = [&"grass", &"water"]
	var plain: GroundAtlas = GroundAtlas.build(ids)
	var half: GroundAtlas = GroundAtlas.build(ids, LOOK, ROOT)
	for key: StringName in [&"water_a", &"water_b", &"grass_a", &"grass_b"]:
		assert_that(half.coords(key)).override_failure_message(String(key)).is_not_equal(
			Vector2i(-1, -1)
		)
		(
			assert_bool(
				(
					half.image().get_region(half.region(key)).get_data()
					== plain.image().get_region(plain.region(key)).get_data()
				)
			)
			. override_failure_message(String(key))
			. is_true()
		)


func test_the_ground_layer_with_such_a_look_still_covers_the_map() -> void:
	var scenario: ScenarioDef = Rig.scenario()
	scenario.map.ground_look = LOOK
	var runner: MatchRunner = auto_free(Rig.runner(scenario))
	var ground: GroundLayer = auto_free(GroundLayer.new())
	ground.runner = runner
	ground.look_root = ROOT
	add_child(ground)
	for _i: int in 2:
		await await_idle_frame()
	assert_bool(ground.covers_map()).is_true()
	assert_int(ground.get_used_cells().size()).is_equal(Rig.COLS * Rig.ROW_COUNT)
	var atlas: GroundAtlas = ground.atlas()
	assert_that(atlas.coords(&"water_b")).is_not_equal(Vector2i(-1, -1))
	assert_that(Rig.key_at(ground, atlas, 4, 0)).is_equal(&"water_a")  # Row 0, column 4: water.
