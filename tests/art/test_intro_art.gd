extends GdUnitTestSuite
## The intro art of plan row P520 (ADR 0043 sections 1 and 2): the app icon's foreground split into
## layer SVGs that composite to the icon, and the boot splash PNG with the AppCode ApS wordmark.
## The layers are rasterised on the CPU (Image.load_svg_from_string, headless) and blended here.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const FOREGROUND: String = "res://assets/art/svg/icon/icon_foreground.svg"
const BRAND_DIR: String = "res://assets/art/brand/"
## The SHA-256 of the brand SVGs as the main lead committed them (P520a), byte for byte.
const BRAND_SHA256: Dictionary[String, String] = {
	"appcode_wordmark_white.svg":
	"cdab9f39198ea504cb04b686393617ce3e8bd2a17d9221353dae8db2dc7ab2af",
	"appcode_mark_white.svg": "5595355e3efedf0100761d75bbf06f4e88f85a7ebc3191ddb66bd878c1b26a97",
}
const LAYER_COUNT: int = 10
const MAX_BYTES: int = 28672
## The layers are 8-bit rasters of their own, so a pixel under several of them with partial alpha
## (an anti-aliased edge) can come out a few levels off the one-pass raster: no pixel more than
## `MAX_LEVELS` off, and at most `MAX_OFF_SHARE` of all pixels more than one whole level off.
const MAX_LEVELS: float = 5.0
const MAX_OFF_SHARE: float = 0.005


func test_the_layers_join_up_over_every_element_of_the_foreground() -> void:
	assert_int(ArtIntro.LAYERS.size()).is_equal(LAYER_COUNT)
	# Tag 0 opens the clipped group and the last tag closes it; every tag between is in a layer.
	assert_int(ArtIntro.covered()).is_equal(ArtIntro.tag_count() - 1)


func test_the_folder_holds_exactly_the_layers_and_each_is_what_the_generator_writes() -> void:
	var layers: Dictionary[String, String] = ArtIntro.layers()
	var want: Array[String] = []
	for stem: String in layers:
		var path: String = ArtIntro.LAYER_DIR + stem + ".svg"
		want.append(path)
		assert_str(FileAccess.get_file_as_string(path)).override_failure_message(path).is_equal(
			layers[stem]
		)
	want.sort()
	assert_array(FileScan.list_files(ArtIntro.LAYER_DIR.trim_suffix("/"), ".svg")).is_equal(want)


func test_each_layer_opens_with_the_layer_and_silhouette_comments_and_stays_small() -> void:
	for stem: String in ArtIntro.layers():
		var text: String = FileAccess.get_file_as_string(ArtIntro.LAYER_DIR + stem + ".svg")
		var lines: PackedStringArray = text.split("\n")
		assert_str(lines[0]).override_failure_message(stem).starts_with("<!-- ")
		assert_str(lines[1]).override_failure_message(stem).starts_with("<!-- Silhouette: ")
		(
			assert_str(lines[2])
			. override_failure_message(stem)
			. is_equal(
				'<svg xmlns="http://www.w3.org/2000/svg" width="432" height="432" viewBox="0 0 432 432">'
			)
		)
		assert_int(text.to_utf8_buffer().size()).override_failure_message(stem).is_less_equal(
			MAX_BYTES
		)


func test_the_layers_composite_to_the_icon_foreground_within_one_level_but_for_edge_pixels(
) -> void:
	var want: Image = ArtIntro.raster_text(FileAccess.get_file_as_string(FOREGROUND), 1.0)
	# The blend runs in floats on premultiplied colour, so only the layers' own 8-bit rasters count.
	var got: PackedFloat32Array = PackedFloat32Array()
	got.resize(432 * 432 * 4)
	for layer: Dictionary in ArtIntro.LAYERS:
		var text: String = FileAccess.get_file_as_string(
			ArtIntro.LAYER_DIR + String(layer["name"]) + ".svg"
		)
		var image: Image = ArtIntro.raster_text(text, 1.0)
		assert_vector(image.get_size()).is_equal(Vector2i(432, 432))
		var data: PackedByteArray = image.get_data()
		for i: int in range(0, data.size(), 4):
			var alpha: float = data[i + 3] / 255.0
			for c: int in 3:
				got[i + c] = data[i + c] * alpha + got[i + c] * (1.0 - alpha)
			got[i + 3] = 255.0 * alpha + got[i + 3] * (1.0 - alpha)
	var worst: float = 0.0
	var bad: int = 0
	var base: PackedByteArray = want.get_data()
	for i: int in range(0, base.size(), 4):
		var alpha: float = base[i + 3] / 255.0
		# Compared premultiplied: a colour under (almost) no alpha is not seen.
		var diff: float = absf(base[i + 3] - got[i + 3])
		for c: int in 3:
			diff = maxf(diff, absf(base[i + c] * alpha - got[i + c]))
		worst = maxf(worst, diff)
		if diff > 1.5:
			bad += 1
	assert_float(worst).is_less_equal(MAX_LEVELS)
	assert_int(bad).override_failure_message("%d pixels over one level" % bad).is_less(
		int(432 * 432 * MAX_OFF_SHARE)
	)


func test_the_brand_svgs_are_the_main_leads_files_unmodified() -> void:
	for file_name: String in BRAND_SHA256:
		var path: String = BRAND_DIR + file_name
		assert_str(FileAccess.get_sha256(path)).override_failure_message(path).is_equal(
			BRAND_SHA256[file_name]
		)


func test_the_brand_textures_are_never_loaded_at_runtime() -> void:
	# They import at 2048 px: only the baked splash PNG may be referenced by the game.
	var offenders: Array[String] = []
	for extension: String in [".gd", ".tscn", ".tres"]:
		for dir: String in ["res://game", "res://scenes", "res://data"]:
			for path: String in FileScan.list_files(dir, extension):
				if FileAccess.get_file_as_string(path).contains("art/brand/"):
					offenders.append(path)
	assert_array(offenders).is_empty()


func test_the_splash_png_is_the_square_on_its_background_colour() -> void:
	var image: Image = _splash()
	assert_vector(image.get_size()).is_equal(Vector2i(ArtIntro.SPLASH_SIDE, ArtIntro.SPLASH_SIDE))
	var background: Color = Color.html(ArtIntro.SPLASH_BG)
	for corner: Vector2i in [
		Vector2i(0, 0), Vector2i(1023, 0), Vector2i(0, 1023), Vector2i(1023, 1023)
	]:
		assert_bool(image.get_pixelv(corner).is_equal_approx(background)).is_true()
	# The icon sits in the middle at 1:1: its centre is the icon's centre, rendered.
	var rects: Dictionary[String, Rect2i] = ArtIntro.lockup(ArtIntro.wordmark_size())
	var icon: Image = ArtIntro.raster_text(FileAccess.get_file_as_string(ArtIntro.ICON), 1.0)
	var at: Vector2i = rects["icon"].position
	for probe: Vector2i in [Vector2i(256, 256), Vector2i(40, 300), Vector2i(470, 200)]:
		assert_bool(image.get_pixelv(at + probe).is_equal_approx(icon.get_pixelv(probe))).is_true()


func test_the_wordmark_is_white_and_30_percent_of_the_icons_width_under_it() -> void:
	var size: Vector2i = ArtIntro.wordmark_size()
	assert_int(size.x).is_between(int(512 * 0.29), int(512 * 0.31) + 1)
	var rects: Dictionary[String, Rect2i] = ArtIntro.lockup(size)
	var icon: Rect2i = rects["icon"]
	var word: Rect2i = rects["wordmark"]
	assert_int(word.position.y).is_greater_equal(icon.end.y)
	assert_int(word.get_center().x).is_equal(icon.get_center().x)
	var image: Image = _splash()
	var white: int = 0
	var other: int = 0
	var background: Color = Color.html(ArtIntro.SPLASH_BG)
	for y: int in range(word.position.y, word.end.y):
		for x: int in range(word.position.x, word.end.x):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.is_equal_approx(Color.WHITE):
				white += 1
			elif not pixel.is_equal_approx(background):
				other += 1
	assert_int(white).is_greater(100)
	# Anti-aliased edges are the only pixels that are neither: they are a minority of the ink.
	assert_int(other).is_less(white * 2)


func test_one_lockup_fits_all_six_sizes_so_no_second_layout_is_needed() -> void:
	var rects: Dictionary[String, Rect2i] = ArtIntro.lockup(ArtIntro.wordmark_size())
	assert_int(ScreenSizes.ALL.size()).is_equal(6)
	for size: Vector2i in ScreenSizes.ALL:
		assert_bool(ArtIntro.fits(rects, size)).override_failure_message(str(size)).is_true()
	# The check is not vacuous: a lockup twice as tall under the icon does not fit the shortest.
	var tall: Dictionary[String, Rect2i] = ArtIntro.lockup(Vector2i(154, 400))
	assert_bool(ArtIntro.fits(tall, Vector2i(1280, 720))).is_false()


func _splash() -> Image:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(ArtIntro.SPLASH_PATH))
	assert_object(image).is_not_null()
	image.convert(Image.FORMAT_RGBA8)
	return image
