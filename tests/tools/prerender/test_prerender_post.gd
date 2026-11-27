extends GdUnitTestSuite
## tools/prerender/post.py (plan row P656b): its PNGs hold only IHDR, IDAT and IEND, a clipped
## sentinel pixel is refused naming the frame and the count, the box filter and the shadow alpha.
## It runs `python3 -I` with the pins of tools/prerender/requirements.txt; a missing numpy or
## Pillow fails every test (CI installs them in its setup-python step, verify.sh checks them).

const POST: String = "res://tools/prerender/post.py"
const DIR: String = "user://prerender_post"


func _require_python() -> void:
	var output: Array = []
	var code: int = OS.execute("python3", ["-I", "-c", "import numpy, PIL"], output, true)
	(
		assert_int(code)
		. override_failure_message(
			"numpy or Pillow is missing: python3 -m pip install -r tools/prerender/requirements.txt"
		)
		. is_equal(0)
	)


func _raw(name: String, colour: Color, scale: int = 4) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var image: Image = Image.create(3 * scale, 2 * scale, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	image.save_png(DIR.path_join(name))
	var info: FileAccess = FileAccess.open(DIR.path_join("bake_info.json"), FileAccess.WRITE)
	info.store_string('{"scale": %d, "shadow_alpha": 0.35}' % scale)


func _post() -> Dictionary:
	var output: Array = []
	var dir: String = ProjectSettings.globalize_path(DIR)
	var code: int = OS.execute(
		"python3", ["-I", ProjectSettings.globalize_path(POST), dir], output, true
	)
	return {"code": code, "text": "".join(output)}


func after_test() -> void:
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file))
	if DirAccess.dir_exists_absolute(DIR.path_join("post")):
		for file: String in DirAccess.get_files_at(DIR.path_join("post")):
			DirAccess.remove_absolute(DIR.path_join("post").path_join(file))
		DirAccess.remove_absolute(DIR.path_join("post"))


func _chunks(path: String) -> PackedStringArray:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var found: PackedStringArray = PackedStringArray()
	var at: int = 8
	while at < bytes.size():
		found.append(bytes.slice(at + 4, at + 8).get_string_from_ascii())
		at += 12 + _be(bytes, at)
	return found


func _be(b: PackedByteArray, at: int) -> int:
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]


func test_the_output_has_no_time_gamma_icc_or_text_chunk_and_is_1x() -> void:
	_require_python()
	_raw("a_hull.png", Color8(200, 40, 200))
	assert_int(_post().code).is_equal(0)
	var out: String = DIR + "/post/a_hull.png"
	assert_array(_chunks(out)).is_equal(["IHDR", "IDAT", "IEND"])
	var image: Image = Image.load_from_file(out)
	assert_vector(image.get_size()).is_equal(Vector2i(3, 2))
	assert_int(image.get_pixel(0, 0).to_html(false).hex_to_int()).is_equal(0xC828C8)


func test_a_clipped_sentinel_pixel_is_refused_naming_the_frame_and_the_count() -> void:
	_require_python()
	_raw("bad_hull.png", Color8(255, 60, 220))
	var run: Dictionary = _post()
	assert_int(run.code).is_equal(6)
	assert_str(run.text).contains("bad_hull.png: 6 clipped sentinel pixels")
	assert_bool(DirAccess.dir_exists_absolute(DIR + "/post")).is_false()


func test_a_saturated_colour_outside_the_key_band_is_not_refused() -> void:
	_require_python()
	_raw("red_hull.png", Color8(255, 0, 0))
	assert_int(_post().code).is_equal(0)


func test_the_shadow_frame_is_black_at_the_bands_alpha() -> void:
	_require_python()
	_raw("a_shadow.png", Color8(0, 0, 0, 255))
	assert_int(_post().code).is_equal(0)
	var pixel: Color = Image.load_from_file(DIR + "/post/a_shadow.png").get_pixel(1, 1)
	assert_int(pixel.a8).is_equal(89)
	assert_int(pixel.r8 + pixel.g8 + pixel.b8).is_equal(0)
