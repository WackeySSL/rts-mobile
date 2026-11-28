extends GdUnitTestSuite
## `BakeShapes.cliff` and `ridge` (plan rows P656c round 4 and P656d4): the same seed gives the same
## mesh, another seed another one, both ends are pinned so that neighbouring walls meet, the crest
## is exactly the height, and nothing leaves the prism (the carving is inward only).

const FOOT_A: Vector3 = Vector3(0.45, -0.5, 0.0)
const FOOT_B: Vector3 = Vector3(0.45, 0.5, 0.0)
const HEIGHT: float = 0.6
const MAT: StringName = &"rock"


func _wall(seed_value: int) -> BakeMesh.Batch:
	var m: BakeMesh = BakeMesh.new(&"cliff_fixture")
	BakeShapes.cliff(m, MAT, FOOT_A, FOOT_B, HEIGHT, 0.06, seed_value)
	return m.batches[MAT]


## The heights of the vertices standing over the foot's end `at` (Godot frame: x, up, z).
func _end_heights(batch: BakeMesh.Batch, at: Vector3) -> Array[float]:
	var found: Array[float] = []
	for v: Vector3 in batch.vertices:
		if absf(v.x - at.x) < 0.0001 and absf(v.z - at.y) < 0.0001:
			var height: float = snappedf(v.y, 0.0001)
			if not found.has(height):
				found.append(height)
	found.sort()
	return found


func test_the_same_seed_gives_the_same_wall_and_another_seed_another() -> void:
	assert_array(_wall(7).vertices).is_equal(_wall(7).vertices)
	assert_array(_wall(7).vertices).is_not_equal(_wall(8).vertices)


func test_both_ends_are_pinned_whatever_the_seed() -> void:
	for at: Vector3 in [FOOT_A, FOOT_B]:
		var one: Array[float] = _end_heights(_wall(1), at)
		assert_int(one.size()).is_equal(49)
		assert_array(one).is_equal(_end_heights(_wall(99), at))
	var w: BakeMesh.Batch = _wall(4)
	assert_array(_end_heights(w, FOOT_A)).is_equal(_end_heights(w, FOOT_B))


func test_the_wall_stays_within_its_height_and_the_triangle_cap() -> void:
	var batch: BakeMesh.Batch = _wall(3)
	var tallest: float = 0.0
	for v: Vector3 in batch.vertices:
		tallest = maxf(tallest, v.y)
	assert_float(tallest).is_equal_approx(HEIGHT, 0.0001)
	assert_int(batch.indices.size() / 3).is_less(BakeMesh.TRIANGLE_CAP)


func test_the_face_looks_away_from_the_tile_centre() -> void:
	var batch: BakeMesh.Batch = _wall(5)
	var outward: int = 0
	var inward: int = 0
	for n: Vector3 in batch.normals:
		outward += 1 if n.x > 0.5 else 0
		inward += 1 if n.x < -0.5 else 0
	assert_int(outward).is_greater(4 * inward)


func test_the_carving_is_inward_only() -> void:
	for v: Vector3 in _wall(6).vertices:
		assert_float(v.x).is_less_equal(FOOT_A.x + 0.0001)


func test_a_ridge_is_pinned_at_its_ends_closed_and_stays_in_its_height() -> void:
	var m: BakeMesh = BakeMesh.new(&"ridge_fixture")
	var a: Vector3 = Vector3(-0.5, -0.5, HEIGHT)
	var b: Vector3 = Vector3(0.5, -0.5, HEIGHT)
	BakeShapes.ridge(m, MAT, a, b, 0.1, 0.1, 0.5, 0.5, 3)
	var top: float = 0.0
	var at_a: float = 0.0
	var at_b: float = 0.0
	var caps: int = 0
	var batch: BakeMesh.Batch = m.batches[MAT]
	for v: Vector3 in batch.vertices:
		top = maxf(top, v.y)
		if absf(v.z + 0.5) < 0.0001 and absf(v.x + 0.5) < 0.0001:
			at_a = maxf(at_a, v.y)
		if absf(v.z + 0.5) < 0.0001 and absf(v.x - 0.5) < 0.0001:
			at_b = maxf(at_b, v.y)
	for n: Vector3 in batch.normals:
		caps += 1 if absf(n.x) > 0.99 else 0
	assert_float(top).is_between(HEIGHT, HEIGHT + 0.1)
	assert_float(at_a).is_equal_approx(HEIGHT + 0.05, 0.0001)
	assert_float(at_b).is_equal_approx(at_a, 0.0001)
	assert_int(caps).is_equal(2 * 6 * 3)  # both ends capped: 6 triangles, 3 vertices each


func test_the_crest_lies_on_the_foot_line_and_the_cap_under_the_lip_is_flush() -> void:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 1.0
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	var batch: BakeMesh.Batch = _wall(11)
	var crest: int = 0
	for v: Vector3 in batch.vertices:
		var u: float = v.z + 0.5  # the foot runs along gy
		var share: float = v.y / HEIGHT
		if is_equal_approx(share, 1.0) or share < 0.0001:
			crest += 1
			assert_float(v.x).is_equal_approx(FOOT_A.x, 0.0001)  # the crest and the foot are pinned
		if share >= 1.0 - BakeShapes.crest_drop(noise, u) + 0.0001:
			assert_float(v.x).is_equal_approx(FOOT_A.x, 0.0001)  # flush under the lip
	assert_int(crest).is_greater(100)


## A model point (grid x, grid y, height) in the 2:1 view's texels, as `ArtRender` projects it.
func _screen(gx: float, gy: float, z: float) -> Vector2:
	return Vector2((gx - gy) * 64.0, (gx + gy) * 32.0 - z * ArtRender.Z_PX)


func test_the_tongue_lies_on_the_faces_lip_line_in_screen_texels() -> void:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 1.0
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	var m: BakeMesh = BakeMesh.new(&"tongue_fixture")
	BakeShapes.tongue(m, MAT, Vector3(0.5, -0.5, HEIGHT), Vector3(0.5, 0.5, HEIGHT), 11)
	var points: Array[Vector2] = []
	for v: Vector3 in m.batches[MAT].vertices:  # Godot frame: x, height, grid y
		points.append(_screen(v.x, v.z, v.y))
	var deepest: float = 0.0
	for i: int in 65:
		var u: float = float(i) / 64.0
		var drop: float = BakeShapes.crest_drop(noise, u)
		deepest = maxf(deepest, drop)
		# Where the face's flush cap ends: on the face's plane, `drop` of its height below the crest.
		var cap: Vector2 = _screen(0.5, -0.5 + u, HEIGHT * (1.0 - drop))
		var nearest: float = 1000.0
		for p: Vector2 in points:
			nearest = minf(nearest, p.distance_to(cap))
		(
			assert_float(nearest)
			. override_failure_message(
				"u %.3f: the tongue is %.2f texels off the lip line" % [u, nearest]
			)
			. is_less(0.05)
		)
	assert_float(deepest).is_between(0.03, BakeShapes.CREST_MAX + 0.0001)
