extends GdUnitTestSuite
## The bake tool's mesh builder (plan row P656a, ADR 0053 sections 5, 7 and 9): face counts and
## outward normals of every primitive, and the triangle cap.

const MAT: StringName = &"steel"
const NONE: float = 0.0


func _builder() -> BakeMesh:
	return BakeMesh.new(&"probe")


## Every triangle of every batch as [centroid, front normal, mean vertex normal], Godot frame. A
## front face winds clockwise in Godot, so the normal it faces is minus the counter-clockwise cross.
func _triangles(m: BakeMesh) -> Array[Array]:
	var found: Array[Array] = []
	for batch: BakeMesh.Batch in m.batches.values():
		for i: int in range(0, batch.indices.size(), 3):
			var p: Array[Vector3] = []
			var n: Vector3 = Vector3.ZERO
			for k: int in 3:
				var at: int = batch.indices[i + k]
				p.append(batch.vertices[at])
				n += batch.normals[at]
			var winding: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
			found.append([(p[0] + p[1] + p[2]) / 3.0, -winding.normalized(), n.normalized()])
	return found


func _face_tris(corners: int) -> int:
	return (corners - 2) + 2 * corners  ## A flat top and a strip of two triangles a side.


func test_a_plane_box_without_a_bevel_is_12_triangles_and_with_one_60() -> void:
	var flat: BakeMesh = _builder()
	BakeShapes.box(flat, MAT, Vector3.ZERO, Vector3.ONE, NONE)
	assert_int(flat.triangles).is_equal(12)
	var soft: BakeMesh = _builder()
	BakeShapes.box(soft, MAT, Vector3.ZERO, Vector3.ONE, 0.02)
	assert_int(soft.triangles).is_equal(6 * _face_tris(4))


func test_every_triangle_of_a_box_winds_and_leans_outward() -> void:
	var m: BakeMesh = _builder()
	BakeShapes.box(m, MAT, Vector3(1.0, 2.0, 3.0), Vector3(1.0, 0.6, 0.4), 0.02)
	for tri: Array in _triangles(m):
		var out: Vector3 = tri[0] - Vector3(1.0, 3.0, 2.0)  # the centre, in the Godot frame
		assert_float(tri[1].dot(tri[2])).is_greater(0.5)
		assert_float(out.dot(tri[2])).is_greater(0.0)


func test_a_clipped_wedge_has_a_face_per_plane_and_outward_normals() -> void:
	var slope: Vector3 = Vector3(1.0, 0.0, 1.0).normalized()
	var planes: Array[Plane] = [
		Plane(Vector3(-1, 0, 0), 0.5),
		Plane(Vector3(1, 0, 0), 0.5),
		Plane(Vector3(0, -1, 0), 0.3),
		Plane(Vector3(0, 1, 0), 0.3),
		Plane(Vector3(0, 0, -1), 0.0),
		Plane(Vector3(0, 0, 1), 0.4),
		Plane(slope, slope.dot(Vector3(0.5, 0.0, 0.2))),
	]
	var m: BakeMesh = _builder()
	m.solid(MAT, planes, NONE)
	# Without a bevel each face is a fan of its corners minus 2: the box's six faces and the
	# slope's quad are 7 faces, the two sides and the top lose a corner or two to the slope.
	assert_int(m.triangles).is_between(10, 16)
	var middle: Vector3 = Vector3(0.0, 0.15, 0.0)  # inside the solid, in the Godot frame
	for tri: Array in _triangles(m):
		assert_float(tri[1].dot(tri[2])).is_greater(0.9)
		assert_float((tri[0] - middle).dot(tri[2])).is_greater(0.0)


func test_art_prim_faces_are_the_artmesh_faces_with_a_bevel_each() -> void:
	var prism: ArtPrim = ArtPrim.parse("prism hull steel 0 0 0 1 1 1 sides=6")
	var expected: int = 0
	for face: ArtMesh.Face in ArtMesh.faces(prism):
		expected += _face_tris(face.points.size())
	var m: BakeMesh = _builder()
	m.art_prim(MAT, prism)
	assert_int(m.triangles).is_equal(expected)
	var box: BakeMesh = _builder()
	box.art_prim(MAT, ArtPrim.parse("box hull steel 0 0 0 1 1 1"))
	assert_int(box.triangles).is_equal(6 * _face_tris(4))
	for tri: Array in _triangles(m):
		assert_float(tri[1].dot(tri[2])).is_greater(0.5)


func test_cylinder_counts_and_normals_point_away_from_the_axis() -> void:
	var plain: BakeMesh = _builder()
	BakeShapes.cylinder(plain, MAT, Vector3.ZERO, Vector3(0, 0, 1), 0.2, 12)
	assert_int(plain.triangles).is_equal(12 * 4)  # two for each side, one for each cap
	var chamfered: BakeMesh = _builder()
	BakeShapes.cylinder(chamfered, MAT, Vector3.ZERO, Vector3(0, 0, 1), 0.2, 12, 0.03)
	assert_int(chamfered.triangles).is_equal(12 * 8)
	var open_tube: BakeMesh = _builder()
	BakeShapes.cylinder(open_tube, MAT, Vector3.ZERO, Vector3(0, 0, 1), 0.2, 12, 0.03, -1.0, false)
	assert_int(open_tube.triangles).is_equal(12 * 2)
	for tri: Array in _triangles(chamfered):
		var from_axis: Vector3 = Vector3(tri[0].x, 0.0, tri[0].z)  # Godot frame: z up is y
		var axis_point: Vector3 = Vector3(0.0, tri[0].y, 0.0)
		assert_float(tri[1].dot(tri[2])).is_greater(0.9)
		if absf(tri[2].y) < 0.3:
			assert_float((tri[0] - axis_point).dot(tri[2])).is_greater(0.0)
		else:
			assert_float(from_axis.length()).is_less(0.21)


func test_a_cone_leans_its_normals_towards_the_narrow_end() -> void:
	var m: BakeMesh = _builder()
	BakeShapes.cylinder(m, MAT, Vector3.ZERO, Vector3(0, 0, 1), 0.2, 8, 0.0, 0.1)
	var found: int = 0
	for tri: Array in _triangles(m):
		if absf(tri[2].y) < 0.95:
			found += 1
			assert_float(tri[2].y).is_greater(0.0)  # Godot y is the model's z, up the cone
	assert_int(found).is_equal(16)


func test_a_dome_is_one_triangle_a_segment_and_rises_along_its_normal() -> void:
	var m: BakeMesh = _builder()
	BakeShapes.dome(m, MAT, Vector3(0.5, 0.5, 0.5), Vector3(0, 0, 1), 0.1, 6)
	assert_int(m.triangles).is_equal(6)
	for tri: Array in _triangles(m):
		assert_float(tri[2].y).is_greater(0.0)
		assert_float(tri[0].y).is_greater(0.5)
		assert_float((tri[0] - Vector3(0.5, 0.5, 0.5)).dot(tri[2])).is_greater(0.0)


func test_a_torus_is_two_triangles_a_cell_with_normals_away_from_its_tube() -> void:
	var m: BakeMesh = _builder()
	var big: float = 0.3
	BakeShapes.torus(m, MAT, Vector3.ZERO, Vector3(0, 0, 1), big, 0.05, 10, 5)
	assert_int(m.triangles).is_equal(10 * 5 * 2)
	for tri: Array in _triangles(m):
		var ring_dir: Vector3 = Vector3(tri[0].x, 0.0, tri[0].z).normalized()  # Godot: y is up
		assert_float((tri[0] - ring_dir * big).dot(tri[2])).is_greater(0.0)
		assert_float(tri[1].dot(tri[2])).is_greater(0.8)


func test_the_cap_admits_60000_and_refuses_60001_naming_the_id_and_count() -> void:
	var m: BakeMesh = BakeMesh.new(&"big_depot")
	var p: PackedVector3Array = [Vector3.ZERO, Vector3.RIGHT, Vector3.UP]
	var n: PackedVector3Array = [Vector3.BACK, Vector3.BACK, Vector3.BACK]
	var flags: PackedFloat32Array = [0.0, 0.0, 0.0]
	for i: int in BakeMesh.TRIANGLE_CAP:
		m.tri(MAT, p, n, flags)
	assert_str(m.cap_error()).is_empty()
	m.tri(MAT, p, n, flags)
	assert_int(m.triangles).is_equal(60001)
	assert_str(m.cap_error()).contains("big_depot").contains("60001").contains("60000")
	# Nothing is cut short in silence: past the cap the batch stops growing, the count does not.
	var batch: BakeMesh.Batch = m.batches[MAT]
	assert_int(batch.indices.size()).is_equal(BakeMesh.TRIANGLE_CAP * 3)
	assert_object(m.to_node({})).is_null()
