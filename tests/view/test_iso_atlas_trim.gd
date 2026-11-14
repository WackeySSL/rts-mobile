extends GdUnitTestSuite
## The atlas trim (ADR 0036 section 15, plan P306): a directional frame lies on the page as its
## tight box only, with its own offset, and no picture moves. "No jump": for every directional frame
## of every sheet, the box a sprite draws after `WorldSort.show_base` (which a turn, a pose
## change and a sweep step all end in) is the box the untrimmed frame showed, `frame_box` minus
## the origin, exactly at bake scale 1.0 and within the texels the crop rounds out to below it. A
## frame with no box keeps the offset `dress` writes.

const TOL_TEXELS: float = 2.0  ## The floor and the ceil of the crop, and the clear ring.

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
					if not sheet.has_boxes(part):
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
	var box: Rect2i = sheet.frame_box(part, dir, frame)
	var want: Rect2 = Rect2(
		Vector2(box.position - sheet.origin(part)) * WorldSort.ART_SCALE,
		Vector2(box.size) * WorldSort.ART_SCALE
	)
	var drawn: Rect2 = Rect2(sprite.offset * sprite.scale, sprite.region_rect.size * sprite.scale)
	var tol: Vector2 = Vector2.ONE * tol_texels * sprite.scale  # Per axis, px of the view.
	var message: String = "%s: drew %s, the untrimmed frame %s" % [label, drawn, want]
	if tol_texels == 0.0:
		assert_bool(drawn.is_equal_approx(want)).override_failure_message(message).is_true()
		return
	(
		assert_bool(drawn.grow_individual(0.01, 0.01, 0.01, 0.01).encloses(want))
		. override_failure_message(message)
		. is_true()
	)
	var outer: Rect2 = Rect2(want.position - tol, want.size + 2.0 * tol)
	assert_bool(outer.grow(0.01).encloses(drawn)).override_failure_message(message).is_true()


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
