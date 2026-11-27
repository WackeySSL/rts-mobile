extends GdUnitTestSuite
## What the generated blockouts look like when rasterised (plan row P99, svg-art-style "Drawing
## rules"): every frame is a valid picture of the size its canvas says, the default view of every
## type (d06 for the Derrick League, d10 for the Lumen Accord, the one view of a building) has a
## team zone in its band (a few percent below detail 2, that it is not a roof plate is
## test_artgen_plates.gd; 30 to 65 % in the key band at detail 2 and up, where the large panels wear
## the team colour, ADR 0050 amendment A3), and shrunk to 32 px in greyscale it still has a body and
## a spread of tones, so it can be told from the ground. No model paints the fixed `faction`
## material, and the two sides of a role read apart by shape (amendment A4). The look itself is the
## gallery's, on Michael's phone.

const SCALE: float = 0.5  ## 2x art at zoom 1: one tile is 64 px.
const SIDE_PX: int = 32
## The marker's share of a sprite's opaque pixels below detail 2: 2 to 12 % in the exact tones of
## the key (ADR 0050 section 3, today's whole-team areas are valid markers). At detail 2 and up the
## share is `Pictures.TEAM_BAND`, in the key band (amendment A3).
const TEAM_SHARE: Vector2 = Vector2(0.02, 0.12)
## Two silhouettes of one role (a Nordvaern and a Facet model) overlap less than this at 32 px
## (amendment A4, the repo's `MAX_OVERLAP`), in each of these directions.
const MAX_OVERLAP: float = 0.85
const PAIR_DIRS: Array[int] = [6, 10]
const BATCHES: String = "res://docs/art/treadline-batches.json"
const MIN_SPREAD: float = 80.0  ## Luminance, 5th to 95th percentile, 0 to 255.
const MIN_BODY_PX: int = 150
const KEY_TOLERANCE: float = 0.06  ## Summed difference of the three channels in 0 to 1.
const PAGE: Vector2i = Vector2i(320, 320)
const GROUND_POINT: Vector2i = Vector2i(160, 200)
const Support: GDScript = preload("res://tests/art/artgen_v5_support.gd")
const Pictures: GDScript = preload("res://tests/art/building_picture_support.gd")

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


func test_the_default_view_of_every_type_has_a_team_share_in_its_band() -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var share: float = Pictures.model_share(model, _default_picture(model))
		var band: Vector2 = Pictures.model_band(model, false, TEAM_SHARE)
		(
			assert_float(share)
			. override_failure_message("%s team share %.3f, band %s" % [path, share, band])
			. is_between(band.x, band.y)
		)


## After the swap of P652 no model paints the fixed `faction` material: a fixed orange or blue part
## on a body would read as a team colour in a mirror match (ADR 0050 amendment A2). `ArtPalette`
## keeps the material for the item cards and as the classifier's reference hue.
func test_no_model_paints_the_fixed_faction_material() -> void:
	var seen: int = 0
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		for part: StringName in model.parts():
			for prim: ArtPrim in model.primitives(part):
				seen += 1
				(
					assert_str(String(prim.material))
					. override_failure_message("%s %s paints faction" % [path, part])
					. is_not_equal(String(ArtPalette.FACTION))
				)
	assert_int(seen).is_greater(1000)


## The faction reads from shape (amendment A4): for each Nordvaern and Facet model of one role, both
## at detail 2 or more, the 32 px silhouettes overlap less than `MAX_OVERLAP` in d06 and in d10, the
## same direction for both. The pairs are the same positions in the two batches of one kind
## (`docs/art/treadline-batches.json`: P638 with P639, P640 with P641, then P642 with P643 and on
## as those models reach detail 2). A mask has no colour, so the check holds whichever triad either
## side wears.
func test_a_nordvaern_and_a_facet_model_of_one_role_read_apart_by_shape() -> void:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BATCHES))
	var batches: Array = parsed["batches"]
	var seen: int = 0
	for at: int in range(0, batches.size() - 1, 2):
		var fossil: Dictionary = batches[at]
		var renew: Dictionary = batches[at + 1]
		assert_str(fossil["what"]).is_equal(renew["what"])
		for i: int in fossil["ids"].size():
			var first: ArtModel = (
				load("res://assets/art/models/fossil/%s.tres" % fossil["ids"][i]) as ArtModel
			)
			var second: ArtModel = (
				load("res://assets/art/models/renew/%s.tres" % renew["ids"][i]) as ArtModel
			)
			if first.detail < 2 or second.detail < 2:
				continue
			for dir: int in PAIR_DIRS:
				var overlap: float = Pictures.overlap(
					Pictures.mask_32(_picture(first, dir)), Pictures.mask_32(_picture(second, dir))
				)
				(
					assert_float(overlap)
					. override_failure_message(
						"%s against %s in d%02d: %.2f" % [first.art_id, second.art_id, dir, overlap]
					)
					. is_less(MAX_OVERLAP)
				)
				seen += 1
	assert_int(seen).is_greater_equal(14)  # seven pairs, two directions (P638-P641)


## The measure bites: a hull of fixed faction material is no team colour, and a hull of `team` is,
## by the exact tones and by the key band.
func test_the_share_measure_tells_the_fixed_material_from_the_team_colour() -> void:
	for faction: StringName in [&"fossil", &"renew"]:
		for material: StringName in [&"faction", &"team"]:
			var model: ArtModel = Support.with_prims(
				["box hull %s 0 0 0 1.2 1.2 0.8" % material], [], []
			)
			model.faction = faction
			var picture: Image = Support.stage_image(model, 0)
			var exact: float = _share(picture, ArtPalette.KEYS[faction])
			var band: float = Pictures.band_share(picture)
			var label: String = "%s %s" % [faction, material]
			if material == &"faction":
				assert_float(exact).override_failure_message(label).is_equal(0.0)
				assert_float(band).override_failure_message(label).is_equal(0.0)
			else:
				assert_float(exact).override_failure_message(label).is_greater(0.6)
				assert_float(band).override_failure_message(label).is_greater(0.8)


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
	return _picture(model, 6 if model.faction == &"fossil" else 10)


## A type facing `dir` (a building's one view) on a transparent page.
func _picture(model: ArtModel, dir: int) -> Image:
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
