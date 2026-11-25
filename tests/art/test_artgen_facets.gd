extends GdUnitTestSuite
## The facet primitives of P630c (ADR 0050 sections 1 and 2): `chamfer=` on a box or wedge and
## `turn=` on a prism. The shipped models use neither (`gen-art.sh --check` is the proof that no
## frame changed); `tests/art/fixtures/facets/facet_hall.tres` is the test model of the form.

const HALL: String = "res://tests/art/fixtures/facets/facet_hall.tres"
const BUILDING_3X3_BYTES: int = 128 * 1024
const BUILDING_3X3_POLYGONS: int = 1500


func _hall() -> ArtModel:
	return load(HALL) as ArtModel


func test_the_hall_is_a_valid_model_and_outside_the_game_art() -> void:
	assert_array(_hall().problems()).is_empty()
	var index: IsoIndex = load(IsoIndex.PATH) as IsoIndex
	assert_object(index.sheet(&"facet_hall_fixture")).is_null()


func test_a_chamfered_box_has_eight_sides_a_top_and_a_bottom_with_outward_normals() -> void:
	var prim: ArtPrim = ArtPrim.parse("box hull steel 0 0 0 2 1 0.5 chamfer=0.25")
	var faces: Array[ArtMesh.Face] = ArtMesh.faces(prim)
	assert_int(faces.size()).is_equal(10)
	var diagonals: int = 0
	var middle: Vector3 = Vector3(0, 0, 0.25)
	for face: ArtMesh.Face in faces:
		assert_float(face.normal.length()).is_equal_approx(1.0, 1e-6)
		var mean: Vector3 = Vector3.ZERO
		for point: Vector3 in face.points:
			mean += point / face.points.size()
			assert_float(absf(point.x)).is_less_equal(1.0 + 1e-6)
			assert_float(absf(point.y)).is_less_equal(0.5 + 1e-6)
		assert_float(face.normal.dot(mean - middle)).is_greater(0.0)
		if absf(face.normal.x) > 0.5 and absf(face.normal.y) > 0.5:
			diagonals += 1
			assert_float(absf(face.normal.x)).is_equal_approx(sqrt(0.5), 1e-6)
			assert_float(face.normal.z).is_equal_approx(0.0, 1e-6)
	assert_int(diagonals).is_equal(4)
	# The top is an octagon of the box's own height.
	assert_int(faces[8].points.size()).is_equal(8)
	assert_float(faces[8].normal.z).is_equal_approx(1.0, 1e-6)


func test_a_chamfer_cuts_each_corner_by_c_along_both_sides() -> void:
	var faces: Array[ArtMesh.Face] = ArtMesh.faces(
		ArtPrim.parse("box hull steel 0 0 0 2 1 0.5 chamfer=0.25")
	)
	var top: ArtMesh.Face = faces[8]
	var seen: Dictionary[Vector2, bool] = {}
	for point: Vector3 in top.points:
		seen[Vector2(snappedf(point.x, 0.001), snappedf(point.y, 0.001))] = true
	for want: Vector2 in [Vector2(1, 0.25), Vector2(0.75, 0.5), Vector2(-0.75, -0.5)]:
		assert_bool(seen.has(want)).override_failure_message(str(want)).is_true()
	assert_float(ArtPrim.parse("box hull steel 0 0 0 2 1 0.5 chamfer=0.25").aabb().size.x).is_equal(
		2.0
	)


func test_a_turned_prism_turns_its_side_normals_and_a_zero_turn_changes_nothing() -> void:
	var plain: ArtPrim = ArtPrim.parse("prism hull steel 0 0 0 1 1 1 sides=6")
	var zero: ArtPrim = ArtPrim.parse("prism hull steel 0 0 0 1 1 1 sides=6 turn=0")
	var turned: ArtPrim = ArtPrim.parse("prism hull steel 0 0 0 1 1 1 sides=6 turn=30")
	for i: int in 6:
		assert_vector(ArtMesh.faces(zero)[i].normal).is_equal(ArtMesh.faces(plain)[i].normal)
		var normal: Vector3 = ArtMesh.faces(plain)[i].normal
		var spun: Vector3 = ArtMesh.faces(turned)[i].normal
		var step: float = rad_to_deg(Vector2(normal.x, normal.y).angle_to(Vector2(spun.x, spun.y)))
		assert_float(step).is_equal_approx(30.0, 1e-4)
	# The box of a turned hexagon allows for its points.
	assert_float(turned.aabb().size.x).is_not_equal(plain.aabb().size.x)


func test_bad_values_are_refused_by_the_primitive_and_the_model() -> void:
	for line: String in [
		"box hull steel 0 0 0 2 1 0.5 chamfer=0",
		"box hull steel 0 0 0 2 1 0.5 chamfer=-0.1",
		"box hull steel 0 0 0 2 1 0.5 chamfer=0.5",
		"box hull steel 0 0 0 2 1 0.5 chamfer=x",
		"prism hull steel 0 0 0 1 1 1 chamfer=0.1",
		"sphere hull steel 0 0 0 1 1 1 chamfer=0.1",
		"box hull steel 0 0 0 1 1 1 turn=30",
		"prism hull steel 0 0 0 1 1 1 turn=361",
		"prism hull steel 0 0 0 1 1 1 turn=x",
	]:
		assert_object(ArtPrim.parse(line)).override_failure_message(line).is_null()
		var model: ArtModel = _hall().duplicate() as ArtModel
		model.prims = PackedStringArray([line, "box hull ceramic 0 0 0 1 1 1"])
		assert_array(model.problems()).override_failure_message(line).is_not_empty()
	assert_object(ArtPrim.parse("box hull steel 0 0 0 2 1 0.5 chamfer=0.49")).is_not_null()
	assert_object(ArtPrim.parse("wedge hull steel 0 0 0 2 1 0.5 chamfer=0.2")).is_not_null()


func test_the_hall_holds_the_same_scene_bands_at_zoom_1() -> void:
	var bands: SameSceneBands = SameScene.load_bands()
	var sprite: SameScene.Sprite = _hall_sprite(bands)
	var measured: Dictionary = SameScene.measure(sprite)
	var misses: PackedStringArray = SameScene.problems("facet_hall", measured, bands)
	assert_array(misses).override_failure_message("%s\n%s" % [measured, misses]).is_empty()


func test_every_face_of_the_hall_is_one_of_its_materials_three_tones_at_every_yaw() -> void:
	var model: ArtModel = _hall()
	var prims: Array[ArtPrim] = model.primitives(&"hull")
	var faces: int = 0
	for dir: int in 16:
		for poly: ArtRender.Poly in ArtRender.render(prims, dir * 22.5, model.faction):
			var material: StringName = prims[poly.prim].material
			var tones: Array[String] = []
			for level: int in [ArtPalette.TOP, ArtPalette.LEFT, ArtPalette.RIGHT]:
				tones.append(ArtPalette.tone(model.faction, material, level))
			assert_bool(poly.fill in tones).override_failure_message(str(material)).is_true()
			faces += 1
	assert_int(faces).is_greater(16 * 20)


## The hall as `SameScene.sprite` lays a building out (hull and shadow on one canvas, 2x art at
## zoom 1.0), from frames built in memory: the fixture has no files and is not in the index.
func _hall_sprite(bands: SameSceneBands) -> SameScene.Sprite:
	var files: Dictionary[String, String] = ArtGen.build(_hall())
	var sheet_text: String = ""
	for path: String in files:
		if path.ends_with("_sheet.tres") and "/facet_hall_fixture" in path:
			sheet_text = files[path]
	DirAccess.make_dir_recursive_absolute("user://facet_hall")
	var file: FileAccess = FileAccess.open("user://facet_hall/sheet.tres", FileAccess.WRITE)
	file.store_string(sheet_text)
	file.close()
	var sheet: IsoSheetDef = (
		ResourceLoader.load("user://facet_hall/sheet.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
		as IsoSheetDef
	)
	assert_object(sheet).is_not_null()
	var scale: float = SameScene.ART_SCALE
	var union: Rect2 = Rect2()
	for part: StringName in [&"shadow", &"hull"]:
		var rect: Rect2 = Rect2(-Vector2(sheet.origin(part)), sheet.frame_size(part))
		union = rect if union.size == Vector2.ZERO else union.merge(rect)
	var out: SameScene.Sprite = SameScene.Sprite.new()
	out.id = &"facet_hall_fixture"
	var size: Vector2i = Vector2i((union.size * scale).ceil()) + Vector2i.ONE
	out.body = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	out.shadow = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	out.ground = Vector2i(-union.position * scale)
	for part: StringName in [&"shadow", &"hull"]:
		var image: Image = Image.new()
		image.load_svg_from_string(files[sheet.path(part, -1)], scale)
		var at: Vector2i = Vector2i((-Vector2(sheet.origin(part)) - union.position) * scale)
		var target: Image = out.shadow if part == &"shadow" else out.body
		target.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)
	assert_object(bands).is_not_null()
	return out


func test_the_hall_builds_every_frame_inside_the_3x3_budget() -> void:
	var files: Dictionary[String, String] = ArtGen.build(_hall())
	var hull: int = 0
	for path: String in files:
		if (
			path.ends_with(".svg")
			and "/facet_hall_fixture" in path
			and "_shadow" not in path
			and "_sheet" not in path
		):
			hull += 1
			assert_int(files[path].length()).override_failure_message(path).is_less(
				BUILDING_3X3_BYTES
			)
			assert_int(files[path].count("<polygon")).override_failure_message(path).is_less(
				BUILDING_3X3_POLYGONS
			)
	assert_int(hull).is_greater(0)
