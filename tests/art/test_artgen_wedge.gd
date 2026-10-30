extends GdUnitTestSuite
## The sloped face of a wedge (plan row P99c, ADR 0023 section 5): a wedge with `slope=1` (or -1)
## keeps its sloped face wherever it stands. The face's mean sits on the middle of the wedge's box,
## so a normal oriented against that middle was decided by rounding noise, and the face was culled
## when the noise went the wrong way. `ArtMesh` now orients every normal against a point inside the
## solid, which no face can pass through.

## Wedges at the origin and away from it, in x, y and z, leaning towards +x and towards -x: the
## Flarejack's hood, the Tanker's glass front, a leaf of the Heavy Yard's sawtooth roof.
const WEDGES: Array[String] = [
	"wedge hull steel 0 0 0 1 1 1",
	"wedge hull steel 0 0 0 1 1 1 slope=-1",
	"wedge hull olive 0.34 0 0.15 0.42 0.5 0.15 slope=1",
	"wedge hull olive 0.6 0 0.35 0.36 0.5 0.14 slope=1",
	"wedge hull steel 0.733 -0.15 0.9 0.733 2 0.42 slope=-1",
	"wedge hull steel -0.733 -0.15 0.9 0.733 2 0.42 slope=-1",
	"wedge hull rust 1 -0.38 1.14 0.42 0.6 0.2 slope=1",
	"wedge hull concrete -0.7 0.45 0.05 0.3 0.8 1.2 slope=1",
	"box hull steel 0.2 -0.3 0.4 0.6 0.4 0.3 slope=1",
	"box hull steel -0.2 0.3 0.4 0.6 0.4 0.3 slope=-1",
]


func test_a_wedge_of_slope_1_keeps_its_sloped_face_wherever_it_stands() -> void:
	for line: String in WEDGES:
		var prim: ArtPrim = ArtPrim.parse(line)
		var faces: Array[ArtMesh.Face] = ArtMesh.faces(prim)
		# The low end has no face, so a wedge is a sloped top, a bottom, the tall end and two
		# triangles.
		assert_int(faces.size()).override_failure_message(line).is_equal(5)
		var slopes: Array[Vector3] = []
		for face: ArtMesh.Face in faces:
			if face.normal.z > 0.0:
				slopes.append(face.normal)
		assert_int(slopes.size()).override_failure_message(line).is_equal(1)
		if slopes.size() != 1:
			continue
		var want: Vector3 = Vector3(signf(prim.slope) * prim.size.z, 0.0, prim.size.x).normalized()
		assert_vector(slopes[0]).override_failure_message(line).is_equal_approx(
			want, Vector3.ONE * 1e-6
		)


func test_every_face_of_a_wedge_looks_away_from_the_inside_of_its_solid() -> void:
	for line: String in WEDGES:
		var prim: ArtPrim = ArtPrim.parse(line)
		var inside: Vector3 = _inside(prim)
		for face: ArtMesh.Face in ArtMesh.faces(prim):
			var middle: Vector3 = Vector3.ZERO
			for point: Vector3 in face.points:
				middle += point / face.points.size()
			(
				assert_float(face.normal.dot(middle - inside))
				. override_failure_message("%s normal %s" % [line, face.normal])
				. is_greater(1e-3)
			)
			assert_float(face.normal.length()).is_equal_approx(1.0, 1e-6)


func test_the_sloped_face_is_drawn_exactly_when_it_faces_the_camera_at_all_16_yaws() -> void:
	for line: String in WEDGES:
		var prim: ArtPrim = ArtPrim.parse(line)
		var tall: float = signf(prim.slope)
		# The faces of the solid in the model's frame: the slope, the tall end, the two sides.
		var normals: Array[Vector3] = [
			Vector3(tall * prim.size.z, 0.0, prim.size.x).normalized(),
			Vector3(-tall, 0.0, 0.0),
			Vector3(0.0, 1.0, 0.0),
			Vector3(0.0, -1.0, 0.0),
		]
		for dir: int in 16:
			var yaw: float = ArtGen.yaw(dir)
			var facing: int = 0
			for normal: Vector3 in normals:
				if ArtRender.rotate(normal, yaw).dot(ArtRender.VIEW) >= ArtRender.MIN_FACING:
					facing += 1
			var polys: Array[ArtRender.Poly] = ArtRender.render([prim], yaw, &"fossil")
			assert_int(polys.size()).override_failure_message("%s at d%02d" % [line, dir]).is_equal(
				facing
			)


func test_no_model_stands_in_for_slope_1_with_0_95_and_every_unit_slope_keeps_its_face() -> void:
	var unit_slopes: int = 0
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		for part: StringName in ArtPrim.PARTS:
			for prim: ArtPrim in model.primitives(part):
				if prim.shape != &"wedge":
					continue
				(
					assert_float(absf(prim.slope))
					. override_failure_message("%s: a wedge at slope 0.95" % path)
					. is_not_equal(0.95)
				)
				if absf(prim.slope) == 1.0:
					unit_slopes += 1
					assert_int(ArtMesh.faces(prim).size()).override_failure_message(path).is_equal(
						5
					)
	# The cabs, glass fronts, hoods and solar panels of both factions, and the Heavy Yard's roof.
	assert_int(unit_slopes).is_greater_equal(14)


## A point strictly inside the wedge's solid, found without the mesh: the centroid of its triangular
## section (a third of the way from the tall end, a third of the height up).
func _inside(prim: ArtPrim) -> Vector3:
	var tall: float = signf(prim.slope)
	return Vector3(
		prim.centre.x - tall * prim.size.x / 6.0, prim.centre.y, prim.z0 + prim.size.z / 3.0
	)
