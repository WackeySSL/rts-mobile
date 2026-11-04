extends GdUnitTestSuite
## The frame axis of the art generator (plan row P134, ADR 0027 section 4): a primitive can carry a
## `group=`, a model lists poses (a pose part, a frame count and the moves of groups in each frame),
## and the generator draws every pose frame with today's projection, light and shadow rules into
## `<id>_<part>_d<NN>_f<K>.svg` (a building's `anim` part into `<id>_anim_f<K>.svg`). The sheet says
## `frames`, `stride_milli`, `anim_ms`, `emitters` and `marks`. Only the four squads have poses
## (P139, test_artgen_poses.gd); every other committed model is as it was before P134: that the
## bytes equal a fresh run is test_artgen.gd; that no other sheet gained a field is pinned here. The
## models used here are crafted in memory and nothing is written to the project.

const TOLERANCE: float = 1e-6
const POINT_TOLERANCE: Vector2 = Vector2.ONE * 0.06  ## Written with one decimal.
const HIP: String = "0 -0.07 0.25"  ## The pivot at the top of the left leg.

var _points: RegEx = RegEx.create_from_string('points="([^"]*)"')


func test_a_group_of_three_frames_makes_f0_f1_f2_in_every_direction_and_nothing_else() -> void:
	var model: ArtModel = _squad()
	var files: Dictionary[String, String] = ArtGen.build(model)
	# 8 hull, 24 walk (3 frames in 8 directions) and 8 shadow frames, each with its import, the
	# sheet and the item card.
	assert_int(files.size()).is_equal((8 + 24 + 8) * 2 + 2)
	for dir: int in range(0, 16, 2):
		assert_bool(files.has(_walk(dir, -1))).override_failure_message(_walk(dir, -1)).is_false()
		for frame: int in 3:
			var path: String = _walk(dir, frame)
			assert_bool(files.has(path)).override_failure_message(path).is_true()
			assert_str(files[path + ".import"]).is_equal(ArtGen.IMPORT_TEXT)
	assert_str(files[_walk(4, 2)].split("\n")[0]).is_equal(
		(
			"<!-- x walk d04 f2: %s from assets/art/models/fossil/x.tres, do not edit -->"
			% ArtGen.MARKER
		)
	)
	# The hull and the shadow keep their names: one frame has no `_f<K>`.
	assert_bool(files.has("res://assets/art/iso/fossil/inf/x_hull_d04.svg")).is_true()
	assert_bool(files.has("res://assets/art/iso/fossil/inf/x_shadow_d04.svg")).is_true()
	assert_bool(ArtGen.build(model) == files).is_true()


func test_a_frame_file_is_the_pose_frame_drawn_in_the_direction_of_its_name() -> void:
	var model: ArtModel = _squad()
	var files: Dictionary[String, String] = ArtGen.build(model)
	var layout: ArtGen.Layout = ArtGen.layouts(model)[&"walk"]
	var seen: Dictionary[String, bool] = {}
	for dir: int in range(0, 16, 2):
		for frame: int in 3:
			var polys: Array[ArtRender.Poly] = ArtRender.render(
				model.frame_prims(&"walk", frame),
				ArtGen.yaw(dir),
				model.faction,
				model.frame_rest(&"walk")
			)
			var comment: String = (
				"x walk d%02d f%d: %s from assets/art/models/fossil/x.tres, do not edit"
				% [dir, frame, ArtGen.MARKER]
			)
			var want: String = ArtSvg.frame(comment, layout.size, layout.origin, polys)
			(
				assert_str(files[_walk(dir, frame)])
				. override_failure_message(_walk(dir, frame))
				. is_equal(want)
			)
			seen[want] = true
	# Every direction and every frame is a picture of its own (the hips turn, the leg moves).
	assert_int(seen.size()).is_equal(24)


func test_frame_0_without_a_move_is_the_standing_figure_and_a_move_changes_only_its_group() -> void:
	var model: ArtModel = _squad()
	var standing: Array[ArtRender.Poly] = ArtRender.render(
		model.primitives(&"hull"), 0.0, model.faction
	)
	var frame_0: Array[ArtRender.Poly] = ArtRender.render(
		model.frame_prims(&"walk", 0), 0.0, model.faction
	)
	assert_array(_signatures(frame_0)).is_equal(_signatures(standing))
	var frame_1: Array[ArtRender.Poly] = ArtRender.render(
		model.frame_prims(&"walk", 1), 0.0, model.faction
	)
	assert_array(_signatures(frame_1)).is_not_equal(_signatures(standing))
	# The torso (no group) and the right leg (no move in frame 2) are the very objects at rest.
	var prims: Array[ArtPrim] = model.primitives(&"hull")
	var in_2: Array[ArtPrim] = model.frame_prims(&"walk", 2)
	assert_int(in_2[0].moves.size()).is_equal(0)
	assert_int(in_2[1].moves.size()).is_equal(1)
	assert_int(in_2[2].moves.size()).is_equal(0)
	assert_vector(in_2[0].size).is_equal(prims[0].size)


## A pose frame of a squad is drawn in the order of the standing primitives and its top faces are
## the standing ones (`rest` of `ArtRender.render`, `ArtModel.frame_rest`): a leg turned 36 degrees
## and lifted rises into the box of the torso above it, where the posed boxes alone leave the order
## to the centre depth (the torso is thin here, so the leg's boxes overlap it all through and the
## fallback draws the leg over it at some yaws), and its front face then faces 0.59 up, which is not
## a roof and gets no light edge. A part without a rest (an `anim` element, which turns all round)
## is judged as posed.
func test_a_posed_leg_keeps_the_draw_order_and_the_light_edge_of_the_standing_figure() -> void:
	var torso: ArtPrim = ArtPrim.parse("box hull olive 0 0 0.25 0.2 0.3 0.05")
	var leg: ArtPrim = ArtPrim.parse("box hull iron 0 -0.07 0 0.1 0.08 0.25 group=leg")
	var by: Array[ArtMove] = [
		ArtMove.parse("walk 0 leg turn y -36 0 -0.07 0.25"),
		ArtMove.parse("walk 0 leg shift 0 0 0.035")
	]
	var standing: Array[ArtPrim] = [torso, leg]
	var posed: Array[ArtPrim] = [torso, leg.moved(by)]
	var light: String = ArtPalette.edge(&"fossil", &"iron", true)
	var late: int = 0  # The yaws at which the posed order alone draws the leg over the torso.
	for yaw: float in [0.0, 45.0, 67.5, 90.0, 112.5, 135.0, 180.0, -45.0, -90.0, -135.0]:
		var polys: Array[ArtRender.Poly] = ArtRender.render(posed, yaw, &"fossil", standing)
		var edges: int = 0
		for poly: ArtRender.Poly in polys:
			edges += int(poly.prim == 1 and poly.stroke == light)
		(
			assert_bool(_leg_comes_first(polys))
			. override_failure_message("yaw %s: the leg is drawn after the torso" % yaw)
			. is_true()
		)
		late += int(not _leg_comes_first(ArtRender.render(posed, yaw, &"fossil")))
		# The one top face of the leg has the light edge when it is seen (tilted back, it is not
		# at every yaw), and no side face has.
		assert_int(edges).override_failure_message("yaw %s" % yaw).is_less_equal(1)
		if yaw == 0.0:
			assert_int(edges).is_equal(1)
	# Control: without the standing primitives the order goes wrong at some yaws.
	assert_int(late).is_greater(0)
	# As posed (no rest) the tilted front face is taken for a roof: a second light edge.
	var as_posed: Array[ArtRender.Poly] = ArtRender.render(posed, 0.0, &"fossil")
	var tilted: int = 0
	for poly: ArtRender.Poly in as_posed:
		tilted += int(poly.prim == 1 and poly.stroke == light)
	assert_int(tilted).is_greater(1)


func test_a_shift_moves_the_group_by_tiles_and_renders_as_the_box_built_there() -> void:
	var rest: ArtPrim = ArtPrim.parse("box hull steel 0 0 0 0.4 0.2 0.3 group=arm")
	var by: Array[ArtMove] = [ArtMove.parse("walk 1 arm shift 0.3 -0.1 0.2")]
	var moved: ArtPrim = rest.moved(by)
	(
		assert_bool(
			moved.aabb().is_equal_approx(AABB(Vector3(0.1, -0.2, 0.2), Vector3(0.4, 0.2, 0.3)))
		)
		. is_true()
	)
	var built: ArtPrim = ArtPrim.parse("box hull steel 0.3 -0.1 0.2 0.4 0.2 0.3")
	for yaw: float in [0.0, 22.5, 90.0, -135.0]:
		var got: Array[ArtRender.Poly] = ArtRender.render([moved], yaw, &"fossil")
		var want: Array[ArtRender.Poly] = ArtRender.render([built], yaw, &"fossil")
		assert_array(_signatures(got)).override_failure_message("yaw %s" % yaw).is_equal(
			_signatures(want)
		)
	# The rest primitive is untouched by `moved`.
	(
		assert_bool(
			rest.aabb().is_equal_approx(AABB(Vector3(-0.2, -0.1, 0.0), Vector3(0.4, 0.2, 0.3)))
		)
		. is_true()
	)


func test_a_turn_goes_about_x_y_or_z_through_a_pivot_in_the_hulls_sense() -> void:
	var x_move: ArtMove = ArtMove.parse("walk 0 g turn x 90 0 0 0")
	var y_move: ArtMove = ArtMove.parse("walk 0 g turn y 90 0 0 0")
	var z_move: ArtMove = ArtMove.parse("walk 0 g turn z 90 0 0 0")
	# A positive turn takes x towards y about z (the hull's yaw), y towards z about x, z towards x
	# about y.
	assert_vector(z_move.place(Vector3.RIGHT)).is_equal_approx(
		Vector3(0, 1, 0), Vector3.ONE * TOLERANCE
	)
	assert_vector(x_move.place(Vector3(0, 1, 0))).is_equal_approx(
		Vector3(0, 0, 1), Vector3.ONE * TOLERANCE
	)
	assert_vector(y_move.place(Vector3(0, 0, 1))).is_equal_approx(
		Vector3(1, 0, 0), Vector3.ONE * TOLERANCE
	)
	# So a positive turn about y swings a point below its pivot back, towards -x.
	var swing: ArtMove = ArtMove.parse("walk 0 g turn y 30 0 0 1")
	var foot: Vector3 = swing.place(Vector3(0, 0, 0))
	assert_float(foot.x).is_less(-0.4)
	assert_float(foot.z).is_equal_approx(1.0 - cos(deg_to_rad(30.0)), TOLERANCE)
	# Each turn leaves its own axis alone and a negative angle is the opposite sense.
	assert_float(z_move.place(Vector3(0, 0, 0.7)).z).is_equal_approx(0.7, TOLERANCE)
	assert_vector(ArtMove.parse("walk 0 g turn z -90 0 0 0").place(Vector3.RIGHT)).is_equal_approx(
		Vector3(0, -1, 0), Vector3.ONE * TOLERANCE
	)
	# Through a pivot: (2, 1, 0) is one tile in front of (1, 1, 0), which turns to one tile beside it.
	var around: ArtMove = ArtMove.parse("walk 0 g turn z 90 1 1 0")
	assert_vector(around.place(Vector3(2, 1, 0))).is_equal_approx(
		Vector3(1, 2, 0), Vector3.ONE * TOLERANCE
	)
	assert_vector(around.place(Vector3(1, 1, 5))).is_equal_approx(
		Vector3(1, 1, 5), Vector3.ONE * TOLERANCE
	)
	# A normal is turned and not shifted.
	assert_vector(z_move.spin(Vector3.RIGHT)).is_equal_approx(
		Vector3(0, 1, 0), Vector3.ONE * TOLERANCE
	)
	assert_vector(ArtMove.parse("walk 0 g shift 1 2 3").spin(Vector3.RIGHT)).is_equal(Vector3.RIGHT)


func test_a_box_turned_a_quarter_about_each_axis_through_its_own_middle_swaps_its_extents() -> void:
	# 0.4 long, 0.2 wide, 0.1 high, its middle at (0, 0, 0.05) and so on for each axis.
	var box: String = "box hull steel 0 0 0 0.4 0.2 0.1 group=g"
	var cases: Dictionary[String, Vector3] = {
		"turn z 90 0 0 0.05": Vector3(0.2, 0.4, 0.1),
		"turn x 90 0 0 0.05": Vector3(0.4, 0.1, 0.2),
		"turn y 90 0 0 0.05": Vector3(0.1, 0.2, 0.4),
	}
	for turn: String in cases:
		var move: ArtMove = ArtMove.parse("walk 0 g " + turn)
		var prim: ArtPrim = ArtPrim.parse(box).moved([move] as Array[ArtMove])
		var extent: Vector3 = cases[turn]
		var want: AABB = AABB(
			Vector3(-extent.x / 2.0, -extent.y / 2.0, 0.05 - extent.z / 2.0), extent
		)
		assert_bool(prim.aabb().is_equal_approx(want)).override_failure_message(turn).is_true()
		# The faces are the turned box's, and they enclose the same box.
		var low: Vector3 = Vector3.INF
		var high: Vector3 = -Vector3.INF
		for face: ArtMesh.Face in ArtMesh.faces(prim):
			for point: Vector3 in face.points:
				low = low.min(point)
				high = high.max(point)
		(
			assert_bool(AABB(low, high - low).is_equal_approx(want))
			. override_failure_message(turn)
			. is_true()
		)
	# A box turned a quarter about z is drawn as the box with its extents swapped.
	var swapped: ArtPrim = ArtPrim.parse("box hull steel 0 0 0 0.2 0.4 0.1")
	var turned: ArtPrim = ArtPrim.parse(box).moved(
		[ArtMove.parse("walk 0 g turn z 90 0 0 0")] as Array[ArtMove]
	)
	for yaw: float in [0.0, 22.5, 90.0, 202.5]:
		assert_array(_signatures(ArtRender.render([turned], yaw, &"fossil"))).is_equal(
			_signatures(ArtRender.render([swapped], yaw, &"fossil"))
		)


func test_moves_apply_in_the_order_of_their_lines_and_a_sphere_moves_by_its_middle() -> void:
	var shift: ArtMove = ArtMove.parse("walk 0 g shift 1 0 0")
	var turn: ArtMove = ArtMove.parse("walk 0 g turn z 90 0 0 0")
	var prim: ArtPrim = ArtPrim.parse("box hull steel 0 0 0 0.2 0.2 0.2 group=g")
	var shifted_first: ArtPrim = prim.moved([shift, turn] as Array[ArtMove])
	var turned_first: ArtPrim = prim.moved([turn, shift] as Array[ArtMove])
	assert_vector(shifted_first.place(Vector3.ZERO)).is_equal_approx(
		Vector3(0, 1, 0), Vector3.ONE * TOLERANCE
	)
	assert_vector(turned_first.place(Vector3.ZERO)).is_equal_approx(
		Vector3(1, 0, 0), Vector3.ONE * TOLERANCE
	)
	# A sphere has no faces: its discs follow the moved middle.
	var ball: ArtPrim = ArtPrim.parse("sphere hull steel 0 0 0 0.4 0.4 0.4 group=g")
	var lifted: ArtPrim = ball.moved([ArtMove.parse("walk 0 g shift 0 0 0.3")] as Array[ArtMove])
	var built: ArtPrim = ArtPrim.parse("sphere hull steel 0 0 0.3 0.4 0.4 0.4")
	assert_array(_signatures(ArtRender.render([lifted], 0.0, &"fossil"))).is_equal(
		_signatures(ArtRender.render([built], 0.0, &"fossil"))
	)


func test_a_primitive_without_a_group_or_without_a_move_for_it_is_not_copied() -> void:
	var loose: ArtPrim = ArtPrim.parse("box hull steel 0 0 0 1 1 1")
	var grouped: ArtPrim = ArtPrim.parse("box hull steel 0 0 0 1 1 1 group=leg")
	var moves: Array[ArtMove] = [ArtMove.parse("walk 0 arm shift 1 0 0")]
	assert_object(loose.moved(moves)).is_same(loose)
	assert_object(grouped.moved(moves)).is_same(grouped)
	assert_str(grouped.group).is_equal("leg")
	(
		assert_object(grouped.moved([ArtMove.parse("walk 0 leg shift 1 0 0")] as Array[ArtMove]))
		. is_not_same(grouped)
	)


func test_a_group_and_a_move_line_that_are_not_valid_are_refused() -> void:
	assert_object(ArtPrim.parse("box hull steel 0 0 0 1 1 1 group=leg_l2")).is_not_null()
	assert_object(ArtPrim.parse("box anim steel 0 0 0 1 1 1")).is_not_null()
	for line: String in [
		"box hull steel 0 0 0 1 1 1 group=",
		"box hull steel 0 0 0 1 1 1 group=2legs",
		"box hull steel 0 0 0 1 1 1 group=a=b",
		"box hull steel 0 0 0 1 1 1 group=a-b",
	]:
		assert_object(ArtPrim.parse(line)).override_failure_message(line).is_null()
	assert_object(ArtMove.parse("walk 3 leg_l shift 0.1 0 -0.2")).is_not_null()
	assert_object(ArtMove.parse("anim 15 dish turn z -22.5 0 0 0.5")).is_not_null()
	for line: String in [
		"",
		"walk 1",
		"walk 1 leg",
		"walk 1 leg shift 1 2",
		"walk 1 leg shift 1 2 3 4",
		"walk 1 leg turn z 30 0 0",
		"walk 1 leg turn z 30 0 0 0 0",
		"walk 1 leg turn w 30 0 0 0",
		"walk 1 leg turn xy 30 0 0 0",
		"walk 1 leg slide 1 2 3",
		"run 1 leg shift 1 2 3",
		"hull 1 leg shift 1 2 3",
		"walk -1 leg shift 1 2 3",
		"walk 1.5 leg shift 1 2 3",
		"walk one leg shift 1 2 3",
		"walk 1 2leg shift 1 2 3",
		"walk 1 leg shift 1 x 3",
		"walk 1 leg turn z deg 0 0 0",
	]:
		assert_object(ArtMove.parse(line)).override_failure_message(line).is_null()


func test_a_squad_with_poses_says_frames_and_stride_in_its_sheet_and_the_text_loads_back() -> void:
	var model: ArtModel = _squad()
	model.poses.append_array(["idle 2", "idle 1 legr shift 0 0 0.02"])
	var sheet: IsoSheetDef = ArtSheet.of(model, ArtGen.all_shots(model))
	assert_array(Array(sheet.parts)).is_equal(["hull", "walk", "idle", "shadow"])
	assert_array(Array(sheet.counts)).is_equal([8, 8, 8, 8])
	assert_array(Array(sheet.frames)).is_equal([1, 3, 2, 1])
	assert_int(sheet.stride_milli).is_equal(900)
	var loaded: IsoSheetDef = _round_trip(sheet)
	assert_array(Array(loaded.frames)).is_equal([1, 3, 2, 1])
	assert_int(loaded.stride_milli).is_equal(900)
	assert_int(loaded.frame_count(&"hull")).is_equal(1)
	assert_int(loaded.frame_count(&"walk")).is_equal(3)
	assert_int(loaded.frame_count(&"idle")).is_equal(2)
	assert_int(loaded.frame_count(&"turret")).is_equal(1)
	assert_str(ArtSheet.text(loaded)).is_equal(ArtSheet.text(sheet))
	# The layout of a pose part is its own union over directions and frames, anchored at the
	# ground point like the hull.
	var layouts: Dictionary[StringName, ArtGen.Layout] = ArtGen.layouts(model)
	assert_vector(Vector2(loaded.frame_size(&"walk"))).is_equal(Vector2(layouts[&"walk"].size))
	assert_vector(Vector2(loaded.origin(&"walk"))).is_equal(Vector2(layouts[&"walk"].origin))
	assert_vector(Vector2(loaded.anchor(&"walk"))).is_equal(Vector2(layouts[&"walk"].origin))
	# The file of a frame: `_f<K>` only for a part with more than one, frame 0 by default.
	assert_str(loaded.path(&"walk", 4, 2)).is_equal(_walk(4, 2))
	assert_str(loaded.path(&"walk", 4)).is_equal(_walk(4, 0))
	assert_str(loaded.path(&"idle", 6, 1)).ends_with("/x_idle_d06_f1.svg")
	assert_str(loaded.path(&"hull", 4)).is_equal("res://assets/art/iso/fossil/inf/x_hull_d04.svg")
	assert_str(loaded.path(&"hull", 4, 2)).is_equal(
		"res://assets/art/iso/fossil/inf/x_hull_d04.svg"
	)
	assert_str(loaded.path(&"shadow", 4)).ends_with("/x_shadow_d04.svg")


func test_a_pose_parts_canvas_holds_every_direction_and_every_frame_with_its_margin() -> void:
	var model: ArtModel = _squad()
	var files: Dictionary[String, String] = ArtGen.build(model)
	var layouts: Dictionary[StringName, ArtGen.Layout] = ArtGen.layouts(model)
	var size: Vector2 = Vector2(layouts[&"walk"].size)
	var margin: float = ArtGen.MARGIN_PX - 0.001
	for dir: int in range(0, 16, 2):
		for frame: int in 3:
			var box: Rect2 = _bounds(files[_walk(dir, frame)])
			var inside: bool = box.position.x >= margin and box.position.y >= margin
			inside = inside and box.end.x <= size.x - margin and box.end.y <= size.y - margin
			assert_bool(inside).override_failure_message(_walk(dir, frame)).is_true()
	# Frame 2 reaches 0.3 tiles forward of the standing figure, past what frame 0 and the hull
	# canvas hold: a canvas of the first frame alone would clip it.
	var forward: int = 6
	assert_float(_bounds(files[_walk(forward, 2)]).end.x).is_greater(
		_bounds(files[_walk(forward, 0)]).end.x + 10.0
	)
	assert_int(layouts[&"walk"].size.x).is_greater(layouts[&"hull"].size.x)


func test_a_tower_with_an_anim_part_has_frames_without_a_direction_anchored_at_the_footprint_centre(
) -> void:
	var model: ArtModel = _tower()
	var files: Dictionary[String, String] = ArtGen.build(model)
	# The body, the shadow, 4 frames of the moving element, each with an import; sheet and card.
	assert_int(files.size()).is_equal((1 + 1 + 4) * 2 + 2)
	for frame: int in 4:
		var path: String = "res://assets/art/iso/fossil/bld/x_anim_f%d.svg" % frame
		assert_bool(files.has(path)).override_failure_message(path).is_true()
	assert_bool(files.has("res://assets/art/iso/fossil/bld/x_hull.svg")).is_true()
	assert_bool(files.has("res://assets/art/iso/fossil/bld/x_anim_d00_f0.svg")).is_false()
	var layouts: Dictionary[StringName, ArtGen.Layout] = ArtGen.layouts(model)
	var anim: ArtGen.Layout = layouts[&"anim"]
	# Cropped to the element and not to the footprint's diamond, and the anchor is the origin.
	assert_int(anim.size.x).is_less(layouts[&"hull"].size.x)
	assert_vector(Vector2(anim.anchor)).is_equal(Vector2(anim.origin))
	# The element is centred on the footprint centre and its foot is 1 tile up: read off frame 0.
	var top: Vector2 = _extent(
		files["res://assets/art/iso/fossil/bld/x_anim_f0.svg"], Vector2(anim.origin)
	)
	assert_float(top.x).is_equal_approx(0.0, 0.1)
	assert_float(top.y).is_equal_approx(ArtRender.project(Vector3(0.15, 0.05, 1.0)).y, 0.1)
	var sheet: IsoSheetDef = _round_trip(ArtSheet.of(model, ArtGen.all_shots(model)))
	assert_array(Array(sheet.parts)).is_equal(["hull", "anim", "shadow"])
	assert_array(Array(sheet.counts)).is_equal([1, 1, 1])
	assert_array(Array(sheet.frames)).is_equal([1, 4, 1])
	assert_int(sheet.anim_ms).is_equal(120)
	assert_array(Array(sheet.directions(&"anim"))).is_equal([-1])
	assert_str(sheet.path(&"anim", -1, 3)).is_equal("res://assets/art/iso/fossil/bld/x_anim_f3.svg")
	assert_vector(Vector2(sheet.origin(&"anim"))).is_equal(Vector2(anim.origin))
	# The building's body does not hold the element (the child draws it) ...
	var plain: ArtModel = _tower()
	plain.poses = PackedStringArray()
	plain.anim_ms = 0
	plain.prims = PackedStringArray(plain.prims).slice(0, 1)
	assert_str(files["res://assets/art/iso/fossil/bld/x_hull.svg"]).is_equal(
		ArtGen.build(plain)["res://assets/art/iso/fossil/bld/x_hull.svg"]
	)


func test_the_moving_element_stands_at_rest_in_the_shadow_and_the_card_of_a_building() -> void:
	# The same building with the element as a hull primitive, and with a head on a mount that the
	# element must not follow.
	var posed: ArtModel = _tower()
	var flat: ArtModel = _tower()
	flat.poses = PackedStringArray()
	flat.anim_ms = 0
	flat.prims = PackedStringArray(
		Array(flat.prims).map(func(l: String) -> String: return l.replace(" anim ", " hull "))
	)
	for model: ArtModel in [posed, flat]:
		model.prims.append("box head steel 0.3 0 0 0.2 0.2 0.2")
		model.mount = Vector3(0.2, 0.1, 1.0)
		assert_array(Array(model.problems())).is_empty()
	var with_poses: Dictionary[String, String] = ArtGen.build(posed)
	var without: Dictionary[String, String] = ArtGen.build(flat)
	# The polygons of the shadow, and of the card (its picture and its own shadow), are the same
	# set (the hull's, the head's on its mount and the element's at rest); they differ in order,
	# which follows the parts.
	for path: String in [
		"res://assets/art/iso/fossil/bld/x_shadow.svg", "res://assets/art/iso/icons/item_x.svg"
	]:
		assert_array(_sorted_lines(with_poses[path])).override_failure_message(path).is_equal(
			_sorted_lines(without[path])
		)
	assert_int(posed.shadow_prims().size()).is_equal(3)
	assert_int(posed.primitives(&"hull").size()).is_equal(1)
	assert_array(posed.parts()).is_equal([&"hull", &"head"])
	assert_array(posed.frame_parts()).is_equal([&"hull", &"head", &"anim", &"shadow"])


func test_the_health_bar_clears_the_moving_element_of_a_building_in_its_highest_frame() -> void:
	var bare: ArtModel = _tower()
	bare.poses = PackedStringArray()
	bare.anim_ms = 0
	bare.prims = PackedStringArray(Array(bare.prims).slice(0, 1))
	var level: ArtModel = _tower()
	level.poses = PackedStringArray(
		Array(level.poses).filter(func(l: String) -> bool: return not l.contains(" shift "))
	)
	# The element stands 0.6 tiles over the roof (23 world px), of which the roof's own reach up
	# the screen takes some back.
	assert_int(_bar_lift(level) - _bar_lift(bare)).is_between(5, 12)
	# In frame 2 alone it is raised by 0.3 tiles (11 world px): the bar follows that frame.
	assert_int(_bar_lift(_tower()) - _bar_lift(level)).is_between(9, 13)


func test_emitters_and_marks_round_trip_into_the_sheet_per_hull_frame() -> void:
	var rover: ArtModel = _rover()
	var sheet: IsoSheetDef = _round_trip(ArtSheet.of(rover, ArtGen.all_shots(rover)))
	assert_array(Array(sheet.emitters)).is_equal(["exhaust", "smoke"])
	assert_int(sheet.emitter_points.size()).is_equal(2 * 16)
	assert_str(sheet.marks).is_equal("tracks")
	var spots: Array[Vector3] = [Vector3(-0.5, 0.1, 0.2), Vector3(0.1, 0.0, 0.9)]
	for index: int in 2:
		for dir: int in 16:
			(
				assert_vector(sheet.emitter_point(index, dir))
				. override_failure_message("emitter %d d%02d" % [index, dir])
				. is_equal_approx(ArtGen.point_px(spots[index], dir), POINT_TOLERANCE)
			)
	# The hull turns the point: behind the tank at d06, on the other side of the screen at d10.
	assert_bool(sheet.emitter_point(0, 6).x < sheet.emitter_point(0, 10).x).is_true()
	assert_str(ArtSheet.text(sheet)).is_equal(
		ArtSheet.text(ArtSheet.of(rover, ArtGen.all_shots(rover)))
	)
	# A building has the one point of each emitter, a squad has the eight of its directions.
	var tower: ArtModel = _tower()
	tower.emitters = PackedStringArray(
		["flame 0.2 -0.1 1.4", "steam -0.2 0.2 0.6", "launch 0 0 1.5"]
	)
	var stack: IsoSheetDef = _round_trip(ArtSheet.of(tower, ArtGen.all_shots(tower)))
	assert_array(Array(stack.emitters)).is_equal(["flame", "steam", "launch"])
	assert_int(stack.emitter_points.size()).is_equal(3)
	assert_vector(stack.emitter_point(0, 6)).is_equal_approx(
		ArtGen.point_px(Vector3(0.2, -0.1, 1.4), 6), POINT_TOLERANCE
	)
	assert_vector(stack.emitter_point(2, -1)).is_equal_approx(
		ArtGen.point_px(Vector3(0, 0, 1.5), 6), POINT_TOLERANCE
	)
	var squad: ArtModel = _squad()
	squad.emitters = PackedStringArray(["smoke 0 0 0.4"])
	var sheet_of_squad: IsoSheetDef = ArtSheet.of(squad, ArtGen.all_shots(squad))
	assert_int(sheet_of_squad.emitter_points.size()).is_equal(8)
	assert_vector(sheet_of_squad.emitter_point(0, 14)).is_equal_approx(
		ArtGen.point_px(Vector3(0, 0, 0.4), 14), POINT_TOLERANCE
	)


func test_a_sheet_writes_the_frame_axis_only_when_it_has_something_to_say() -> void:
	var plain: ArtModel = _squad()
	plain.poses = PackedStringArray()
	plain.stride_milli = 0
	var text: String = ArtSheet.text(ArtSheet.of(plain, ArtGen.all_shots(plain)))
	for field: StringName in ArtSheet.LIFE_FIELDS:
		assert_bool(text.contains("\n%s = " % field)).override_failure_message(field).is_false()
	# One field at a time shows up, in the order of `LIFE_FIELDS`, after the icon.
	var rover: ArtModel = _rover()
	rover.marks = &""
	rover.emitters = PackedStringArray()
	var lines: PackedStringArray = ArtSheet.text(ArtSheet.of(rover, ArtGen.all_shots(rover))).split(
		"\n"
	)
	assert_bool(lines[-2].begins_with("icon = ")).is_true()
	rover.marks = &"wheels"
	lines = ArtSheet.text(ArtSheet.of(rover, ArtGen.all_shots(rover))).split("\n")
	assert_str(lines[-2]).is_equal('marks = &"wheels"')
	rover.emitters = PackedStringArray(["steam 0 0 0.5"])
	lines = ArtSheet.text(ArtSheet.of(rover, ArtGen.all_shots(rover))).split("\n")
	assert_bool(lines[-4].begins_with("emitters = PackedStringArray(")).is_true()
	assert_bool(lines[-3].begins_with("emitter_points = PackedVector2Array(")).is_true()


func test_only_squads_and_eight_buildings_have_a_pose_and_every_other_committed_sheet_is_as_before(
) -> void:
	var index: IsoIndex = load(IsoIndex.PATH) as IsoIndex
	assert_int(index.sheets.size()).is_greater_equal(28)
	var posed: Array[String] = []
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		if not model.poses.is_empty():
			posed.append(String(model.art_id))
			continue
		# P143 tags the vehicles with marks and an exhaust (P160: a damage and a hang point and a
		# scar_milli) and some buildings with emitters (the
		# sheet says so, below); no model but a posed one has a stride or an `anim_ms`.
		assert_bool(model.stride_milli == 0 and model.anim_ms == 0).is_true()
		var tagged: bool = not model.emitters.is_empty() or model.marks != &""
		assert_array(model.pose_parts()).override_failure_message(path).is_empty()
		assert_array(model.frame_parts()).override_failure_message(path).is_equal(
			model.parts() + [ArtModel.SHADOW]
		)
		# A fresh sheet says one frame for every part, and the committed one says nothing.
		var fresh: IsoSheetDef = ArtSheet.of(model, ArtGen.all_shots(model))
		assert_array(Array(fresh.frames)).override_failure_message(path).is_equal(
			Array(fresh.counts).map(func(_count: int) -> int: return 1)
		)
		assert_bool(fresh.emitters.is_empty() and fresh.emitter_points.is_empty()).is_equal(
			model.emitters.is_empty()
		)
		var sheet: IsoSheetDef = index.sheet(model.art_id)
		assert_array(Array(sheet.frames)).override_failure_message(path).is_empty()
		for part: String in sheet.parts:
			assert_int(sheet.frame_count(StringName(part))).override_failure_message(path).is_equal(
				1
			)
		var committed: String = FileAccess.get_file_as_string(ArtGen.sheet_path(model))
		for field: StringName in ArtSheet.LIFE_FIELDS:
			if tagged and field in [&"emitters", &"emitter_points", &"marks", &"scar_milli"]:
				continue
			(
				assert_bool(committed.contains("\n%s = " % field))
				. override_failure_message(path)
				. is_false()
			)
		assert_str(ArtSheet.text(fresh)).override_failure_message(path).is_equal(committed)
	# The four squads (P139) and the eight animated buildings (P143) are the only models with a pose.
	posed.sort()
	(
		assert_array(posed)
		. is_equal(
			[
				"fossil_radar",
				"fossil_strike",
				"power_plant",
				"renew_barracks",
				"renew_defence",
				"renew_factory",
				"renew_hq",
				"renew_power",
				"renew_radar",
				"renew_refinery",
				"renew_rifle",
				"renew_rocket",
				"renew_strike",
				"rifle_squad",
				"rocket_squad",
			]
		)
	)


func test_a_sheet_finds_an_emitter_point_for_a_vehicle_a_squad_and_a_building() -> void:
	var sheet: IsoSheetDef = IsoSheetDef.new()
	sheet.emitters = PackedStringArray(["smoke", "flame"])
	sheet.emitter_points = PackedVector2Array([Vector2(1, 1), Vector2(2, 2)])
	assert_vector(sheet.emitter_point(1, -1)).is_equal(Vector2(2, 2))
	assert_vector(sheet.emitter_point(0, 9)).is_equal(Vector2(1, 1))
	var squad: PackedVector2Array = PackedVector2Array()
	for i: int in 16:
		squad.append(Vector2(i, i))
	sheet.emitter_points = squad
	assert_vector(sheet.emitter_point(0, 4)).is_equal(Vector2(2, 2))  # Eight frames each: 4 x 8 / 16.
	assert_vector(sheet.emitter_point(1, 14)).is_equal(Vector2(15, 15))
	assert_vector(sheet.emitter_point(1, 0)).is_equal(Vector2(8, 8))
	# An index the sheet lacks answers (0, 0); a unit's direction -1 is the first frame.
	assert_vector(sheet.emitter_point(2, 0)).is_equal(Vector2.ZERO)
	assert_vector(sheet.emitter_point(-1, 0)).is_equal(Vector2.ZERO)
	assert_vector(sheet.emitter_point(1, -1)).is_equal(Vector2(8, 8))
	assert_vector(sheet.emitter_point(1, -9)).is_equal(Vector2(8, 8))
	assert_vector(sheet.emitter_point(1, 99)).is_equal(Vector2(15, 15))
	assert_vector(IsoSheetDef.new().emitter_point(0, 3)).is_equal(Vector2.ZERO)
	assert_int(sheet.frame_count(&"hull")).is_equal(1)
	assert_int(IsoSheetDef.new().frame_count(&"walk")).is_equal(1)
	assert_str(IsoSheetDef.frame_path(&"renew", &"inf", &"y", &"walk", 2, 1)).is_equal(
		"res://assets/art/iso/renew/inf/y_walk_d02_f1.svg"
	)
	assert_str(IsoSheetDef.frame_path(&"renew", &"bld", &"y", &"anim", -1, 0)).ends_with(
		"/y_anim_f0.svg"
	)
	assert_str(IsoSheetDef.frame_path(&"renew", &"bld", &"y", &"hull", -1)).ends_with("/y_hull.svg")


func test_a_model_with_poses_is_valid_and_each_mistake_in_them_is_named() -> void:
	for model: ArtModel in [_squad(), _tower(), _rover()]:
		assert_array(Array(model.problems())).is_empty()
	var header: String = "not a header"
	var move: String = "no such frame or group"
	var stride: String = "stride_milli is above 0"
	var kind: String = "an emitter is"
	var cases: Array[Array] = [
		["one frame", header, func(m: ArtModel) -> void: m.poses[0] = "walk 1"],
		["17 frames", header, func(m: ArtModel) -> void: m.poses[0] = "walk 17"],
		["a count with a tail", header, func(m: ArtModel) -> void: m.poses.append("idle 2x")],
		["an unknown pose part", header, func(m: ArtModel) -> void: m.poses.append("run 4")],
		["a line that is nothing", header, func(m: ArtModel) -> void: m.poses.append("legs")],
		[
			"a move past the last frame",
			move,
			func(m: ArtModel) -> void: m.poses.append("walk 3 legl shift 0 0 0")
		],
		[
			"a group no primitive has",
			move,
			func(m: ArtModel) -> void: m.poses.append("walk 1 tail shift 0 0 0")
		],
		[
			"a move of a pose without a header",
			move,
			func(m: ArtModel) -> void: m.poses.append("idle 0 legl shift 0 0 0")
		],
		["two headers", "more than one walk", func(m: ArtModel) -> void: m.poses.append("walk 4")],
		["a walk without a stride", stride, func(m: ArtModel) -> void: m.stride_milli = 0],
		[
			"a stride without a walk",
			stride,
			func(m: ArtModel) -> void: m.poses = PackedStringArray()
		],
		["a negative stride", stride, func(m: ArtModel) -> void: m.stride_milli = -900],
		["a negative stride without a walk", stride, func(m: ArtModel) -> void: _no_poses(m, -5)],
		["a walk of a vehicle", "a squad's", func(m: ArtModel) -> void: m.category = &"veh"],
		["an anim of a squad", "a squad's", func(m: ArtModel) -> void: _squad_anim(m)],
		["an anim_ms without an anim", "anim_ms", func(m: ArtModel) -> void: m.anim_ms = 100],
		["a negative anim_ms", "anim_ms", func(m: ArtModel) -> void: _no_poses(m, 0, -1)],
		["a group on a turret", "group=", func(m: ArtModel) -> void: _grouped_turret(m)],
		[
			"a bad emitter kind",
			kind,
			func(m: ArtModel) -> void: m.emitters = PackedStringArray(["fountain 0 0 0"])
		],
		[
			"an emitter without a height",
			kind,
			func(m: ArtModel) -> void: m.emitters = PackedStringArray(["smoke 0 0"])
		],
		[
			"an emitter with a fourth number",
			kind,
			func(m: ArtModel) -> void: m.emitters = PackedStringArray(["smoke 0 0 0 0"])
		],
		["marks of a squad", "marks", func(m: ArtModel) -> void: m.marks = &"tracks"],
	]
	for found: Array in cases:
		var model: ArtModel = _squad()
		found[2].call(model)
		var text: String = "\n".join(model.problems())
		assert_str(text).override_failure_message(found[0]).contains(found[1])
	var tower: ArtModel = _tower()
	tower.anim_ms = 0
	assert_str("\n".join(tower.problems())).contains("anim_ms")
	tower = _tower()
	tower.poses = PackedStringArray()
	tower.anim_ms = 0
	assert_str("\n".join(tower.problems())).contains("go together")
	tower = _tower()
	tower.prims = PackedStringArray(Array(tower.prims).slice(0, 1))
	assert_str("\n".join(tower.problems())).contains("go together")
	var rover: ArtModel = _rover()
	rover.marks = &"treads"
	assert_str("\n".join(rover.problems())).contains("marks")


func _squad() -> ArtModel:
	var model: ArtModel = _model(&"inf", &"x")
	model.prims = PackedStringArray(
		[
			"box hull olive 0 0 0.25 0.2 0.3 0.3",
			"box hull iron 0 -0.07 0 0.1 0.08 0.25 group=legl",
			"box hull iron 0 0.07 0 0.1 0.08 0.25 group=legr",
		]
	)
	model.poses = PackedStringArray(
		[
			"walk 3",
			"walk 1 legl turn y 30 0 -0.07 0.25",
			"walk 1 legr turn y -30 0 0.07 0.25",
			"walk 2 legl shift 0.3 0 0",
		]
	)
	model.stride_milli = 900
	return model


## The squad without poses, with a `stride_milli` and an `anim_ms`.
func _no_poses(model: ArtModel, stride: int, anim: int = 0) -> void:
	model.poses = PackedStringArray()
	model.stride_milli = stride
	model.anim_ms = anim


## The squad with an element and a pose of `anim`, which a squad does not have.
func _squad_anim(model: ArtModel) -> void:
	model.prims.append("box anim steel 0 0 0.6 0.1 0.1 0.1 group=head")
	model.poses.append("anim 2")
	model.anim_ms = 100


## The squad with a group on a primitive of a turret, which no pose moves.
func _grouped_turret(model: ArtModel) -> void:
	model.prims.append("box turret steel 0 0 0 0.1 0.1 0.1 group=gun")
	model.mount = Vector3(0, 0, 0.3)


## Whether every polygon of primitive 1 (the leg) comes before every polygon of primitive 0.
func _leg_comes_first(polys: Array[ArtRender.Poly]) -> bool:
	var last_leg: int = -1
	var first_torso: int = polys.size()
	for at: int in polys.size():
		if polys[at].prim == 1:
			last_leg = at
		elif polys[at].prim == 0:
			first_torso = mini(first_torso, at)
	return last_leg >= 0 and last_leg < first_torso


func _tower() -> ArtModel:
	var model: ArtModel = _model(&"bld", &"x")
	model.footprint = 2
	model.prims = PackedStringArray(
		["box hull concrete 0 0 0 1.2 1.2 1.0", "box anim steel 0 0 1.0 0.3 0.1 0.6 group=head"]
	)
	model.poses = PackedStringArray(
		[
			"anim 4",
			"anim 1 head turn z 90 0 0 0",
			"anim 2 head turn z 180 0 0 0",
			"anim 2 head shift 0 0 0.3",
			"anim 3 head turn z 270 0 0 0",
		]
	)
	model.anim_ms = 120
	return model


func _rover() -> ArtModel:
	var model: ArtModel = _model(&"veh", &"x")
	model.prims = PackedStringArray(["box hull olive 0 0 0.1 1.0 0.5 0.2"])
	model.emitters = PackedStringArray(["exhaust -0.5 0.1 0.2", "smoke 0.1 0 0.9"])
	model.marks = &"tracks"
	return model


## The lines of a text, sorted.
func _sorted_lines(text: String) -> Array:
	var lines: Array = Array(text.split("\n"))
	lines.sort()
	return lines


## The `bar_lift_px` a fresh run writes for `model`.
func _bar_lift(model: ArtModel) -> int:
	var text: String = ArtGen.build(model)[ArtGen.sheet_path(model)]
	return int(RegEx.create_from_string("bar_lift_px = (\\d+)").search(text).get_string(1))


func _model(category: StringName, id: StringName) -> ArtModel:
	var model: ArtModel = ArtModel.new()
	model.art_id = id
	model.faction = &"fossil"
	model.category = category
	return model


## `res://assets/art/iso/fossil/inf/x_walk_d<NN>_f<K>.svg`; frame -1 has no `_f<K>`.
func _walk(dir: int, frame: int) -> String:
	return IsoSheetDef.frame_path(&"fossil", &"inf", &"x", &"walk", dir, frame)


## What a picture is: its polygons as text, each ring from its smallest corner (two boxes with the
## same faces start their rings at different corners), sorted.
func _signatures(polys: Array[ArtRender.Poly]) -> Array[String]:
	var found: Array[String] = []
	for poly: ArtRender.Poly in polys:
		var points: Array[String] = []
		for point: Vector2 in poly.points:
			points.append("%s,%s" % [ArtSvg.num(point.x), ArtSvg.num(point.y)])
		var first: int = points.find(points.min())
		points = points.slice(first) + points.slice(0, first)
		found.append("%s %s %s" % [poly.fill, poly.stroke, " ".join(points)])
	found.sort()
	return found


## The box round the polygon corners of a frame, in px of its canvas.
func _bounds(text: String) -> Rect2:
	var box: Rect2 = Rect2()
	var first: bool = true
	for found: RegExMatch in _points.search_all(text):
		for pair: String in found.get_string(1).split(" "):
			var at: Vector2 = Vector2(
				pair.get_slice(",", 0).to_float(), pair.get_slice(",", 1).to_float()
			)
			box = Rect2(at, Vector2.ZERO) if first else box.expand(at)
			first = false
	return box


## The middle of a frame's polygons across and the lowest point of them, in px from `origin`.
func _extent(text: String, origin: Vector2) -> Vector2:
	var box: Rect2 = _bounds(text)
	return Vector2(box.get_center().x - origin.x, box.end.y - origin.y)


## The sheet as a `.tres` in a temporary folder and loaded again.
func _round_trip(sheet: IsoSheetDef) -> IsoSheetDef:
	var access: DirAccess = DirAccess.create_temp("frame_axis_")
	var file: String = access.get_current_dir().path_join("sheet.tres")
	var written: FileAccess = FileAccess.open(file, FileAccess.WRITE)
	written.store_string(ArtSheet.text(sheet))
	written.close()
	return ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE) as IsoSheetDef
