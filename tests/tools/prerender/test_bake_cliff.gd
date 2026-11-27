extends GdUnitTestSuite
## `BakeShapes.cliff` (plan row P656c round 4): the same seed gives the same mesh, another seed
## another one, both ends are pinned so that neighbouring walls meet, and the top stays in height.

const FOOT_A: Vector3 = Vector3(0.45, -0.5, 0.0)
const FOOT_B: Vector3 = Vector3(0.45, 0.5, 0.0)
const HEIGHT: float = 0.6
const MAT: StringName = &"rock"


func _wall(seed_value: int) -> BakeMesh.Batch:
	var m: BakeMesh = BakeMesh.new(&"cliff_fixture")
	BakeShapes.cliff(m, MAT, FOOT_A, FOOT_B, 0.15, HEIGHT, 0.06, seed_value)
	return m.batches[MAT]


## The heights of the vertices standing over the foot's end `at` (Godot frame: x, up, z).
func _end_heights(batch: BakeMesh.Batch, at: Vector3) -> Array[float]:
	var found: Array[float] = []
	for v: Vector3 in batch.vertices:
		if absf(v.x - at.x) < 0.0001 and absf(v.z - at.y) < 0.0001:
			found.append(snappedf(v.y, 0.0001))
	found.sort()
	return found


func test_the_same_seed_gives_the_same_wall_and_another_seed_another() -> void:
	assert_array(_wall(7).vertices).is_equal(_wall(7).vertices)
	assert_array(_wall(7).vertices).is_not_equal(_wall(8).vertices)


func test_both_ends_are_pinned_whatever_the_seed() -> void:
	for at: Vector3 in [FOOT_A, FOOT_B]:
		var one: Array[float] = _end_heights(_wall(1), at)
		assert_int(one.size()).is_greater(10)
		assert_array(one).is_equal(_end_heights(_wall(99), at))


func test_the_wall_stays_within_its_height_and_the_triangle_cap() -> void:
	var batch: BakeMesh.Batch = _wall(3)
	var tallest: float = 0.0
	for v: Vector3 in batch.vertices:
		tallest = maxf(tallest, v.y)
	assert_float(tallest).is_between(HEIGHT * 0.9, HEIGHT * 1.15)
	assert_int(batch.indices.size() / 3).is_less(BakeMesh.TRIANGLE_CAP)


func test_the_face_looks_away_from_the_tile_centre() -> void:
	var batch: BakeMesh.Batch = _wall(5)
	var outward: int = 0
	for i: int in batch.vertices.size():
		if batch.normals[i].x > 0.5:
			outward += 1
	assert_int(outward).is_greater(100)
