extends GdUnitTestSuite
## The rules of the art generator (plan row P99, ADR 0023 sections 1 and 5, STYLE.md "Projection"
## and "Light"): the model line, the faces of each primitive, the projection, the three-tone light
## from the north-west, back faces, the face order, the palette, the writer and the file naming. The
## models, the frames and the key band are in test_artgen.gd.

const BOX: String = "box hull steel 0 0 0 1 1 1"


func test_a_model_line_has_nine_fields_and_options_that_belong_to_its_shape() -> void:
	var prim: ArtPrim = ArtPrim.parse(
		"prism turret olive 0.1 -0.2 0.3 0.5 0.4 0.2 sides=8 taper=0.5 axis=x"
	)
	assert_object(prim).is_not_null()
	assert_str(prim.shape).is_equal("prism")
	assert_str(prim.part).is_equal("turret")
	assert_str(prim.material).is_equal("olive")
	assert_vector(prim.centre).is_equal_approx(Vector2(0.1, -0.2), Vector2.ONE * 1e-6)
	assert_float(prim.z0).is_equal_approx(0.3, 1e-6)
	assert_vector(prim.size).is_equal_approx(Vector3(0.5, 0.4, 0.2), Vector3.ONE * 1e-6)
	assert_int(prim.sides).is_equal(8)
	assert_float(prim.taper).is_equal(0.5)
	assert_int(prim.axis).is_equal(0)
	assert_float(ArtPrim.parse("wedge hull steel 0 0 0 1 1 1").slope).is_equal(1.0)
	assert_int(ArtPrim.parse("prism hull steel 0 0 0 1 1 1").sides).is_equal(12)
	assert_int(ArtPrim.parse(BOX).sides).is_equal(4)


func test_a_line_that_is_not_a_primitive_is_refused() -> void:
	for line: String in [
		"",
		"box hull steel 0 0 0 1 1",
		"cone hull steel 0 0 0 1 1 1",
		"box wing steel 0 0 0 1 1 1",
		"box hull steel 0 0 x 1 1 1",
		"box hull steel 0 0 0 1 0 1",
		"box hull steel 0 0 0 1 1 1 sides=8",
		"box hull steel 0 0 0 1 1 1 axis=x",
		"prism hull steel 0 0 0 1 1 1 sides=2",
		"prism hull steel 0 0 0 1 1 1 axis=w",
		"prism hull steel 0 0 0 1 1 1 colour=red",
		"sphere hull steel 0 0 0 1 1 1 taper=0.5",
		"wedge hull steel 0 0 0 1 1 1 slope=2",
	]:
		assert_object(ArtPrim.parse(line)).override_failure_message(line).is_null()


func test_a_box_has_six_faces_that_face_outwards() -> void:
	var faces: Array[ArtMesh.Face] = ArtMesh.faces(ArtPrim.parse(BOX))
	assert_int(faces.size()).is_equal(6)
	var normals: Array[Vector3] = []
	for face: ArtMesh.Face in faces:
		normals.append(face.normal)
		assert_int(face.points.size()).is_equal(4)
		var middle: Vector3 = (face.points[0] + face.points[2]) / 2.0 - Vector3(0, 0, 0.5)
		assert_float(face.normal.dot(middle)).is_greater(0.0)
	for want: Vector3 in [
		Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD
	]:
		assert_bool(normals.any(func(n: Vector3) -> bool: return n.is_equal_approx(want))).is_true()


func test_a_prism_is_a_ring_of_sides_and_two_caps_and_a_wedge_loses_its_front() -> void:
	(
		assert_int(ArtMesh.faces(ArtPrim.parse("prism hull steel 0 0 0 1 1 1 sides=12")).size())
		. is_equal(14)
	)
	(
		assert_int(ArtMesh.faces(ArtPrim.parse("prism hull steel 0 0 0 1 1 1 sides=6")).size())
		. is_equal(8)
	)
	assert_int(ArtMesh.faces(ArtPrim.parse("sphere hull steel 0 0 0 1 1 1")).size()).is_equal(0)
	var wedge: Array[ArtMesh.Face] = ArtMesh.faces(ArtPrim.parse("wedge hull steel 0 0 0 1 1 1"))
	assert_int(wedge.size()).is_equal(5)
	# The top slopes down towards +x, so its normal leans that way and the +x face is gone.
	var slope: ArtMesh.Face = wedge[wedge.size() - 2]
	assert_float(slope.normal.x).is_greater(0.5)
	assert_float(slope.normal.z).is_greater(0.5)
	var axis_x: Array[ArtMesh.Face] = ArtMesh.faces(
		ArtPrim.parse("prism hull steel 0 0 0 2 1 1 axis=x")
	)
	var caps: Array[Vector3] = [axis_x[axis_x.size() - 2].normal, axis_x[axis_x.size() - 1].normal]
	assert_bool(caps.has(Vector3.RIGHT) and caps.has(Vector3.LEFT)).is_true()


func test_a_hexagon_is_longer_along_its_second_axis_and_the_box_knows_it() -> void:
	var hex: AABB = ArtPrim.parse("prism hull steel 0 0 0 1 1 1 sides=6").aabb()
	assert_float(hex.size.x).is_equal_approx(1.0, 1e-6)
	assert_float(hex.size.y).is_equal_approx(2.0 / sqrt(3.0), 1e-6)
	var round: AABB = ArtPrim.parse("prism hull steel 0 0 0 1 1 1 sides=12").aabb()
	assert_vector(round.size).is_equal_approx(Vector3.ONE, Vector3.ONE * 1e-6)
	var lying: AABB = ArtPrim.parse("prism hull steel 0 0 0 2 1 1 sides=6 axis=x").aabb()
	assert_float(lying.size.x).is_equal_approx(2.0, 1e-6)
	assert_float(lying.size.z).is_equal_approx(2.0 / sqrt(3.0), 1e-6)


func test_the_projection_is_the_dimetric_2_to_1_of_adr_0023_at_twice_the_size() -> void:
	# ADR 0023 section 1: screen = ((gx - gy) x 32, (gx + gy) x 16 - z); at 2x a tile is 128 x 64.
	assert_vector(ArtRender.project(Vector3(1, 0, 0))).is_equal(Vector2(64, 32))
	assert_vector(ArtRender.project(Vector3(0, 1, 0))).is_equal(Vector2(-64, 32))
	assert_vector(ArtRender.project(Vector3(1, 1, 0))).is_equal(Vector2(0, 64))
	assert_vector(ArtRender.project(Vector3(-0.5, -0.5, 0))).is_equal(Vector2(0, -32))
	# A cube of one tile is 39.2 px high at 1x (Spec 01 says 39).
	assert_float(-ArtRender.project(Vector3(0, 0, 1)).y / 2.0).is_equal_approx(39.19, 0.01)
	assert_float(ArtRender.Z_PX).is_equal_approx(ArtRender.TILE_PX * cos(deg_to_rad(30.0)), 1e-9)
	# The camera looks from +gx, +gy and 30 degrees up: a unit vector.
	assert_float(ArtRender.VIEW.length()).is_equal_approx(1.0, 1e-9)
	assert_float(ArtRender.VIEW.z).is_equal(0.5)


func test_the_light_is_top_100_left_82_and_right_62_percent() -> void:
	assert_int(ArtRender.level(Vector3(0, 0, 1))).is_equal(ArtPalette.TOP)
	assert_int(ArtRender.level(Vector3(0, 1, 0))).is_equal(ArtPalette.LEFT)
	assert_int(ArtRender.level(Vector3(1, 0, 0))).is_equal(ArtPalette.RIGHT)
	# A slope towards the south-east is a left-face tone; towards the north-west it is lit.
	assert_int(ArtRender.level(Vector3(1, 0, 1).normalized())).is_equal(ArtPalette.LEFT)
	assert_int(ArtRender.level(Vector3(-1, 0, 1).normalized())).is_equal(ArtPalette.TOP)
	assert_array(ArtPalette.SHADES).is_equal([1.0, 0.82, 0.62])
	# The light sits at a fixed place in the world: turned a sixteenth, a box face keeps its side.
	for yaw: float in [0.0, 22.5, 45.0, 67.5, 90.0, 135.0, 180.0, 270.0]:
		var polys: Array[ArtRender.Poly] = _render([BOX], yaw)
		var fills: Array[String] = []
		for poly: ArtRender.Poly in polys:
			fills.append(poly.fill)
		assert_bool(fills.has(ArtPalette.tone(&"fossil", &"steel", ArtPalette.TOP))).is_true()
		(
			assert_bool(polys.size() >= 2 and polys.size() <= 3)
			. override_failure_message("yaw %s" % yaw)
			. is_true()
		)


func test_a_box_shows_a_left_face_a_right_face_and_a_top_drawn_last() -> void:
	var polys: Array[ArtRender.Poly] = _render([BOX], 0.0)
	assert_int(polys.size()).is_equal(3)
	var left: String = ArtPalette.tone(&"fossil", &"steel", ArtPalette.LEFT)
	var right: String = ArtPalette.tone(&"fossil", &"steel", ArtPalette.RIGHT)
	var top: String = ArtPalette.tone(&"fossil", &"steel", ArtPalette.TOP)
	assert_array([polys[0].fill, polys[1].fill]).contains_exactly_in_any_order([left, right])
	assert_str(polys[2].fill).is_equal(top)
	# The top face is the diamond above the footprint: 128 px wide, 64 px high, a tile up.
	var diamond: Rect2 = ArtRender.bounds([polys[2]] as Array[ArtRender.Poly])
	assert_vector(diamond.size).is_equal_approx(Vector2(128, 64), Vector2.ONE * 1e-3)
	assert_float(diamond.get_center().y).is_equal_approx(-ArtRender.Z_PX, 1e-3)
	# The light edge is on the top, a dark edge on the sides.
	assert_str(polys[2].stroke).is_equal(ArtPalette.edge(&"fossil", &"steel", true))
	assert_str(polys[0].stroke).is_equal(ArtPalette.edge(&"fossil", &"steel", false))


func test_a_box_turned_45_degrees_shows_one_wide_face() -> void:
	var polys: Array[ArtRender.Poly] = _render([BOX], 45.0)
	assert_int(polys.size()).is_equal(2)
	assert_str(polys[0].fill).is_equal(ArtPalette.tone(&"fossil", &"steel", ArtPalette.LEFT))


func test_the_nearer_primitive_is_drawn_after_the_farther_one_whatever_the_yaw() -> void:
	var far: String = "box hull iron -1.5 -1.5 0 1 1 1"
	var near: String = "box hull olive 0 0 0 1 1 1"
	var iron: String = ArtPalette.tone(&"fossil", &"iron", ArtPalette.TOP)
	var olive: String = ArtPalette.tone(&"fossil", &"olive", ArtPalette.TOP)
	# Listed near first: the order comes from the camera, not from the list.
	assert_array(_top_order([near, far], 0.0)).is_equal([iron, olive])
	assert_array(_top_order([far, near], 0.0)).is_equal([iron, olive])
	# Half a turn later the camera sees the other one in front.
	assert_array(_top_order([near, far], 180.0)).is_equal([olive, iron])
	assert_array(_top_order([far, near], 180.0)).is_equal([olive, iron])
	# Something standing on a slab is drawn after the slab, and a tower behind it before it.
	var slab: String = "box hull concrete 0 0 0 3 3 0.1"
	var tower: String = "box hull iron -1 -1 0.1 0.5 0.5 2"
	var after: String = "box hull olive 1 1 0.1 0.5 0.5 0.5"
	var tones: Array[String] = _top_order([after, tower, slab], 0.0)
	assert_str(tones[0]).is_equal(ArtPalette.tone(&"fossil", &"concrete", ArtPalette.TOP))
	assert_str(tones[1]).is_equal(iron)
	assert_str(tones[2]).is_equal(olive)


func test_a_sphere_is_three_discs_the_lit_one_up_and_left() -> void:
	var polys: Array[ArtRender.Poly] = _render(["sphere hull steel 0 0 0.5 1 1 1"], 0.0)
	assert_int(polys.size()).is_equal(3)
	var dark: Rect2 = ArtRender.bounds([polys[0]] as Array[ArtRender.Poly])
	var lit: Rect2 = ArtRender.bounds([polys[2]] as Array[ArtRender.Poly])
	assert_float(dark.size.x).is_equal_approx(ArtRender.TILE_PX, 1.0)
	assert_float(lit.size.x).is_less(dark.size.x)
	assert_float(lit.get_center().x).is_less(dark.get_center().x)
	assert_float(lit.get_center().y).is_less(dark.get_center().y)
	assert_str(polys[2].fill).is_equal(ArtPalette.tone(&"fossil", &"steel", ArtPalette.TOP))


func test_a_material_is_its_mid_tone_and_the_team_is_the_key_triad() -> void:
	assert_str(ArtPalette.tone(&"fossil", &"steel", ArtPalette.LEFT)).is_equal("#6B7366")
	assert_str(ArtPalette.tone(&"fossil", &"steel", ArtPalette.TOP)).is_equal("#828C7C")
	assert_str(ArtPalette.tone(&"fossil", &"steel", ArtPalette.RIGHT)).is_equal("#51574D")
	assert_str(ArtPalette.tone(&"renew", &"ceramic", ArtPalette.TOP)).is_equal("#FFFFFF")
	for faction: StringName in ArtPalette.KEYS:
		for level: int in 3:
			assert_str(ArtPalette.tone(faction, ArtPalette.TEAM, level)).is_equal(
				ArtPalette.KEYS[faction][level]
			)
		assert_str(ArtPalette.edge(faction, ArtPalette.TEAM, true)).is_equal(
			ArtPalette.KEYS[faction][0]
		)
		assert_str(ArtPalette.edge(faction, ArtPalette.TEAM, false)).is_equal(
			ArtPalette.KEYS[faction][2]
		)
	assert_array(ArtPalette.KEYS[&"fossil"]).is_equal(["#FF9446", "#E8681F", "#B04B12"])
	assert_array(ArtPalette.KEYS[&"renew"]).is_equal(["#62D6EE", "#1FA6C8", "#137C99"])
	assert_bool(ArtPalette.has_material(&"fossil", &"ceramic")).is_false()
	assert_bool(ArtPalette.has_material(&"renew", &"team")).is_true()


func test_the_writer_gives_one_decimal_and_no_minus_zero_and_a_fixed_shape() -> void:
	var poly: ArtRender.Poly = ArtRender.Poly.new()
	poly.points = PackedVector2Array(
		[Vector2(-0.04, 1.26), Vector2(10.0, 3.14159), Vector2(-7.5, 0.0)]
	)
	poly.fill = "#112233"
	poly.stroke = "#445566"
	var text: String = ArtSvg.frame(
		"note", Vector2i(40, 20), Vector2i(10, 5), [poly] as Array[ArtRender.Poly]
	)
	var lines: PackedStringArray = text.split("\n")
	assert_str(lines[0]).is_equal("<!-- note -->")
	assert_str(lines[1]).is_equal(
		'<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20" viewBox="0 0 40 20">'
	)
	assert_str(lines[2]).is_equal('<g stroke-width="2" stroke-linejoin="round">')
	assert_str(lines[3]).is_equal(
		'<polygon points="10,6.3 20,8.1 2.5,5" fill="#112233" stroke="#445566"/>'
	)
	assert_str(text).ends_with("</g>\n</svg>\n")
	poly.stroke = ""
	(
		assert_str(
			ArtSvg.frame("n", Vector2i(2, 2), Vector2i.ZERO, [poly] as Array[ArtRender.Poly])
		)
		. contains('fill="#112233"/>')
	)


func test_a_direction_faces_the_grid_angle_k_minus_6_times_22_5() -> void:
	# ADR 0023 section 1: d06 faces +gx (south-east on screen), d10 +gy (south-west), d00 is up the
	# screen and d08 down it.
	assert_float(ArtGen.yaw(6)).is_equal(0.0)
	assert_float(ArtGen.yaw(10)).is_equal(90.0)
	assert_float(ArtGen.yaw(0)).is_equal(-135.0)
	assert_float(ArtGen.yaw(8)).is_equal(45.0)
	var forward: Vector3 = ArtRender.rotate(Vector3.RIGHT, ArtGen.yaw(8))
	assert_vector(ArtRender.project(forward)).is_equal_approx(Vector2(0, 45.25), Vector2.ONE * 0.01)
	var up_screen: Vector3 = ArtRender.rotate(Vector3.RIGHT, ArtGen.yaw(0))
	assert_vector(ArtRender.project(up_screen)).is_equal_approx(
		Vector2(0, -45.25), Vector2.ONE * 0.01
	)
	var model: ArtModel = ArtModel.new()
	model.art_id = &"x"
	model.faction = &"fossil"
	model.category = &"veh"
	assert_str(ArtGen.frame_path(model, &"hull", 6)).is_equal(
		"res://assets/art/iso/fossil/veh/x_hull_d06.svg"
	)
	assert_str(ArtGen.frame_path(model, &"turret", 15)).ends_with("/x_turret_d15.svg")
	assert_str(ArtGen.frame_path(model, &"hull", -1)).ends_with("/x_hull.svg")


func test_the_mount_turns_with_the_hull_and_a_model_without_a_hull_is_refused() -> void:
	var model: ArtModel = ArtModel.new()
	model.art_id = &"x"
	model.faction = &"renew"
	model.category = &"veh"
	model.prims = PackedStringArray(
		[BOX.replace("steel", "ceramic"), "box turret ceramic 0 0 1 1 1 1"]
	)
	assert_array(Array(model.problems())).contains(["x: a turret or head part needs a mount"])
	model.mount = Vector3(0.5, 0, 0.3)
	assert_array(Array(model.problems())).is_empty()
	assert_vector(ArtGen.mount_px(model, 6)).is_equal_approx(
		ArtRender.project(Vector3(0.5, 0, 0.3)), Vector2.ONE * 1e-6
	)
	assert_vector(ArtGen.mount_px(model, 10)).is_equal_approx(
		ArtRender.project(Vector3(0, 0.5, 0.3)), Vector2.ONE * 1e-6
	)
	model.prims = PackedStringArray(["box hull teal 0 0 0 1 1 1"])
	assert_int(model.problems().size()).is_equal(1)
	model.footprint = 2
	assert_int(model.problems().size()).is_equal(2)
	model.prims = PackedStringArray(["box turret ceramic 0 0 0 1 1 1"])
	assert_array(Array(model.problems())).contains(["x: no hull primitive"])


func test_a_synthetic_model_builds_48_frames_a_sheet_and_a_card_and_the_same_bytes_twice() -> void:
	var model: ArtModel = ArtModel.new()
	model.art_id = &"x"
	model.faction = &"renew"
	model.category = &"veh"
	model.mount = Vector3(0, 0, 1)
	model.prims = PackedStringArray(
		[BOX.replace("steel", "team"), "prism turret graphite 0 0 0 0.5 0.5 0.5"]
	)
	var files: Dictionary[String, String] = ArtGen.build(model)
	# 16 hull, 16 turret and 16 shadow frames with an import each, the sheet and the item card.
	assert_int(files.size()).is_equal(98)
	assert_bool(files.has("res://assets/art/iso/renew/veh/x_sheet.tres")).is_true()
	assert_bool(files.has("res://assets/art/iso/icons/item_x.svg")).is_true()
	assert_bool(files.has("res://assets/art/iso/renew/veh/x_shadow_d15.svg")).is_true()
	assert_str(files["res://assets/art/iso/renew/veh/x_hull_d00.svg.import"]).is_equal(
		ArtGen.IMPORT_TEXT
	)
	assert_str(ArtGen.IMPORT_TEXT).is_equal('[remap]\n\nimporter="keep"\n')
	assert_bool(ArtGen.build(model) == files).is_true()
	assert_str(files["res://assets/art/iso/renew/veh/x_hull_d06.svg"]).contains("#62D6EE")
	assert_str(files["res://assets/art/iso/renew/veh/x_hull_d06.svg"].split("\n")[0]).contains(
		ArtGen.MARKER
	)


func test_a_model_is_found_under_the_name_it_loads_with_in_an_export_too() -> void:
	assert_str(ArtGen.tres_name("heavy_tank.tres")).is_equal("heavy_tank.tres")
	assert_str(ArtGen.tres_name("heavy_tank.tres.remap")).is_equal("heavy_tank.tres")
	for other: String in ["heavy_tank.res", "heavy_tank.tres.uid", "notes.md", ""]:
		assert_str(ArtGen.tres_name(other)).is_equal("")


func _render(lines: Array[String], yaw: float) -> Array[ArtRender.Poly]:
	var prims: Array[ArtPrim] = []
	for line: String in lines:
		prims.append(ArtPrim.parse(line))
	return ArtRender.render(prims, yaw, &"fossil")


## The fill of the top face of each primitive, in the order they are drawn.
func _top_order(lines: Array[String], yaw: float) -> Array[String]:
	var tops: Array[String] = []
	for material: StringName in ArtPalette.MATERIALS[&"fossil"]:
		tops.append(ArtPalette.tone(&"fossil", material, ArtPalette.TOP))
	var found: Array[String] = []
	for poly: ArtRender.Poly in _render(lines, yaw):
		if tops.has(poly.fill):
			found.append(poly.fill)
	return found
