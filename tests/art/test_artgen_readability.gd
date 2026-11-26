extends GdUnitTestSuite
## What the generated blockouts look like when rasterised (plan row P99, svg-art-style "Drawing
## rules"): every frame is a valid picture of the size its canvas says, the default view of every
## type (d06 for the Derrick League, d10 for the Lumen Accord, the one view of a building) has a
## team zone of a few percent of its pixels and no more than a fifth (that it is not a roof plate
## is test_artgen_plates.gd), and shrunk to 32 px in greyscale it still has a body and a spread of
## tones, so it can be told from the ground. The look itself is the gallery's, on Michael's phone.

const SCALE: float = 0.5  ## 2x art at zoom 1: one tile is 64 px.
const SIDE_PX: int = 32
## The marker's share of a sprite's opaque pixels: 2 to 12 % for the transition (ADR 0050 section 3,
## today's whole-team areas are valid markers); the last model batch narrows it to 2 to 6 %.
const TEAM_SHARE: Vector2 = Vector2(0.02, 0.12)
## The fixed faction colour's share at detail 1 and up: panels may cover large surfaces.
const FACTION_SHARE: Vector2 = Vector2(0.15, 0.85)
const MIN_SPREAD: float = 80.0  ## Luminance, 5th to 95th percentile, 0 to 255.
const MIN_BODY_PX: int = 150
const KEY_TOLERANCE: float = 0.06  ## Summed difference of the three channels in 0 to 1.
const PAGE: Vector2i = Vector2i(320, 320)
const GROUND_POINT: Vector2i = Vector2i(160, 200)
const Support: GDScript = preload("res://tests/art/artgen_v5_support.gd")

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


func test_the_default_view_of_every_type_has_a_team_share_of_2_to_12_percent() -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var share: float = _share(_default_picture(model), ArtPalette.KEYS[model.faction])
		(
			assert_float(share)
			. override_failure_message("%s team share %.3f" % [path, share])
			. is_between(TEAM_SHARE.x, TEAM_SHARE.y)
		)


## A model at detail 1 or more (ADR 0050 section 1) paints its faction's fixed colour on panels:
## FACTION_SHARE of its default view. The
## share is the hue-band measure of the same-scene check (P640): the pixels whose hue is within
## `faction_hue_band` of the faction's mid hue at a saturation of `faction_sat_min` or more, read
## from `same_scene.tres`. Exact tones miss the small faces of infantry, where the 1 px edge and the
## anti-aliasing take every pixel of a face under 5 px wide.
func test_a_model_at_detail_1_or_more_has_a_faction_share_in_its_band() -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		if not ("detail" in model) or int(model.get(&"detail")) < 1:
			continue
		var share: float = _faction_share(_default_picture(model), model.faction)
		(
			assert_float(share)
			. override_failure_message("%s faction share %.3f" % [path, share])
			. is_between(FACTION_SHARE.x, FACTION_SHARE.y)
		)


## The measure bites: a hull of fixed faction material is faction colour, not marker, and the
## other way round for the same hull in `team`.
func test_the_share_measure_tells_the_fixed_material_from_the_marker() -> void:
	for faction: StringName in [&"fossil", &"renew"]:
		for material: StringName in [&"faction", &"team"]:
			var model: ArtModel = Support.with_prims(
				["box hull %s 0 0 0 1.2 1.2 0.8" % material], [], []
			)
			model.faction = faction
			var picture: Image = Support.stage_image(model, 0)
			var faction_share: float = _faction_share(picture, faction)
			var team_share: float = _share(picture, ArtPalette.KEYS[faction])
			var label: String = "%s %s" % [faction, material]
			if material == &"faction":
				assert_float(faction_share).override_failure_message(label).is_greater(0.6)
				assert_float(team_share).override_failure_message(label).is_equal(0.0)
			else:
				assert_float(team_share).override_failure_message(label).is_greater(0.6)
				assert_float(faction_share).override_failure_message(label).is_equal(0.0)


## The share of `picture`'s opaque pixels within `KEY_TOLERANCE` of one of `hexes`.
func _share(picture: Image, hexes: Array) -> float:
	var keys: Array[Color] = []
	for hex: String in hexes:
		keys.append(Color(hex))
	var hit: int = 0
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
					hit += 1
					break
	return float(hit) / maxi(body, 1)


## The hue of `faction` in the bands: the one of `faction_hues` nearest the mid tone of the
## faction's fixed colour (the bands list the hues without naming the factions).
func _faction_hue(bands: SameSceneBands, faction: StringName) -> float:
	var mid: float = Color(ArtPalette.tone(faction, ArtPalette.FACTION, 1)).h * 360.0
	var best: float = bands.faction_hues[0]
	var best_gap: float = 360.0
	for hue: float in bands.faction_hues:
		var gap: float = absf(mid - hue)
		gap = minf(gap, 360.0 - gap)
		if gap < best_gap:
			best = hue
			best_gap = gap
	return best


## The share of `picture`'s opaque pixels in `faction`'s hue band (bands from `same_scene.tres`).
func _faction_share(picture: Image, faction: StringName) -> float:
	var bands: SameSceneBands = SameScene.load_bands()
	var hue: float = _faction_hue(bands, faction)
	var hit: int = 0
	var body: int = 0
	for y: int in picture.get_height():
		for x: int in picture.get_width():
			var pixel: Color = picture.get_pixel(x, y)
			if pixel.a < 0.95:
				continue
			body += 1
			var gap: float = absf(pixel.h * 360.0 - hue)
			if (
				pixel.s >= bands.faction_sat_min
				and minf(gap, 360.0 - gap) <= bands.faction_hue_band
			):
				hit += 1
	return float(hit) / maxi(body, 1)


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
	assert_int(seen).is_equal(6 * 8 * (4 + 2))  # the four squads and the two medic squads (P280)


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
