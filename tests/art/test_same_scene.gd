extends GdUnitTestSuite
## The same-scene check (ADR 0050 section 8, plan row P629): the composer builds the sheet headless,
## today's art is inside the bands of `tools/artgen/same_scene.tres`, and a sprite lit from the
## wrong side or outlined in black is not.

const SCOUT: StringName = &"renew_scout"
const HQ: StringName = &"renew_hq"

var _bands: SameSceneBands = SameScene.load_bands()


func test_the_sheet_builds_headless_with_every_zoom_both_factions_and_the_hud_strip() -> void:
	var sheet: Image = SameScene.sheet(_bands)
	assert_int(_bands.zooms.size()).is_equal(4)
	assert_int(_bands.scene.size()).is_equal(4)
	assert_bool(sheet.get_width() > 1200 and sheet.get_height() > 1000).is_true()
	# The sheet is not blank: it holds both faction hues beyond the dark background.
	var colours: Dictionary[int, bool] = {}
	for y: int in range(0, sheet.get_height(), 7):
		for x: int in range(0, sheet.get_width(), 7):
			colours[sheet.get_pixel(x, y).to_rgba32() >> 12] = true
	assert_int(colours.size()).is_greater(200)


func test_todays_art_holds_every_band() -> void:
	assert_array(SameScene.audit(_bands)).is_empty()
	assert_int(_bands.roster.size()).is_greater_equal(16)


func test_a_sprite_lit_from_the_south_east_fails_the_light_bands() -> void:
	for id: StringName in [SCOUT, HQ]:
		assert_array(_problems(id)).is_empty()
	var flipped: SameScene.Sprite = SameScene.sprite(SCOUT, _bands, 1.0)
	flipped.body.flip_x()
	assert_str("\n".join(_problems_of(flipped))).contains("left_right")
	flipped = SameScene.sprite(HQ, _bands, 1.0)
	flipped.body.flip_y()
	assert_str("\n".join(_problems_of(flipped))).contains("up_down")


func test_a_black_outline_fails_the_edge_band() -> void:
	var sprite: SameScene.Sprite = SameScene.sprite(HQ, _bands, 1.0)
	var box: Rect2i = sprite.body.get_used_rect()
	for x: int in range(box.position.x, box.end.x):
		for y: int in range(box.position.y, box.end.y):
			if sprite.body.get_pixel(x, y).a > 0.9 and _is_rim(sprite.body, x, y):
				sprite.body.set_pixel(x, y, Color.BLACK)
	assert_str("\n".join(_problems_of(sprite))).contains("black_edge")


func test_a_flat_sprite_fails_the_tone_and_density_bands() -> void:
	var sprite: SameScene.Sprite = SameScene.sprite(HQ, _bands, 1.0)
	var box: Rect2i = sprite.body.get_used_rect()
	sprite.body.fill_rect(box, Color(0.3, 0.3, 0.3))
	var text: String = "\n".join(_problems_of(sprite))
	assert_str(text).contains("density")
	assert_str(text).contains("value")


func _problems(id: StringName) -> PackedStringArray:
	return _problems_of(SameScene.sprite(id, _bands, 1.0))


func _problems_of(sprite: SameScene.Sprite) -> PackedStringArray:
	return SameScene.problems(String(sprite.id), SameScene.measure(sprite), _bands)


func _is_rim(image: Image, x: int, y: int) -> bool:
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if image.get_pixelv(Vector2i(x, y) + step).a < 0.5:
			return true
	return false
