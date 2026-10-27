extends GdUnitTestSuite
## The cast shadows of the generator (plan row P99b, ADR 0023 section 5, canvas Spec 02): every
## primitive is dropped onto the ground towards +gx (south-east on the screen), 0.8 x its height
## long, black at 35 % as one group. The light does not turn with a unit, a turret casts from its
## mount, and a shadow frame is a frame set of its own with one canvas and the hull's anchor.

const REACH: float = 0.8  ## Spec 02, written again here so that a change of ArtShadow.REACH fails.


func test_a_box_casts_the_hull_of_its_corners_dropped_0_8_tiles_per_tile_of_height_along_plus_gx(
) -> void:
	var polys: Array[ArtRender.Poly] = _shadow(["box hull steel 0 0 0 1 1 1"], 0.0)
	assert_int(polys.size()).is_equal(1)
	assert_int(polys[0].points.size()).is_equal(4)
	# Ground x from -0.5 (the base) to 1.3 (the top, 0.5 + 0.8), y from -0.5 to 0.5; on the screen
	# x is (gx - gy) x 64 and y is (gx + gy) x 32.
	var box: Rect2 = ArtRender.bounds(polys)
	assert_vector(box.position).is_equal_approx(Vector2(-64.0, -32.0), Vector2.ONE * 0.01)
	assert_vector(box.end).is_equal_approx(Vector2(115.2, 57.6), Vector2.ONE * 0.01)
	assert_str(polys[0].fill).is_equal("#000000")
	assert_str(polys[0].stroke).is_equal("")


func test_the_shadow_falls_the_same_way_whatever_the_yaw_of_what_casts_it() -> void:
	# A thin pole 1 tile high at the origin: its tip drops to (0.8, 0), whichever way it is turned.
	for yaw: float in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0]:
		var polys: Array[ArtRender.Poly] = _shadow(["box hull steel 0 0 0 0.02 0.02 1"], yaw)
		assert_int(polys.size()).is_equal(1)
		var tip: Vector2 = ArtRender.project(Vector3(REACH, 0.0, 0.0))
		(
			assert_float(ArtRender.bounds(polys).end.x)
			. override_failure_message(str(yaw))
			. is_equal_approx(tip.x + 1.3, 1.0)
		)


func test_a_taller_primitive_casts_a_longer_shadow_in_proportion() -> void:
	var low: Rect2 = ArtRender.bounds(_shadow(["box hull steel 0 0 0 0.1 0.1 0.5"], 0.0))
	var high: Rect2 = ArtRender.bounds(_shadow(["box hull steel 0 0 0 0.1 0.1 1.0"], 0.0))
	# The reach past the box is REACH x its top, 64 x sqrt 2 px of screen x per tile along +gx.
	assert_float(high.size.x - low.size.x).is_equal_approx(0.5 * REACH * 64.0, 0.01)


func test_a_sphere_casts_an_ellipse_whose_long_axis_lies_along_plus_gx() -> void:
	var polys: Array[ArtRender.Poly] = _shadow(["sphere hull steel 0 0 0 1 1 1"], 0.0)
	assert_int(polys[0].points.size()).is_equal(ArtShadow.SPHERE_POINTS)
	var stretch: float = sqrt(1.0 + REACH * REACH)
	for point: Vector2 in polys[0].points:
		# Back to the ground: gx = (y / 32 + x / 64) / 2, gy = (y / 32 - x / 64) / 2.
		var gx: float = (point.y / 32.0 + point.x / 64.0) / 2.0
		var gy: float = (point.y / 32.0 - point.x / 64.0) / 2.0
		var on_ellipse: float = pow((gx - REACH * 0.5) / (0.5 * stretch), 2.0) + pow(gy / 0.5, 2.0)
		assert_float(on_ellipse).is_equal_approx(1.0, 1e-4)


func test_primitives_that_overlap_keep_a_polygon_each_and_one_group_makes_them_35_percent() -> void:
	var model: ArtModel = _model(
		[
			"box hull steel 0 0 0 1 1 1",
			"box hull steel 0.2 0 0 1 1 1",
			"box turret iron 0 0 0 0.4 0.4 0.4",
		]
	)
	model.mount = Vector3(0.1, 0.0, 1.0)
	var polys: Array[ArtRender.Poly] = ArtShadow.polys(model.shadow_prims(), 0.0)
	assert_int(polys.size()).is_equal(3)
	var text: String = ArtGen.build(model)["res://assets/art/iso/fossil/veh/x_shadow_d06.svg"]
	assert_str(text).contains('<g opacity="0.35">')
	assert_str(ArtShadow.OPACITY).is_equal("0.35")
	assert_int(text.count("<polygon ")).is_equal(3)
	assert_int(text.count('fill="#000000"/>')).is_equal(3)
	assert_bool(text.contains("stroke")).is_false()
	assert_bool(text.contains("fill-opacity")).is_false()


func test_a_turret_casts_from_its_mount_turned_with_the_hull() -> void:
	var model: ArtModel = _model(
		["box hull steel 0 0 0 1 1 0.2", "box turret iron 0 0 0 0.2 0.2 0.2"]
	)
	model.mount = Vector3(0.3, 0.0, 0.2)
	var found: Array[ArtPrim] = model.shadow_prims()
	assert_int(found.size()).is_equal(2)
	assert_vector(found[1].centre).is_equal(Vector2(0.3, 0.0))
	assert_float(found[1].z0).is_equal_approx(0.2, 1e-6)
	# The source primitive is not changed: a second call gives the same answer.
	assert_float(model.shadow_prims()[1].z0).is_equal_approx(0.2, 1e-6)
	assert_float(model.primitives(&"turret")[0].z0).is_equal(0.0)


func test_a_line_of_points_has_no_shadow_and_collinear_corners_are_dropped() -> void:
	var flat: Array[Vector2] = [Vector2(0, 0), Vector2(1, 1), Vector2(2, 2), Vector2(0, 0)]
	assert_int(ArtShadow._hull(flat).size()).is_less(3)
	var square: Array[Vector2] = [
		Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(2, 2), Vector2(0, 2), Vector2(1, 1)
	]
	assert_int(ArtShadow._hull(square).size()).is_equal(4)


func test_every_unit_shadow_reaches_further_to_the_right_than_to_the_left_of_its_ground_point(
) -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var layout: ArtGen.Layout = ArtGen.layouts(model)[ArtModel.SHADOW]
		if model.category != &"bld":
			assert_int(layout.size.x - layout.anchor.x).override_failure_message(path).is_greater(
				layout.anchor.x
			)


func test_a_shadow_has_a_frame_for_each_hull_frame_and_never_a_turn_of_its_own() -> void:
	var model: ArtModel = _model(
		["box hull steel 0 0 0 1 1 1", "box turret iron 0 0 0 0.4 0.4 0.4"]
	)
	model.mount = Vector3(0.1, 0.0, 1.0)
	assert_array(model.directions(ArtModel.SHADOW)).is_equal(model.directions(&"hull"))
	assert_array(model.frame_parts()).is_equal([&"hull", &"turret", &"shadow"])
	model.category = &"inf"
	assert_array(model.directions(ArtModel.SHADOW)).is_equal([0, 2, 4, 6, 8, 10, 12, 14])
	assert_array(model.parts()).is_equal([&"hull", &"turret"])


## The guide says what the generator does: the direction, the reach and the opacity of the code.
func test_the_style_guide_states_the_direction_the_reach_and_the_opacity() -> void:
	var guide: String = FileAccess.get_file_as_string("res://assets/art/STYLE.md")
	guide = RegEx.create_from_string("\\s+").sub(guide, " ", true)
	for words: String in [
		"towards **+gx, the south-east of the screen**",
		"`%s x its height` tiles" % ArtShadow.REACH,
		'<g opacity="%s">' % ArtShadow.OPACITY,
		"**35 % as one group**",
	]:
		assert_bool(guide.contains(words)).override_failure_message(words).is_true()


func _shadow(lines: Array[String], yaw: float) -> Array[ArtRender.Poly]:
	var prims: Array[ArtPrim] = []
	for line: String in lines:
		prims.append(ArtPrim.parse(line))
	return ArtShadow.polys(prims, yaw)


func _model(lines: Array[String]) -> ArtModel:
	var model: ArtModel = ArtModel.new()
	model.art_id = &"x"
	model.faction = &"fossil"
	model.category = &"veh"
	model.prims = PackedStringArray(lines)
	return model
