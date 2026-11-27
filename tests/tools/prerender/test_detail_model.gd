extends GdUnitTestSuite
## The `_detail.tres` schema and reader (plan row P656a, ADR 0053 section 5): a committed fixture
## loads, builds the same triangles every time, mirrors and repeats its parts, and a seeded
## variation that depends on the seed in the data only.

const FIXTURE: String = "res://tests/tools/fixtures/prerender/fixture_box_detail.tres"
const BOX: int = 60  ## A bevelled box: six faces, ten triangles each.
const CYLINDER_8: int = 8 * 8  ## 8 segments, chamfered: eight triangles a segment.


func _built(model: DetailModel, part: StringName) -> BakeMesh:
	var m: BakeMesh = BakeMesh.new(model.art_id)
	model.build(part, m)
	return m


func test_the_fixture_reads_as_a_sound_model() -> void:
	var model: DetailModel = DetailModel.read(FIXTURE)
	assert_object(model).is_not_null()
	assert_array(model.problems()).is_empty()
	assert_array(model.part_names()).contains_exactly([&"hull", &"turret"])
	assert_str(String(model.art_id)).is_equal("fixture_box")


func test_a_part_builds_its_box_and_its_mirrored_repeated_cylinders() -> void:
	var model: DetailModel = DetailModel.read(FIXTURE)
	# One box, then a cylinder mirrored across y and repeated 3 times: 6 cylinders.
	assert_int(_built(model, &"hull").triangles).is_equal(BOX + 6 * CYLINDER_8)
	assert_int(_built(model, &"turret").triangles).is_equal(BOX)


func test_the_same_data_builds_the_same_mesh_and_the_seed_moves_the_jitter() -> void:
	var model: DetailModel = DetailModel.read(FIXTURE)
	var first: BakeMesh.Batch = _built(model, &"hull").batches[&"steel"]
	var again: BakeMesh.Batch = _built(model, &"hull").batches[&"steel"]
	assert_array(first.vertices).is_equal(again.vertices)
	var other: DetailModel = model.duplicate()
	other.variation_seed = model.variation_seed + 1
	var moved: BakeMesh.Batch = _built(other, &"hull").batches[&"steel"]
	assert_array(first.vertices).is_not_equal(moved.vertices)
	assert_int(first.vertices.size()).is_equal(moved.vertices.size())


func test_the_hash_is_a_pure_function_in_the_unit_interval() -> void:
	var seen: Dictionary = {}
	for i: int in 200:
		var h: float = DetailModel.hash01(42, i, i * 3)
		assert_float(h).is_between(0.0, 0.99999999)
		assert_float(DetailModel.hash01(42, i, i * 3)).is_equal(h)
		seen[snappedf(h, 0.01)] = true
	assert_int(seen.size()).is_greater(60)  # spread, not a constant


func test_problems_name_an_unknown_shape_a_missing_material_and_a_zero_count() -> void:
	var model: DetailModel = DetailModel.read(FIXTURE).duplicate(true)
	model.parts[0].shape = &"sphere"
	model.parts[1].material = &"gold"
	model.parts[2].count = 0
	var found: String = "\n".join(model.problems())
	assert_str(found).contains("part 0: unknown shape sphere")
	assert_str(found).contains("part 1: unknown material gold")
	assert_str(found).contains("part 2: count under 1")
