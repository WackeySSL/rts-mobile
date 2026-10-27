extends GdUnitTestSuite
## The per-match atlas bake (plan P113, ADR 0023 sections 2 and 5). Crafted SVG text, read through
## the `reader` seam, pins the colour step (each player's triad exactly where the key triad was and
## nothing else changed), the gutters, the sharing of a frame no key colour touches and the player
## index of `region`; crafted canvases pin the scale rule (`fit_scale`) end to end; the real
## blockouts of both factions pin the page (one, at most 4096 a side, for two players) and that the
## engine rasterises every frame to the size the rule counts on. Read from `image()` (a bake with
## `keep_image`), never the texture.

const KEY: PackedStringArray = ["#FF9446", "#E8681F", "#B04B12"]  ## Signal, the Derrick League's.
const ARKTISK: PackedStringArray = ["#62D6EE", "#1FA6C8", "#137C99"]
const KARMIN: PackedStringArray = ["#F26A5E", "#CF3A2E", "#922219"]
const GREY: String = "#808080"
const SMALL: Vector2i = Vector2i(16, 4)  ## The crafted hull: four stripes of 4 px.
const GUTTER: int = RuntimeAtlas.GUTTER_PX
const HEAD: String = '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">'
const BLOCK: String = '<polygon points="%d,0 %d,0 %d,%d %d,%d" fill="%s"/>'


func test_each_players_triad_stands_exactly_where_the_key_triad_was_and_nothing_else_changed(
) -> void:
	var sheet: IsoSheetDef = _sheet(&"crafted", &"fossil", SMALL)
	var atlas: IsoAtlas = _bake([sheet], [_art(KEY, KEY), _art(KEY, ARKTISK)])
	# Player 0 wears the key triad, player 1 Arktisk: its stripes are the triad, the grey one stays.
	var first: Image = _page(atlas, &"crafted", &"hull", 0)
	var second: Image = _page(atlas, &"crafted", &"hull", 1)
	assert_array(_stripes(first)).is_equal([KEY[0], KEY[1], KEY[2], GREY])
	assert_array(_stripes(second)).is_equal([ARKTISK[0], ARKTISK[1], ARKTISK[2], GREY])
	# Every pixel is what the rasteriser makes of the hand-recoloured text, edges included.
	assert_that(first.get_data()).is_equal(_raster(_hull(KEY)).get_data())
	assert_that(second.get_data()).is_equal(_raster(_hull(ARKTISK)).get_data())


func test_a_triad_that_holds_other_key_colours_is_baked_in_one_pass() -> void:
	var turned: PackedStringArray = [KEY[1], KEY[2], KEY[0]]
	var atlas: IsoAtlas = _bake([_sheet(&"crafted", &"fossil", SMALL)], [_art(KEY, turned)])
	assert_array(_stripes(_page(atlas, &"crafted", &"hull", 0))).is_equal(
		[KEY[1], KEY[2], KEY[0], GREY]
	)


func test_a_gutter_round_each_region_repeats_its_edge_and_no_two_cells_touch() -> void:
	var sheet: IsoSheetDef = _sheet(&"crafted", &"fossil", SMALL)
	var atlas: IsoAtlas = _bake([sheet], [_art(KEY, KEY), _art(KEY, ARKTISK)])
	var image: Image = atlas.image()
	var rects: Array[Rect2i] = _rects(atlas, [&"hull", &"shadow"], 2)
	assert_array(rects).has_size(3)  # Two hulls and the one shadow they share.
	for rect: Rect2i in rects:
		for y: int in rect.size.y:
			var left: Color = image.get_pixel(rect.position.x, rect.position.y + y)
			var right: Color = image.get_pixel(rect.end.x - 1, rect.position.y + y)
			for step: int in GUTTER:
				var at_left: Color = image.get_pixel(
					rect.position.x - 1 - step, rect.position.y + y
				)
				assert_that(at_left).is_equal(left)
				assert_that(image.get_pixel(rect.end.x + step, rect.position.y + y)).is_equal(right)
	for first: int in rects.size():
		for second: int in range(first + 1, rects.size()):
			assert_bool(rects[first].grow(GUTTER).intersects(rects[second].grow(GUTTER))).is_false()


func test_a_frame_no_key_colour_touches_is_baked_once_for_the_players_of_a_faction() -> void:
	var sheet: IsoSheetDef = _sheet(&"crafted", &"fossil", SMALL)
	var atlas: IsoAtlas = _bake([sheet], [_art(KEY, KEY), _art(KEY, ARKTISK), _art(KEY, KARMIN)])
	var shadow: Rect2i = atlas.region(&"crafted", &"shadow", -1, 0)
	assert_bool(shadow.has_area()).is_true()
	assert_that(atlas.region(&"crafted", &"shadow", -1, 1)).is_equal(shadow)
	assert_that(atlas.region(&"crafted", &"shadow", -1, 2)).is_equal(shadow)
	assert_array(_rects(atlas, [&"hull"], 3)).has_size(3)  # The hulls differ by player.


func test_a_player_has_regions_only_for_the_frames_of_its_own_faction() -> void:
	var fossil: IsoSheetDef = _sheet(&"crafted", &"fossil", SMALL)
	var renew: IsoSheetDef = _sheet(&"other", &"renew", SMALL)
	var players: Array[IsoPlayerArt] = [_art(KEY, ARKTISK), _art(ARKTISK, KARMIN, &"renew")]
	var atlas: IsoAtlas = _bake([fossil, renew], players)
	assert_bool(atlas.region(&"crafted", &"hull", -1, 0).has_area()).is_true()
	assert_bool(atlas.region(&"other", &"hull", -1, 1).has_area()).is_true()
	assert_that(atlas.region(&"crafted", &"hull", -1, 1)).is_equal(Rect2i())
	assert_that(atlas.region(&"other", &"hull", -1, 0)).is_equal(Rect2i())
	assert_that(atlas.region(&"crafted", &"turret", -1, 0)).is_equal(Rect2i())
	assert_that(atlas.region(&"crafted", &"hull", 3, 0)).is_equal(Rect2i())
	assert_that(atlas.region(&"crafted", &"hull", -1, 7)).is_equal(Rect2i())


func test_the_scale_falls_by_seven_eighths_until_the_page_fits_4096() -> void:
	var thirty_two: Array[Vector2i] = []
	thirty_two.resize(32)
	thirty_two.fill(Vector2i(1000, 1000))
	# Cells are the rasterised size and 4 px: 1004, 879, 770 and 674 wide at scale 1, 7/8, 49/64 and
	# 343/512, which fit 4, 4, 5 and 6 to a 4096 shelf, so the 32 take 8, 8, 7 and 6 shelves:
	# 8032, 7032, 5390 and 4044 px, and only the last fits.
	assert_float(IsoAtlas.fit_scale(thirty_two, 1.0)).is_equal_approx(343.0 / 512.0, 1e-9)
	assert_that(IsoAtlas.page_size(thirty_two, 1.0)).is_equal(Vector2i(4096, 8032))
	assert_that(IsoAtlas.page_size(thirty_two, 343.0 / 512.0)).is_equal(Vector2i(4096, 4044))
	# Sixteen fit at once; a request is never raised; a canvas wider than the page lowers the scale.
	assert_float(IsoAtlas.fit_scale(thirty_two.slice(0, 16), 1.0)).is_equal(1.0)
	assert_float(IsoAtlas.fit_scale(thirty_two, 0.5)).is_equal(0.5)
	var wide: Array[Vector2i] = [Vector2i(5000, 10)]
	assert_float(IsoAtlas.fit_scale(wide, 1.0)).is_equal_approx(49.0 / 64.0, 1e-9)


func test_when_no_scale_down_to_the_floor_fits_the_atlas_is_empty() -> void:
	var huge: Array[Vector2i] = [Vector2i(20000, 20000)]
	assert_float(IsoAtlas.fit_scale(huge, 1.0)).is_equal(0.0)
	assert_float(IsoAtlas.fit_scale(huge, 0.2)).is_equal(0.0)  # Asked for below the floor.
	assert_float(IsoAtlas.fit_scale([] as Array[Vector2i], 1.0)).is_equal(1.0)  # Nothing to fit.
	var atlas: IsoAtlas = _bake(
		[_sheet(&"crafted", &"fossil", Vector2i(20000, 20000))], [_art(KEY, KEY)]
	)
	assert_bool(atlas.is_empty()).is_true()
	assert_float(atlas.bake_scale()).is_equal(0.0)
	assert_object(atlas.texture()).is_null()
	assert_that(atlas.page_px()).is_equal(Vector2i.ZERO)
	assert_that(atlas.region(&"crafted", &"hull", -1)).is_equal(Rect2i())


func test_a_bake_that_would_not_fit_is_rasterised_at_the_lowered_scale() -> void:
	# Three distinct frames of 3000 x 1500: at scale 1 the cells are 1504 tall, so two fit one page
	# and the third does not; at 7/8 they are 1317 tall and all three do, 3951 px.
	var sheet: IsoSheetDef = _sheet(&"big", &"fossil", Vector2i(3000, 1500), false)
	var players: Array[IsoPlayerArt] = [_art(KEY, KEY), _art(KEY, ARKTISK), _art(KEY, KARMIN)]
	var atlas: IsoAtlas = _bake([sheet], players, 1.0, Vector2i(3000, 1500))
	assert_float(atlas.bake_scale()).is_equal(0.875)
	assert_that(atlas.page_px()).is_equal(Vector2i(4096, 3951))
	for player: int in 3:
		assert_that(atlas.region(&"big", &"hull", -1, player).size).is_equal(Vector2i(2625, 1313))
	assert_that(atlas.region(&"big", &"hull", -1, 0)).is_not_equal(
		atlas.region(&"big", &"hull", -1, 1)
	)


func test_the_real_blockouts_of_both_factions_with_two_players_fit_one_page_at_full_scale() -> void:
	var sheets: Array[IsoSheetDef] = IsoAtlas.load_sheets()
	var atlas: IsoAtlas = IsoAtlas.build(sheets, _real_players(), 1.0)
	assert_bool(atlas.is_empty()).is_false()
	assert_float(atlas.bake_scale()).is_equal(1.0)
	assert_int(atlas.page_px().x).is_equal(IsoAtlas.PAGE_MAX_PX)
	assert_int(atlas.page_px().y).is_between(1, IsoAtlas.PAGE_MAX_PX)
	assert_that(atlas.texture().get_size()).is_equal(Vector2(atlas.page_px()))
	assert_bool(atlas.image().is_empty()).is_true()  # The CPU page is dropped after the upload.
	assert_float(atlas.bake_ms()).is_greater(0.0)
	_assert_every_frame_has_its_rasterised_size(atlas, sheets, 1.0)


func test_every_real_frame_comes_out_of_the_engine_at_the_size_the_rule_counts() -> void:
	var sheets: Array[IsoSheetDef] = IsoAtlas.load_sheets()
	var atlas: IsoAtlas = IsoAtlas.build(sheets, _real_players(), 49.0 / 64.0)
	assert_float(atlas.bake_scale()).is_equal(49.0 / 64.0)  # It fits, so the request is kept.
	_assert_every_frame_has_its_rasterised_size(atlas, sheets, 49.0 / 64.0)


func test_a_real_frame_is_read_from_its_file_and_recoloured_for_each_player() -> void:
	var index: IsoIndex = load(IsoIndex.PATH) as IsoIndex
	var sheet: IsoSheetDef = index.sheet(&"headquarters")
	var players: Array[IsoPlayerArt] = [_art(KEY, KEY), _art(KEY, KARMIN)]
	var atlas: IsoAtlas = IsoAtlas.build([sheet], players, 0.5, true)
	var text: String = FileAccess.get_file_as_string(sheet.path(&"hull", -1))
	assert_bool(text.contains(KEY[1])).is_true()  # The art paints its team zone in the key triad.
	var own: Image = _page(atlas, &"headquarters", &"hull", 0)
	var other: Image = _page(atlas, &"headquarters", &"hull", 1)
	assert_that(own.get_data()).is_equal(_raster(text, 0.5).get_data())
	assert_that(other.get_data()).is_equal(_raster(players[1].recolour(text), 0.5).get_data())
	assert_that(other.get_data()).is_not_equal(own.get_data())


func test_the_index_loads_every_sheet_of_both_factions() -> void:
	var sheets: Array[IsoSheetDef] = IsoAtlas.load_sheets()
	var index: IsoIndex = load(IsoIndex.PATH) as IsoIndex
	assert_int(sheets.size()).is_equal(index.sheets.size())
	var per_faction: Dictionary[StringName, int] = {&"fossil": 0, &"renew": 0}
	for sheet: IsoSheetDef in sheets:
		per_faction[sheet.faction] += 1
		var first: int = sheet.directions(&"hull")[0]
		assert_bool(FileAccess.file_exists(sheet.path(&"hull", first))).is_true()
	assert_int(per_faction[&"fossil"]).is_equal(14)
	assert_int(per_faction[&"renew"]).is_equal(14)


func test_a_player_without_valid_art_and_a_frame_without_text_are_reported() -> void:
	var sheet: IsoSheetDef = _sheet(&"crafted", &"fossil", SMALL)
	var made: Array[IsoAtlas] = []
	var players: Array[IsoPlayerArt] = [null, _art(KEY, ARKTISK)]
	await (
		assert_error(func() -> void: made.append(_bake([sheet], players)))
		. is_push_error("IsoAtlas: player 0 has no valid art (a faction and two triads)")
	)
	assert_bool(made[0].region(&"crafted", &"hull", -1, 1).has_area()).is_true()
	assert_that(made[0].region(&"crafted", &"hull", -1, 0)).is_equal(Rect2i())
	var path: String = sheet.path(&"hull", -1)
	var reader: Callable = func(file: String) -> String: return "" if file == path else _shadow()
	var one: Array[IsoPlayerArt] = [_art(KEY, KEY)]
	await (
		assert_error(func() -> void: made.append(IsoAtlas.build([sheet], one, 1.0, true, reader)))
		. is_push_error("IsoAtlas: no SVG text at %s" % path)
	)
	assert_that(made[1].region(&"crafted", &"hull", -1, 0)).is_equal(Rect2i())
	assert_bool(made[1].region(&"crafted", &"shadow", -1, 0).has_area()).is_true()


## The crafted sheet of one art id: a hull and, unless `with_shadow` is off, its shadow; one frame
## each, of `canvas` px.
func _sheet(
	art_id: StringName, faction: StringName, canvas: Vector2i, with_shadow: bool = true
) -> IsoSheetDef:
	var sheet: IsoSheetDef = IsoSheetDef.new()
	sheet.art_id = art_id
	sheet.faction = faction
	sheet.category = &"bld"
	sheet.footprint = 1
	var parts: int = 2 if with_shadow else 1
	for part: int in parts:
		sheet.parts.append(["hull", "shadow"][part])
		sheet.counts.append(1)
		sheet.sizes.append_array([canvas.x, canvas.y])
		sheet.anchors.append_array([0, 0])
	return sheet


## `HEAD` and one block of `colour` from `left` to `right` across `height` rows.
func _block(left: int, right: int, height: int, colour: String) -> String:
	return BLOCK % [left, right, right, height, left, height, colour]


## The crafted hull of SMALL: three stripes in the colours of `triad` and a grey one.
func _hull(triad: PackedStringArray) -> String:
	var text: String = HEAD % [SMALL.x, SMALL.y]
	for stripe: int in 3:
		text += _block(4 * stripe, 4 * stripe + 4, SMALL.y, triad[stripe])
	return text + _block(12, 16, SMALL.y, GREY) + "</svg>"


func _shadow() -> String:
	return HEAD % [SMALL.x, SMALL.y] + _block(0, 16, SMALL.y, "#000000") + "</svg>"


## The crafted frames: the key-coloured stripes for SMALL, one key-coloured block for any other
## canvas, and a shadow without a key colour.
func _reader(canvas: Vector2i) -> Callable:
	var hull: String = _hull(KEY)
	if canvas != SMALL:
		hull = HEAD % [canvas.x, canvas.y] + _block(0, canvas.x, canvas.y, KEY[1]) + "</svg>"
	return func(path: String) -> String: return _shadow() if path.contains("_shadow") else hull


func _art(
	key: PackedStringArray, triad: PackedStringArray, faction: StringName = &"fossil"
) -> IsoPlayerArt:
	return IsoPlayerArt.make(faction, key, triad)


func _bake(
	sheets: Array[IsoSheetDef],
	players: Array[IsoPlayerArt],
	scale: float = 1.0,
	canvas: Vector2i = SMALL
) -> IsoAtlas:
	return IsoAtlas.build(sheets, players, scale, true, _reader(canvas))


## The page pixels of one frame of one player.
func _page(atlas: IsoAtlas, art_id: StringName, part: StringName, player: int) -> Image:
	return atlas.image().get_region(atlas.region(art_id, part, -1, player))


## The colours at the middle of the four stripes of a SMALL frame, "#RRGGBB".
func _stripes(image: Image) -> Array[String]:
	var colours: Array[String] = []
	for stripe: int in 4:
		colours.append("#" + image.get_pixel(4 * stripe + 2, 2).to_html(false).to_upper())
	return colours


## The distinct regions of the crafted art id's `parts` for the first `players` players.
func _rects(atlas: IsoAtlas, parts: Array[StringName], players: int) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	for part: StringName in parts:
		for player: int in players:
			var rect: Rect2i = atlas.region(&"crafted", part, -1, player)
			if not rects.has(rect):
				rects.append(rect)
	return rects


func _raster(text: String, scale: float = 1.0) -> Image:
	var image: Image = Image.new()
	assert_int(image.load_svg_from_string(text, scale)).is_equal(OK)
	return image


## Player 0 the Derrick League in its own Signal triad, player 1 the Lumen Accord in Arktisk.
func _real_players() -> Array[IsoPlayerArt]:
	return [_art(KEY, KEY), _art(ARKTISK, ARKTISK, &"renew")]


## Each frame of each player's faction has a region of the size the engine rasterises its canvas
## to (`raster_size`), which is what the scale rule counted before anything was rasterised.
func _assert_every_frame_has_its_rasterised_size(
	atlas: IsoAtlas, sheets: Array[IsoSheetDef], scale: float
) -> void:
	var factions: Array[StringName] = [&"fossil", &"renew"]
	var frames: int = 0
	for player: int in factions.size():
		for sheet: IsoSheetDef in sheets:
			if sheet.faction != factions[player]:
				continue
			for part_name: String in sheet.parts:
				var part: StringName = StringName(part_name)
				var want: Vector2i = IsoAtlas.raster_size(sheet.frame_size(part), scale)
				for dir: int in sheet.directions(part):
					var region: Rect2i = atlas.region(sheet.art_id, part, dir, player)
					(
						assert_that(region.size)
						. override_failure_message("%s %s %d" % [sheet.art_id, part, dir])
						. is_equal(want)
					)
					frames += 1
	assert_int(frames).is_equal(480)
