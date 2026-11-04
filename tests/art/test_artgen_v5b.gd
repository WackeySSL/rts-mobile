extends GdUnitTestSuite
## Generator v5b (plan row P163b, ADR 0029 section 5) on crafted buildings in a test's own output:
## the shape `broken`, the shape `rod` with `bend`, and the helper `petals`.

const Support = preload("res://tests/art/artgen_v5_support.gd")
const BODY: String = "box hull concrete 0 0 0 1.6 1.6 0.4 group=body"


func _model(lines: Array[String], poses: Array[String] = []) -> ArtModel:
	var prims: Array[String] = [BODY]
	prims.append_array(lines)
	return Support.with_prims(prims, poses, [])


func _hull_polys(model: ArtModel) -> Array[ArtRender.Poly]:
	return ArtRender.render(model.primitives(&"hull"), 0.0, model.faction)


func _of_shape(model: ArtModel, shape: StringName) -> Array[ArtPrim]:
	var found: Array[ArtPrim] = []
	for prim: ArtPrim in model.primitives(&"hull"):
		if prim.shape == shape:
			found.append(prim)
	return found


func _top(prim: ArtPrim) -> Array[float]:
	var heights: Array[float] = []
	for face: ArtMesh.Face in ArtMesh.faces(prim):
		for point: Vector3 in face.points:
			heights.append(point.z)
	return heights


func test_broken_draws_n_teeth_between_low_and_the_full_height() -> void:
	var model: ArtModel = _model(["broken hull concrete 0 0 0.4 1.2 0.3 1.0 teeth=6 low=0.4"])
	assert_array(Array(model.problems())).is_empty()
	var prim: ArtPrim = _of_shape(model, &"broken")[0]
	var fractions: PackedFloat64Array = prim.tooth_fractions()
	assert_int(fractions.size()).is_equal(6)
	var rising: int = 0
	for i: int in fractions.size():
		assert_float(fractions[i]).is_between(0.4, 1.0)
		if i > 0 and (fractions[i] > fractions[i - 1]) == (i % 2 == 0):
			rising += 1
	assert_int(rising).is_equal(5)  # a zigzag: high, low, high, low...
	var tops: Array[float] = []
	for z: float in _top(prim):
		if z > 0.4 + 1e-6:
			tops.append(z)
	assert_float(tops.min()).is_greater_equal(0.4 + 0.4 * 1.0 - 1e-6)
	assert_float(tops.max()).is_less_equal(1.4 + 1e-6)
	# Front and back, two ends, a floor and five tooth segments.
	assert_int(ArtMesh.faces(prim).size()).is_equal(2 + 2 + 1 + 5)
	assert_int(_hull_polys(model).size()).is_greater(0)


func test_broken_is_the_same_on_two_runs_and_differs_for_two_lines() -> void:
	var line: String = "broken hull concrete 0 0 0.4 1.2 0.3 1.0 teeth=8 low=0.2"
	var one: ArtModel = _model([line])
	var two: ArtModel = _model([line])
	assert_array(Array(_of_shape(one, &"broken")[0].tooth_fractions())).is_equal(
		Array(_of_shape(two, &"broken")[0].tooth_fractions())
	)
	assert_array(Array(ArtSvg.group("", _hull_polys(one)))).is_equal(
		Array(ArtSvg.group("", _hull_polys(two)))
	)
	var both: ArtModel = _model([line, line.replace(" 0 0 0.4", " 0.5 0 0.4")])
	var pair: Array[ArtPrim] = _of_shape(both, &"broken")
	assert_array(Array(pair[0].tooth_fractions())).is_not_equal(Array(pair[1].tooth_fractions()))


func test_broken_refuses_a_wrong_option() -> void:
	for line: String in [
		"broken hull concrete 0 0 0.4 1 1 1 teeth=1",
		"broken hull concrete 0 0 0.4 1 1 1 low=1",
		"broken hull concrete 0 0 0.4 1 1 1 low=0",
		"box hull concrete 0 0 0.4 1 1 1 teeth=4",
		"box hull concrete 0 0 0.4 1 1 1 low=0.5",
		"box hull concrete 0 0 0.4 1 1 1 bend=10",
	]:
		assert_str("\n".join(_model([line]).problems())).contains("not a primitive")


func test_rod_is_a_stroke_of_its_width_with_no_outline() -> void:
	var model: ArtModel = _model(["rod hull rebar -0.4 0 0.4 0.4 0 1.0 6"])
	assert_array(Array(model.problems())).is_empty()
	var rods: Array[ArtRender.Poly] = []
	for poly: ArtRender.Poly in _hull_polys(model):
		if poly.fill == ArtPalette.tone(&"fossil", &"rebar", ArtPalette.LEFT):
			rods.append(poly)
	assert_int(rods.size()).is_equal(1)
	assert_str(rods[0].stroke).is_equal("")
	var pts: PackedVector2Array = rods[0].points
	assert_int(pts.size()).is_equal(4)
	assert_float(pts[0].distance_to(pts[3])).is_equal_approx(6.0, 1e-3)  # its width in px
	assert_float(pts[1].distance_to(pts[2])).is_equal_approx(6.0, 1e-3)
	var ends: Vector2 = (pts[0] + pts[3]) / 2.0
	assert_vector(ends).is_equal_approx(
		ArtRender.project(Vector3(-0.4, 0, 0.4)), Vector2(1e-3, 1e-3)
	)
	var svg: String = ArtSvg.frame("t", Vector2i(400, 400), Vector2i(200, 300), rods)
	assert_str(svg).not_contains('stroke="#')
	assert_int(svg.count("<polygon")).is_equal(1)


func test_rod_with_bend_makes_two_segments() -> void:
	var straight: ArtModel = _model(["rod hull beam 0 0 0.4 0 0 1.4 4"])
	var bent: ArtModel = _model(["rod hull beam 0 0 0.4 0 0 1.4 4 bend=40"])
	var colour: String = ArtPalette.tone(&"fossil", &"beam", ArtPalette.LEFT)
	var counts: Array[int] = []
	for model: ArtModel in [straight, bent]:
		assert_array(Array(model.problems())).is_empty()
		var n: int = 0
		for poly: ArtRender.Poly in _hull_polys(model):
			n += 1 if poly.fill == colour else 0
		counts.append(n)
	assert_array(counts).is_equal([1, 2])
	var path: PackedVector3Array = _of_shape(bent, &"rod")[0].rod_path()
	assert_vector(path[0]).is_equal_approx(Vector3(0, 0, 0.4), Vector3.ONE * 1e-6)
	assert_vector(path[1]).is_equal_approx(Vector3(0, 0, 0.9), Vector3.ONE * 1e-6)
	assert_float(path[1].distance_to(path[2])).is_equal_approx(0.5, 1e-6)  # the half keeps its length
	assert_float(path[2].x).is_greater(0.2)  # the upper half swings towards +x


func test_rod_is_ordered_at_its_midpoint_and_refuses_a_thin_width() -> void:
	var front: ArtModel = _model(["rod hull rebar 1.2 1.2 0.1 1.3 1.3 0.3 4"])
	var back: ArtModel = _model(["rod hull rebar -1.3 -1.3 0.1 -1.2 -1.2 0.3 4"])
	var prims: Array[ArtPrim] = front.primitives(&"hull")
	assert_int(ArtRender.draw_order(prims, 0.0)[-1]).is_equal(1)  # nearer than the body: last
	prims = back.primitives(&"hull")
	assert_int(ArtRender.draw_order(prims, 0.0)[0]).is_equal(1)  # farther than the body: first
	assert_str("\n".join(_model(["rod hull rebar 0 0 0.4 0 0 1 1.5"]).problems())).contains("not a")
	assert_str("\n".join(_model(["rod hull rebar 0 0 0.4 0 0 0.4 4"]).problems())).contains("not a")
	assert_str("\n".join(_model(["rod hull rebar 0 0 0.4 0 0 1 4 bend=120"]).problems())).contains(
		"not a"
	)


func test_petals_expand_to_n_plates_turned_by_tilt_and_an_interior_disc() -> void:
	var counts: Array[int] = []
	for n: int in [3, 6, 12]:
		var model: ArtModel = _model(["petals hull steel 0 0 0.4 0.8 %d 50 group=lid" % n])
		assert_array(Array(model.problems())).is_empty()
		var plates: int = 0
		var discs: int = 0
		for prim: ArtPrim in model.primitives(&"hull"):
			plates += 1 if prim.shape == &"box" and prim.group == &"lid" else 0
			discs += 1 if prim.material == &"interior" else 0
		counts.append(plates * 100 + discs)
	assert_array(counts).is_equal([301, 601, 1201])
	var model: ArtModel = _model(["petals hull steel 0 0 0.4 0.8 4 50"])
	var first: ArtPrim = model.primitives(&"hull")[2]  # body, disc, then plate 0 (towards +x)
	assert_str(first.material).is_equal("steel")
	var top: float = -INF
	var reach: float = -INF
	for face: ArtMesh.Face in ArtMesh.faces(first):
		for point: Vector3 in face.points:
			top = maxf(top, point.z)
			reach = maxf(reach, point.x)
	# Turned out by 50 degrees about its base at the rim (x = 0.4): half a tile tall.
	assert_float(top).is_equal_approx(
		0.4 + 0.4 * cos(deg_to_rad(50.0)) + 0.02 * sin(deg_to_rad(50.0)), 0.03
	)
	assert_float(reach).is_equal_approx(
		0.4 + 0.4 * sin(deg_to_rad(50.0)) + 0.02 * cos(deg_to_rad(50.0)), 0.03
	)
	# The fourth plate faces the other way (+y after 90 degrees): the first is turned about z.
	var second: ArtPrim = model.primitives(&"hull")[3]
	var side: float = -INF
	for face: ArtMesh.Face in ArtMesh.faces(second):
		for point: Vector3 in face.points:
			side = maxf(side, point.y)
	assert_float(side).is_equal_approx(reach, 0.03)


func test_petals_refuse_a_wrong_line() -> void:
	for line: String in [
		"petals hull steel 0 0 0.4 0.8 2 50",
		"petals hull steel 0 0 0.4 0.8 17 50",
		"petals hull steel 0 0 0.4 0.8 4 0",
		"petals hull steel 0 0 0.4 0.8 4 95",
		"petals hull steel 0 0 0.4 0 4 50",
		"petals hull steel 0 0 0.4 0.8 4",
		"petals hull steel 0 0 0.4 0.8 4 50 bend=3",
	]:
		assert_str("\n".join(_model([line]).problems())).contains("not a primitive")


func test_petals_survive_a_pose_and_draw() -> void:
	var model: ArtModel = Support.building(
		["petals hull steel 0 0 1.0 0.5 5 40 group=lid damage=2"],
		Support.POSES + ["dmg2 0 lid shift 0 0 0.1"]
	)
	assert_array(Array(model.problems())).is_empty()
	var stage: Array[ArtPrim] = model.damage_prims(2)
	var plates: int = 0
	for prim: ArtPrim in stage:
		plates += 1 if prim.group == &"lid" and prim.shape == &"box" else 0
	assert_int(plates).is_equal(5)
	assert_int(ArtGen.stage_polys(model, 2).size()).is_greater(0)
	# A hide of the group takes the plates and the disc together; the intact picture has them.
	var hidden: ArtModel = Support.building(
		["petals hull steel 0 0 1.0 0.5 5 40 group=lid"], Support.POSES + ["dmg2 0 lid hide"]
	)
	assert_array(Array(hidden.problems())).is_empty()
	var lids: Array[int] = []
	for count: Array in [
		hidden.primitives(&"hull"), hidden.damage_prims(1), hidden.damage_prims(2)
	]:
		lids.append(count.filter(func(p: ArtPrim) -> bool: return p.group == &"lid").size())
	assert_array(lids).is_equal([6, 6, 0])
