extends GdUnitTestSuite
## The intro art of plan row P520 (ADR 0043 sections 1 and 2): the app icon's two adaptive layers
## split into layer SVGs that composite to the icon, and the boot splash PNG with the AppCode ApS
## wordmark. The layers are rasterised on the CPU (Image.load_svg_from_string, headless) and
## blended with the engine's own float blend.
##
## Composite tolerance (recorded in the plan): every layer is an 8-bit raster of its own, so a
## pixel under several translucent layers rounds a few levels off the one-pass raster. Measured
## over an opaque backdrop (`Image.compute_image_metrics`, per channel): the foreground is at most
## 4 levels off over black and 3 over white (mean 0.021); the background and the whole icon at
## most 5 (mean 0.12, the background being many translucent gradients). The tests allow exactly
## that and a small margin on the means, and each layer's footprint and weight are pinned so a
## dropped thin element cannot hide in the tolerance.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const BRAND_DIR: String = "res://assets/art/brand/"
## The SHA-256 of the brand SVGs as the main lead committed them (P520a), byte for byte.
const BRAND_SHA256: Dictionary[String, String] = {
	"appcode_wordmark_white.svg":
	"cdab9f39198ea504cb04b686393617ce3e8bd2a17d9221353dae8db2dc7ab2af",
	"appcode_mark_white.svg": "5595355e3efedf0100761d75bbf06f4e88f85a7ebc3191ddb66bd878c1b26a97",
}
const MAX_BYTES: int = 28672
const FG_MAX_LEVELS: float = 4.0
const FG_MAX_MEAN: float = 0.025
const BG_MAX_LEVELS: float = 5.0
const BG_MAX_MEAN: float = 0.13
const FULL_MAX_MEAN: float = 0.135
## Each layer over black: its used rect and its mean level (`compute_image_metrics` against black),
## the weight of what it paints. A dropped element changes one of them.
const FOOTPRINT: Dictionary[String, Array] = {
	"sky": [Rect2i(0, 0, 432, 432), 96.0973],
	"ring": [Rect2i(112, 98, 208, 208), 2.1488],
	"sweep": [Rect2i(168, 110, 93, 93), 1.2221],
	"ground": [Rect2i(0, 0, 432, 432), 23.5329],
	"shadow": [Rect2i(96, 209, 241, 100), 0.0220],
	"underlay": [Rect2i(96, 150, 240, 152), 0.8973],
	"track_far": [Rect2i(171, 189, 128, 72), 1.4063],
	"cleats_far": [Rect2i(265, 217, 41, 52), 0.3198],
	"hull": [Rect2i(115, 177, 160, 87), 3.1600],
	"track_near": [Rect2i(98, 197, 91, 92), 0.7616],
	"cleats_near": [Rect2i(147, 236, 51, 64), 0.7376],
	"hull_deck": [Rect2i(100, 182, 209, 115), 0.8197],
	"turret": [Rect2i(137, 153, 97, 52), 1.6949],
	"gun": [Rect2i(208, 172, 126, 43), 1.0614],
	"rim_light": [Rect2i(97, 152, 238, 149), 1.6287],
	"clods": [Rect2i(109, 283, 204, 50), 0.2895],
	"sparks": [Rect2i(84, 226, 254, 106), 0.2142],
}
const MEAN_SLACK: float = 0.01  ## Relative.
const MIN_BRAND_SCAN_FILES: int = 100


func test_the_layers_join_up_and_the_generator_splits_without_problems() -> void:
	var made: Dictionary = ArtIntro.generate()
	assert_array(Array(made["problems"])).is_empty()
	assert_int(Dictionary(made["files"]).size()).is_equal(ArtIntro.order().size())
	assert_int(ArtIntro.order().size()).is_equal(FOOTPRINT.size())


func test_the_folder_holds_exactly_the_layers_and_each_is_what_the_generator_writes() -> void:
	var files: Dictionary = ArtIntro.generate()["files"]
	var want: Array[String] = []
	for stem: String in files:
		var path: String = ArtIntro.LAYER_DIR + stem + ".svg"
		want.append(path)
		assert_str(FileAccess.get_file_as_string(path)).override_failure_message(path).is_equal(
			files[stem]
		)
	want.sort()
	assert_array(FileScan.list_files(ArtIntro.LAYER_DIR.trim_suffix("/"), ".svg")).is_equal(want)


func test_each_layer_opens_with_the_layer_and_silhouette_comments_and_stays_small() -> void:
	for stem: String in ArtIntro.order():
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


func test_the_cleats_and_the_radar_are_layers_of_their_own() -> void:
	var order: Array[String] = ArtIntro.order()
	for stem: String in ["cleats_far", "cleats_near", "ring", "sweep"]:
		assert_bool(order.has(stem)).override_failure_message(stem).is_true()
	# The sky is under the ring and the ground over it: the order is what the icon paints.
	assert_int(order.find("sky")).is_less(order.find("ring"))
	assert_int(order.find("sweep")).is_less(order.find("ground"))
	assert_int(order.find("ground")).is_less(order.find("shadow"))


func test_the_foreground_layers_composite_to_icon_foreground_within_the_tolerance() -> void:
	var want: Image = ArtIntro.raster_text(FileAccess.get_file_as_string(ArtIntro.FOREGROUND), 1.0)
	var got: Image = _stack(ArtIntro.order().slice(ArtIntro.BACKGROUND_LAYERS.size()))
	for backdrop: Color in [Color.BLACK, Color.WHITE]:
		var metrics: Dictionary = _over(want, backdrop).compute_image_metrics(
			_over(got, backdrop), false
		)
		assert_float(metrics["max"]).override_failure_message(str(backdrop)).is_less_equal(
			FG_MAX_LEVELS
		)
		assert_float(metrics["mean"]).override_failure_message(str(backdrop)).is_less_equal(
			FG_MAX_MEAN
		)


func test_the_background_layers_composite_to_icon_background_within_the_tolerance() -> void:
	var want: Image = ArtIntro.raster_text(FileAccess.get_file_as_string(ArtIntro.BACKGROUND), 1.0)
	var got: Image = _stack(ArtIntro.order().slice(0, ArtIntro.BACKGROUND_LAYERS.size()))
	var metrics: Dictionary = want.compute_image_metrics(_over(got, Color.BLACK), false)
	assert_float(metrics["max"]).is_less_equal(BG_MAX_LEVELS)
	assert_float(metrics["mean"]).is_less_equal(BG_MAX_MEAN)


func test_all_layers_composite_to_the_whole_adaptive_icon_within_the_tolerance() -> void:
	var want: Image = ArtIntro.raster_text(FileAccess.get_file_as_string(ArtIntro.BACKGROUND), 1.0)
	var front: Image = ArtIntro.raster_text(FileAccess.get_file_as_string(ArtIntro.FOREGROUND), 1.0)
	want.blend_rect(front, Rect2i(0, 0, 432, 432), Vector2i.ZERO)
	var metrics: Dictionary = want.compute_image_metrics(
		_over(_stack(ArtIntro.order()), Color.BLACK), false
	)
	assert_float(metrics["max"]).is_less_equal(BG_MAX_LEVELS)
	assert_float(metrics["mean"]).is_less_equal(FULL_MAX_MEAN)


func test_each_layers_footprint_and_weight_are_pinned() -> void:
	for stem: String in FOOTPRINT:
		var image: Image = ArtIntro.raster_text(
			FileAccess.get_file_as_string(ArtIntro.LAYER_DIR + stem + ".svg"), 1.0
		)
		assert_object(image.get_used_rect()).override_failure_message(stem).is_equal(
			FOOTPRINT[stem][0]
		)
		var black: Image = Image.create(432, 432, false, Image.FORMAT_RGBA8)
		black.fill(Color.BLACK)
		var weight: float = _over(image, Color.BLACK).compute_image_metrics(black, false)["mean"]
		var pinned: float = FOOTPRINT[stem][1]
		assert_float(weight).override_failure_message(stem).is_equal_approx(
			pinned, pinned * MEAN_SLACK + 0.0001
		)


func test_the_splitter_reports_what_it_cannot_carry_over() -> void:
	var defs: String = '<defs><linearGradient id="a"><stop offset="0"/></linearGradient>'
	var tail: String = "</defs>"
	var layers: Array[Dictionary] = [{"name": "x", "from": 1, "to": 2, "what": "w", "shape": "s"}]
	# A clean group splits.
	var head: String = '<svg>%s<clipPath id="fc"><rect/></clipPath>%s'
	var clean: String = head + '<g><rect/><path d="M0 0"/></g></svg>'
	var good: Dictionary = ArtIntro.split(clean % [defs, tail], layers, true, "foreground", "t.svg")
	assert_array(Array(good["problems"])).is_empty()
	# An element that is not self-closing.
	var open: String = clean.replace("<rect/>", "<text>a</text>")
	var bad: Dictionary = ArtIntro.split(open % [defs, tail], layers, true, "foreground", "t.svg")
	assert_int(Array(bad["problems"]).size()).is_greater(0)
	assert_bool(Dictionary(bad["files"]).is_empty()).is_true()
	# A layer that ends inside a nested group.
	var nested: String = head + "<g><g><rect/></g><rect/></g></svg>"
	var inside: Array[Dictionary] = [{"name": "x", "from": 1, "to": 2, "what": "w", "shape": "s"}]
	var cut: Dictionary = ArtIntro.split(nested % [defs, tail], inside, true, "foreground", "t.svg")
	assert_int(Array(cut["problems"]).size()).is_greater(0)
	# A layer run with a gap.
	var gap: Array[Dictionary] = [{"name": "x", "from": 2, "to": 2, "what": "w", "shape": "s"}]
	var gapped: Dictionary = ArtIntro.split(clean % [defs, tail], gap, true, "foreground", "t.svg")
	assert_int(Array(gapped["problems"]).size()).is_greater(0)
	# A def that refers to another, one that is missing and one that is no gradient.
	var linked: String = defs.replace('<stop offset="0"/>', '<stop offset="0" href="#b"/>')
	var one: Array[Dictionary] = [{"name": "x", "from": 0, "to": 0, "what": "w", "shape": "s"}]
	var flat: String = '<svg>%s%s<rect fill="url(#a)"/></svg>'
	var refers: Dictionary = ArtIntro.split(
		flat % [linked, tail], one, false, "background", "t.svg"
	)
	assert_int(Array(refers["problems"]).size()).is_greater(0)
	var missing: Dictionary = ArtIntro.split(
		(flat % [defs, tail]).replace("#a", "#zz"), one, false, "background", "t.svg"
	)
	assert_int(Array(missing["problems"]).size()).is_greater(0)
	var odd: Dictionary = ArtIntro.split(
		flat % [defs + '<mask id="m"/>', tail], one, false, "background", "t.svg"
	)
	assert_int(Array(odd["problems"]).size()).is_greater(0)


func test_the_brand_svgs_are_the_main_leads_files_unmodified() -> void:
	for file_name: String in BRAND_SHA256:
		var path: String = BRAND_DIR + file_name
		assert_str(FileAccess.get_sha256(path)).override_failure_message(path).is_equal(
			BRAND_SHA256[file_name]
		)


func test_the_brand_textures_are_never_loaded_at_runtime() -> void:
	# They import at 2048 px: only the baked splash PNG may be referenced by the game. The intro
	# generator reads the SVG text offline; nothing else in the project, its settings, its tools
	# or its addons may name them.
	var offenders: Array[String] = []
	var scanned: int = 0
	var files: Array[String] = ["res://project.godot", "res://export_presets.cfg"]
	for dir: String in ["game", "scenes", "data", "tools", "addons"]:
		for extension: String in [".gd", ".tscn", ".tres", ".cfg", ".gdextension", ".json"]:
			files.append_array(FileScan.list_files("res://" + dir, extension))
	for path: String in files:
		if path == "res://tools/artgen/ArtIntro.gd":
			continue
		scanned += 1
		var text: String = FileAccess.get_file_as_string(path)
		if path == "res://export_presets.cfg":
			# An exclude_filter line may name the brand folder (it keeps it out of every pack);
			# any other line naming it (an include, a launcher icon) is a runtime use.
			var kept: PackedStringArray = []
			for line: String in text.split("\n"):
				if not line.begins_with("exclude_filter="):
					kept.append(line)
			text = "\n".join(kept)
		if text.contains("art/brand/"):
			offenders.append(path)
	assert_int(scanned).is_greater(MIN_BRAND_SCAN_FILES)
	assert_array(offenders).is_empty()


func test_the_splash_png_is_exactly_what_the_generator_renders() -> void:
	var made: Image = ArtIntro.splash()
	var saved: Image = _splash()
	saved.convert(Image.FORMAT_RGB8)
	assert_vector(saved.get_size()).is_equal(made.get_size())
	assert_bool(saved.get_data() == made.get_data()).is_true()


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


func test_the_boot_splash_settings_for_p533_are_godots_keep_mode_and_the_splash_colour() -> void:
	# `Keep` is index 1 of the property's own enum hint in Godot 4.7.2.
	var found: bool = false
	for info: Dictionary in ProjectSettings.get_property_list():
		if info["name"] == "application/boot_splash/stretch_mode":
			found = true
			var modes: PackedStringArray = String(info["hint_string"]).split(",")
			assert_str(modes[ArtIntro.BOOT_SPLASH_STRETCH_KEEP]).is_equal("Keep")
	assert_bool(found).is_true()
	assert_str(ArtIntro.BOOT_SPLASH_SETTINGS["application/boot_splash/bg_color"]).is_equal(
		ArtIntro.SPLASH_BG
	)
	assert_str(ArtIntro.BOOT_SPLASH_SETTINGS["application/boot_splash/image"]).is_equal(
		ArtIntro.SPLASH_PATH
	)


func test_one_lockup_fits_all_six_sizes_by_their_aspect_and_dp() -> void:
	var rects: Dictionary[String, Rect2i] = ArtIntro.lockup(ArtIntro.wordmark_size())
	assert_int(ScreenSizes.ALL.size()).is_equal(6)
	for size: Vector2i in ScreenSizes.ALL:
		var m: UiMetrics = _profile(size)
		(
			assert_bool(ArtIntro.fits(rects, size, UiScale.window_px_per_dp(m)))
			. override_failure_message("%s %s" % [size, m.os_name])
			. is_true()
		)
	# The phone with its notch insets: the lockup stays inside the safe area.
	for notch: UiMetrics in UiProfiles.notch_design().values():
		(
			assert_bool(
				ArtIntro.fits(
					rects, notch.window_size, UiScale.window_px_per_dp(notch), notch.safe_area
				)
			)
			. is_true()
		)


func test_a_wordmark_too_small_fails_only_the_sizes_where_it_is_too_small_in_dp() -> void:
	# 12 px of 1024: 4.8 dp on the 420 dpi phone (both ways), 8.4 dp on the 96 dpi desktop and
	# 9 dp on the 4:3 tablet, against a floor of 8 dp.
	var small: Dictionary[String, Rect2i] = ArtIntro.lockup(Vector2i(154, 12))
	var failing: Array[Vector2i] = []
	for size: Vector2i in ScreenSizes.ALL:
		if not ArtIntro.fits(small, size, UiScale.window_px_per_dp(_profile(size))):
			failing.append(size)
	failing.sort()
	var want: Array[Vector2i] = [Vector2i(1080, 2400), Vector2i(2400, 1080)]
	assert_array(failing).is_equal(want)
	# A lockup that does not lie inside the safe area does not fit.
	var rects: Dictionary[String, Rect2i] = ArtIntro.lockup(ArtIntro.wordmark_size())
	assert_bool(ArtIntro.fits(rects, Vector2i(1280, 720), 1.0, Rect2i(0, 0, 300, 300))).is_false()


## The layers `stems` painted over one another in float on a transparent square.
func _stack(stems: Array[String]) -> Image:
	var got: Image = Image.create(432, 432, false, Image.FORMAT_RGBAF)
	for stem: String in stems:
		var layer: Image = ArtIntro.raster_text(
			FileAccess.get_file_as_string(ArtIntro.LAYER_DIR + stem + ".svg"), 1.0
		)
		layer.convert(Image.FORMAT_RGBAF)
		got.blend_rect(layer, Rect2i(0, 0, 432, 432), Vector2i.ZERO)
	return got


## `image` over an opaque `backdrop`, as 8-bit RGBA.
func _over(image: Image, backdrop: Color) -> Image:
	var base: Image = Image.create(432, 432, false, Image.FORMAT_RGBAF)
	base.fill(backdrop)
	var top: Image = image.duplicate()
	top.convert(Image.FORMAT_RGBAF)
	base.blend_rect(top, Rect2i(0, 0, 432, 432), Vector2i.ZERO)
	base.convert(Image.FORMAT_RGBA8)
	return base


## The profile whose window is `size`: of the six, the landscape and portrait ones.
func _profile(size: Vector2i) -> UiMetrics:
	var all: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	all.merge(UiProfiles.portrait())
	for m: UiMetrics in all.values():
		if m.window_size == size:
			return m
	fail("no profile for %s" % size)
	return null


func _splash() -> Image:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(ArtIntro.SPLASH_PATH))
	assert_object(image).is_not_null()
	image.convert(Image.FORMAT_RGBA8)
	return image
