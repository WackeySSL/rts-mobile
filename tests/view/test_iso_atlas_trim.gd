extends GdUnitTestSuite
## The atlas trim (ADR 0036 section 15, plan P306): a directional frame lies on the page as its
## tight box only, with its own offset, and no picture moves. "No jump": for every directional frame
## of every sheet, the box a sprite draws after `WorldSort.show_base` (which a turn, a pose
## change and a sweep step all end in) is the box the untrimmed frame showed, `frame_box` minus
## the origin, exactly at bake scale 1.0 and within the texels the crop rounds out to below it. A
## frame with no box keeps the offset `dress` writes.

const Trim: GDScript = preload("res://tests/view/support/trim_check.gd")
const TOL_TEXELS: float = 2.0  ## What `Trim` allows below scale 1.0.

var _sort: WorldSort


func before_test() -> void:
	_sort = auto_free(WorldSort.new())


func test_the_crop_is_the_boxs_floor_and_ceil_with_a_ring_below_full_scale() -> void:
	var canvas: Vector2i = Vector2i(100, 80)
	var box: Rect2i = Rect2i(10, 20, 30, 40)
	assert_that(IsoAtlas.trim_rect(canvas, box, 1.0)).is_equal(box)
	# At 0.5 the raster is 50 x 40: x 5 to 20, y 10 to 30, grown by one texel.
	assert_that(IsoAtlas.trim_rect(canvas, box, 0.5)).is_equal(Rect2i(4, 9, 17, 22))
	# The whole canvas is the whole raster, and a box at the edge is clipped to it.
	assert_that(IsoAtlas.trim_rect(canvas, Rect2i(Vector2i.ZERO, canvas), 0.5)).is_equal(
		Rect2i(0, 0, 50, 40)
	)
	assert_that(IsoAtlas.trim_rect(canvas, Rect2i(90, 70, 10, 10), 0.5)).is_equal(
		Rect2i(44, 34, 6, 6)
	)


func test_no_directional_frame_jumps_at_full_scale() -> void:
	var atlas: IsoAtlas = _bake(1.0)
	assert_float(atlas.bake_scale()).is_equal(1.0)
	var seen: int = _check(atlas, 0.0)
	assert_int(seen).is_greater(400)  # The blockouts: units, squads, heads (480 directional frames).


func test_no_directional_frame_jumps_below_full_scale() -> void:
	var atlas: IsoAtlas = _bake(0.5)
	assert_float(atlas.bake_scale()).is_equal(0.5)
	assert_int(_check(atlas, TOL_TEXELS)).is_greater(400)


func test_the_trimmed_page_is_shorter_than_the_untrimmed_one() -> void:
	var players: Array[IsoPlayerArt] = _players()
	var sheets: Array[IsoSheetDef] = IsoAtlas.load_sheets()
	var bare: Array[IsoSheetDef] = []
	for sheet: IsoSheetDef in sheets:
		var copy: IsoSheetDef = sheet.duplicate() as IsoSheetDef
		copy.boxes = PackedInt32Array()
		bare.append(copy)
	var trimmed: int = IsoAtlas.planned_page(sheets, players, 1.0).y
	var whole: int = IsoAtlas.planned_page(bare, players, 1.0).y
	assert_int(trimmed).is_less(whole - 500)


## Every directional frame's drawn box against its untrimmed box; the number of frames checked.
func _check(atlas: IsoAtlas, tol_texels: float) -> int:
	_sort.atlas = atlas
	var checked: int = 0
	var players: Array[IsoPlayerArt] = _players()
	for sheet: IsoSheetDef in IsoAtlas.load_sheets():
		var slot: int = -1
		for at: int in players.size():
			if players[at].faction == sheet.faction:
				slot = at
		if slot < 0:
			continue
		for part_name: String in sheet.parts:
			var part: StringName = StringName(part_name)
			if part == &"shadow":
				continue
			for dir: int in sheet.directions(part):
				var base: int = atlas.base(sheet.art_id, part, dir, slot)
				for frame: int in sheet.frame_count(part):
					var sprite: Sprite2D = auto_free(Sprite2D.new())
					_sort.dress(sprite, sheet, part)
					var dressed: Vector2 = sprite.offset
					_sort.show_base(sprite, base, frame)
					var label: String = "%s %s d%d f%d" % [sheet.art_id, part, dir, frame]
					if not sheet.has_boxes(part) or sheet.flies():
						assert_vector(sprite.offset).override_failure_message(label).is_equal(
							dressed
						)
						continue
					checked += 1
					_assert_box(sheet, part, dir, frame, sprite, tol_texels, label)
	return checked


func _assert_box(
	sheet: IsoSheetDef,
	part: StringName,
	dir: int,
	frame: int,
	sprite: Sprite2D,
	tol_texels: float,
	label: String
) -> void:
	var bake: float = 1.0 if tol_texels == 0.0 else 0.5
	(
		assert_str(Trim.problem(sprite, sheet, part, dir, frame, bake))
		. override_failure_message(label)
		. is_empty()
	)


func _bake(scale: float) -> IsoAtlas:
	return IsoAtlas.build(IsoAtlas.load_sheets(), _players(), scale)


func _players() -> Array[IsoPlayerArt]:
	var players: Array[IsoPlayerArt] = []
	for faction: StringName in [&"fossil", &"renew"]:
		var key: PackedStringArray = (
			(load(WorldSort.FACTION_FILE % faction) as FactionDef).key_triad
		)
		players.append(IsoPlayerArt.make(faction, key, key))
	return players


func test_a_flyers_frames_stay_untrimmed_on_page_two() -> void:
	# Page 2 (the shadows and the flyers) is not trimmed (ADR 0036 section 15): a flyer's hull
	# keeps its whole canvas as its region, and the page is the size it was without boxes.
	var players: Array[IsoPlayerArt] = _players()
	var sheets: Array[IsoSheetDef] = []
	for sheet: IsoSheetDef in IsoAtlas.load_sheets():
		if sheet.art_id == &"light_tank":
			var flyer: IsoSheetDef = sheet.duplicate() as IsoSheetDef
			flyer.fly_px = 40
			sheets.append(flyer)
	for sheet: IsoSheetDef in IsoAtlas.load_sheets():
		if sheet.art_id == &"heavy_tank":  # A ground sheet: an atlas bakes only with page 1.
			sheets.append(sheet)
	assert_int(sheets.size()).is_equal(2)
	var bare: Array[IsoSheetDef] = []
	for sheet: IsoSheetDef in sheets:
		var copy: IsoSheetDef = sheet.duplicate() as IsoSheetDef
		copy.boxes = PackedInt32Array()
		bare.append(copy)
	assert_bool(sheets[0].has_boxes(&"hull")).is_true()
	assert_bool(sheets[0].frame_box(&"hull", 0).size != sheets[0].frame_size(&"hull")).is_true()
	var atlas: IsoAtlas = IsoAtlas.build(sheets, players, 1.0)
	var region: Rect2i = atlas.region(&"light_tank", &"hull", 0, 0)
	assert_that(region.size).is_equal(sheets[0].frame_size(&"hull"))
	var sprite: Sprite2D = auto_free(Sprite2D.new())
	_sort.atlas = atlas
	_sort.dress(sprite, sheets[0], &"hull")
	var dressed: Vector2 = sprite.offset
	_sort.show_base(sprite, atlas.base(&"light_tank", &"hull", 0, 0), 0)
	assert_vector(sprite.offset).is_equal(dressed)
	var second: Vector2i = IsoAtlas.planned_page(sheets, players, 1.0, Callable(), 1)
	assert_that(second).is_equal(IsoAtlas.planned_page(bare, players, 1.0, Callable(), 1))
	assert_int(second.y).is_greater(0)
