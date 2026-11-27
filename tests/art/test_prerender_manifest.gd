extends GdUnitTestSuite
## The pre-render manifest (plan row P656b, ADR 0053 sections 5 and 7), headless. The real
## manifest is empty until the first art row and must pass. The failure cases use a manifest built
## in code over a tiny fixture frame (a shaded box, made by tools/prerender/post.py from a
## code-built shape, not art) and copies of it under user://.

const FIXTURE: String = "res://tests/art/fixtures/prerender/fixture_box_hull.png"
const MODEL: String = "res://tests/tools/fixtures/prerender/fixture_box_detail.tres"
const DIR: String = "user://prerender_manifest"
const SHEET: String = DIR + "/fixture_box_sheet.tres"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var sheet: IsoSheetDef = _sheet(Vector2i(24, 16), 1)
	ResourceSaver.save(sheet, SHEET)


func after_test() -> void:
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file))


func _sheet(canvas: Vector2i, footprint: int) -> IsoSheetDef:
	var sheet: IsoSheetDef = IsoSheetDef.new()
	sheet.art_id = &"fixture_box"
	sheet.footprint = footprint
	sheet.parts = PackedStringArray(["hull"])
	sheet.sizes = PackedInt32Array([canvas.x, canvas.y])
	sheet.anchors = PackedInt32Array([0, 0])
	return sheet


func _load_sheet(path: String) -> IsoSheetDef:
	return load(path) as IsoSheetDef


func _copy(name: String, bytes: PackedByteArray = PackedByteArray()) -> String:
	var path: String = DIR.path_join(name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes if not bytes.is_empty() else FileAccess.get_file_as_bytes(FIXTURE))
	return path


func _manifest(png: String, sources: PackedStringArray = [SHEET, MODEL]) -> ArtManifest:
	var m: ArtManifest = ArtManifest.new()
	m.add(png, sources, 1.0)
	return m


func _noise_png(w: int, h: int) -> PackedByteArray:
	var raw: PackedByteArray = Crypto.new().generate_random_bytes(w * h * 4)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, raw).save_png_to_buffer()


func test_the_committed_manifest_passes_and_is_empty_until_the_first_art_row() -> void:
	var m: ArtManifest = ArtManifest.read()
	assert_str(m.stamp).contains("Forward+").contains("Mesa 25.2.8-0ubuntu0.24.04.5")
	assert_array(m.problems(ArtManifest.OWNED, _load_sheet)).is_empty()


func test_a_listed_fixture_matches_its_line() -> void:
	var png: String = _copy("fixture_box_hull.png")
	var m: ArtManifest = _manifest(png)
	assert_array(m.problems([], _load_sheet)).is_empty()
	var f: PackedStringArray = m.entries[0].split("|")
	assert_str(f[3]).is_equal("24x16")
	assert_int(int(f[2])).is_equal(FileAccess.get_file_as_bytes(FIXTURE).size())


func test_a_changed_png_fails_on_hash_and_bytes() -> void:
	var png: String = _copy("fixture_box_hull.png")
	var m: ArtManifest = _manifest(png)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(png)
	bytes.append(0)
	_copy("fixture_box_hull.png", bytes)
	assert_array(m.problems([], _load_sheet)).contains(
		["%s: hash or bytes differ from the manifest" % png]
	)


func test_a_png_under_an_owned_folder_that_is_not_listed_fails() -> void:
	var m: ArtManifest = _manifest(_copy("fixture_box_hull.png"))
	var extra: String = _copy("extra.png")
	assert_array(m.problems([DIR], _load_sheet)).contains(["%s: not in the manifest" % extra])


func test_a_model_whose_hash_moved_fails_and_names_the_id() -> void:
	var source: String = DIR + "/fixture_box_detail.tres"
	_copy("fixture_box_detail.tres", FileAccess.get_file_as_bytes(MODEL))
	var m: ArtManifest = _manifest(_copy("fixture_box_hull.png"), [SHEET, source])
	assert_array(m.problems([], _load_sheet)).is_empty()
	var file: FileAccess = FileAccess.open(source, FileAccess.READ_WRITE)
	file.seek_end()
	file.store_string("\n# edited without a re-bake\n")
	file = null
	var found: PackedStringArray = m.problems([], _load_sheet)
	assert_int(found.size()).is_equal(1)
	assert_str(found[0]).starts_with("fixture_box: source %s moved" % source)


func test_a_frame_off_its_sheets_canvas_at_its_factor_fails() -> void:
	var m: ArtManifest = _manifest(_copy("fixture_box_hull.png"))
	ResourceSaver.save(_sheet(Vector2i(25, 16), 1), SHEET)
	var found: PackedStringArray = m.problems([], func(p: String) -> IsoSheetDef: return load(p))
	assert_str("".join(found)).contains("the sheet's hull canvas at its factor is (25, 16)")


func test_a_frame_over_its_footprints_byte_budget_fails() -> void:
	for pair: Array in [[3, 128 * 1024], [2, 80 * 1024], [1, 48 * 1024]]:
		var png: String = _copy("fixture_box_hull.png", _noise_png(200, 200))
		ResourceSaver.save(_sheet(Vector2i(200, 200), pair[0]), SHEET)
		var m: ArtManifest = _manifest(png)
		var over: bool = FileAccess.get_file_as_bytes(png).size() > pair[1]
		var found: PackedStringArray = m.problems(
			[], func(p: String) -> IsoSheetDef: return load(p)
		)
		assert_bool("".join(found).contains("over the budget of %d" % pair[1])).is_equal(over)
		assert_bool(over).is_true()


func test_a_kit_over_five_megabytes_fails_and_a_smaller_one_passes() -> void:
	var png: String = _copy("kit_a.png", _noise_png(1500, 1000))
	var m: ArtManifest = ArtManifest.new()
	m.kit_dir = DIR
	m.add(png, [], 1.0)
	assert_int(FileAccess.get_file_as_bytes(png).size()).is_greater(5 * 1024 * 1024)
	assert_str("".join(m.problems([], _load_sheet))).contains("the kit is")
	m.kit_bytes_max = 8 * 1024 * 1024
	assert_array(m.problems([], _load_sheet)).is_empty()


func test_rewriting_the_same_inputs_gives_the_same_bytes() -> void:
	var png: String = _copy("fixture_box_hull.png")
	var m: ArtManifest = _manifest(png)
	m.stamp = "stamp"
	m.save(DIR + "/one.tres")
	m.add(png, [SHEET, MODEL], 1.0)
	m.save(DIR + "/two.tres")
	assert_str(FileAccess.get_sha256(DIR + "/one.tres")).is_equal(
		FileAccess.get_sha256(DIR + "/two.tres")
	)
