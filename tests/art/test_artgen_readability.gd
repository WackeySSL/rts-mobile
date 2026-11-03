extends GdUnitTestSuite
## What the generated blockouts look like when rasterised (plan row P99, svg-art-style "Drawing
## rules"): every frame is a valid picture of the size its canvas says, the default view of every
## type (d06 for the Derrick League, d10 for the Lumen Accord, the one view of a building) has a
## team zone of a few percent of its pixels and no more than a fifth (that it is not a roof plate
## is test_artgen_plates.gd), and shrunk to 32 px in greyscale it still has a body and a spread of
## tones, so it can be told from the ground. The look itself is the gallery's, on Michael's phone.

const SCALE: float = 0.5  ## 2x art at zoom 1: one tile is 64 px.
const SIDE_PX: int = 32
const TEAM_SHARE: Vector2 = Vector2(0.03, 0.2)
const MIN_SPREAD: float = 80.0  ## Luminance, 5th to 95th percentile, 0 to 255.
const MIN_BODY_PX: int = 150
const KEY_TOLERANCE: float = 0.06  ## Summed difference of the three channels in 0 to 1.
const PAGE: Vector2i = Vector2i(320, 320)
const GROUND_POINT: Vector2i = Vector2i(160, 200)

var _fresh: Dictionary[String, String] = {}


func before() -> void:
	_fresh = ArtGen.build_all()


func test_every_frame_is_a_picture_of_the_size_its_canvas_says() -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var layouts: Dictionary[StringName, ArtGen.Layout] = ArtGen.layouts(model)
		for part: StringName in layouts:
			for dir: int in model.directions(part):
				for frame: int in model.frames(part):
					var image: Image = _raster(model, part, dir, frame)
					var layout: ArtGen.Layout = layouts[part]
					(
						assert_vector(Vector2(image.get_size()))
						. override_failure_message(path)
						. is_equal(Vector2(layout.size) * SCALE)
					)
					(
						assert_bool(image.get_used_rect().size.x > 0)
						. override_failure_message(path)
						. is_true()
					)


func test_the_default_view_of_every_type_has_a_team_share_of_3_to_20_percent() -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var picture: Image = _default_picture(model)
		var keys: Array[Color] = []
		for hex: String in ArtPalette.KEYS[model.faction]:
			keys.append(Color(hex))
		var team: int = 0
		var body: int = 0
		for y: int in picture.get_height():
			for x: int in picture.get_width():
				var pixel: Color = picture.get_pixel(x, y)
				if pixel.a < 0.95:
					continue
				body += 1
				for key: Color in keys:
					if (
						absf(pixel.r - key.r) + absf(pixel.g - key.g) + absf(pixel.b - key.b)
						< KEY_TOLERANCE
					):
						team += 1
						break
		var share: float = float(team) / body
		(
			assert_float(share)
			. override_failure_message("%s team share %.3f" % [path, share])
			. is_between(TEAM_SHARE.x, TEAM_SHARE.y)
		)


func test_the_default_view_of_every_type_is_identifiable_at_32_px_in_greyscale() -> void:
	for path: String in ArtGen.model_paths():
		_assert_identifiable(path, _default_picture(load(path) as ArtModel))


## A pose frame is as identifiable as the standing figure (plan row P139): the legs and the head
## move, the body stays a body of tones, in every direction and every frame of a squad.
func test_every_walk_and_idle_frame_is_identifiable_at_32_px_in_greyscale() -> void:
	var seen: int = 0
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var layouts: Dictionary[StringName, ArtGen.Layout] = ArtGen.layouts(model)
		for part: StringName in model.pose_parts():
			if part not in [&"walk", &"idle"]:
				continue
			for dir: int in model.directions(part):
				for frame: int in model.frames(part):
					var picture: Image = Image.create_empty(
						PAGE.x, PAGE.y, false, Image.FORMAT_RGBA8
					)
					_blit(picture, _raster(model, part, dir, frame), layouts[part], Vector2.ZERO)
					_assert_identifiable("%s %s d%02d f%d" % [path, part, dir, frame], picture)
					seen += 1
	assert_int(seen).is_equal(4 * 8 * (4 + 2))


## `picture` shrunk to 32 px in greyscale still has a body and a spread of tones.
func _assert_identifiable(label: String, picture: Image) -> void:
	var box: Rect2i = picture.get_used_rect()
	var small: Image = picture.get_region(box)
	var factor: float = float(SIDE_PX) / maxi(box.size.x, box.size.y)
	small.resize(
		maxi(1, roundi(box.size.x * factor)),
		maxi(1, roundi(box.size.y * factor)),
		Image.INTERPOLATE_LANCZOS
	)
	var grey: Array[float] = []
	for y: int in small.get_height():
		for x: int in small.get_width():
			var pixel: Color = small.get_pixel(x, y)
			if pixel.a > 0.9:
				grey.append((0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b) * 255.0)
	grey.sort()
	assert_int(grey.size()).override_failure_message(label + " body").is_greater_equal(MIN_BODY_PX)
	var spread: float = grey[int(grey.size() * 0.95)] - grey[int(grey.size() * 0.05)]
	(
		assert_float(spread)
		. override_failure_message("%s spread %.0f" % [label, spread])
		. is_greater_equal(MIN_SPREAD)
	)


## The default view of a type on a transparent page: the hull, and the turret or head at its mount.
func _default_picture(model: ArtModel) -> Image:
	var dir: int = 6 if model.faction == &"fossil" else 10
	var picture: Image = Image.create_empty(PAGE.x, PAGE.y, false, Image.FORMAT_RGBA8)
	var layouts: Dictionary[StringName, ArtGen.Layout] = ArtGen.layouts(model)
	_blit(
		picture,
		_raster(model, &"hull", -1 if model.category == &"bld" else dir),
		layouts[&"hull"],
		Vector2.ZERO
	)
	for part: StringName in [&"turret", &"head"]:
		if layouts.has(part):
			var mount: Vector2 = ArtGen.mount_px(model, 6 if model.category == &"bld" else dir)
			_blit(picture, _raster(model, part, dir), layouts[part], mount)
	return picture


## One frame of a part as an image: a pose part's frame `frame`, the one frame of any other.
func _raster(model: ArtModel, part: StringName, dir: int, frame: int = -1) -> Image:
	var at: int = frame if model.frames(part) > 1 else -1
	var image: Image = Image.new()
	image.load_svg_from_string(_fresh[ArtGen.frame_path(model, part, dir, at)], SCALE)
	return image


func _blit(picture: Image, frame: Image, layout: ArtGen.Layout, offset: Vector2) -> void:
	var at: Vector2i = GROUND_POINT + Vector2i((offset - Vector2(layout.origin)) * SCALE)
	picture.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), at)
