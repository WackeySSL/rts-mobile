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


## The mirror row (P632): the same sprite as the two players of a mirror route has one
## silhouette and differs only where the marker is, a part of the body (the old models paint their
## whole team areas in it, 5 to 12 %, and its anti-aliased edges count too).
func test_the_mirror_row_differs_only_in_the_marker() -> void:
	for at: int in [0, 2]:  # The sheet's mirror row: an Ironward and a Facet unit.
		var id: StringName = StringName(_bands.scene[at])
		var own: SameScene.Sprite = SameScene.sprite(id, _bands, 1.0)
		var other: SameScene.Sprite = SameScene.sprite(id, _bands, 1.0, SameScene.mirror_of(id))
		assert_vector(Vector2(own.body.get_size())).is_equal(Vector2(other.body.get_size()))
		var differs: int = 0
		var body: int = 0
		for y: int in own.body.get_height():
			for x: int in own.body.get_width():
				var a: Color = own.body.get_pixel(x, y)
				var b: Color = other.body.get_pixel(x, y)
				assert_float(absf(a.a - b.a)).override_failure_message(String(id)).is_less(0.01)
				body += 1 if a.a > 0.95 else 0
				differs += 1 if a.a > 0.95 and not a.is_equal_approx(b) else 0
		var share: float = float(differs) / maxi(body, 1)
		assert_float(share).override_failure_message("%s %.3f" % [id, share]).is_between(0.02, 0.3)


## The route colours of the sheet are what `WorldSort.TRIADS` gives the sides (interim, P647).
func test_the_sheet_wears_the_routes_triads() -> void:
	assert_array(SameScene.ROUTE_TRIAD[&"fossil"]).is_equal(WorldSort.TRIADS[0])
	assert_array(SameScene.ROUTE_TRIAD[&"renew"]).is_equal(WorldSort.TRIADS[3])
	assert_array(Array(SameScene.mirror_of(&"heavy_tank"))).is_equal(WorldSort.TRIADS[3])
	assert_array(Array(SameScene.mirror_of(&"renew_tank"))).is_equal(WorldSort.TRIADS[0])


## The transition list (2026-11-25, P632) may only shrink: every listed id still misses its band,
## and a model that is fixed has to leave the list (P647 empties it).
func test_every_exempt_id_still_misses_its_band() -> void:
	for id: StringName in _bands.exempt_sat:
		assert_bool(_bands.roster.has(String(id))).override_failure_message(id).is_true()
		var m: Dictionary = SameScene.measure(SameScene.sprite(id, _bands, 1.0))
		assert_float(m[&"sat"]).override_failure_message("%s left sat" % id).is_less(
			_bands.tone_sat.x
		)
	for id: StringName in _bands.exempt_up:
		var m: Dictionary = SameScene.measure(SameScene.sprite(id, _bands, 1.0))
		assert_float(m[&"up_down"]).override_failure_message("%s left up" % id).is_less(
			_bands.light_up_min
		)


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


func test_a_garish_neutral_body_fails_the_neutral_band_and_pure_panels_the_whole_sprite_band(
) -> void:
	var garish: SameScene.Sprite = SameScene.sprite(HQ, _bands, 1.0)
	garish.body.fill_rect(garish.body.get_used_rect(), Color("#2EC24A"))
	assert_str("\n".join(_problems_of(garish))).contains("sat 0.")
	var panels: SameScene.Sprite = SameScene.sprite(HQ, _bands, 1.0)
	var box: Rect2i = panels.body.get_used_rect()
	panels.body.fill_rect(box, Color(0.45, 0.45, 0.45))
	panels.body.fill_rect(
		Rect2i(box.position, Vector2i(box.size.x * 4 / 5, box.size.y)), Color("#FF6E1F")
	)
	var text: String = "\n".join(_problems_of(panels))
	assert_str(text).contains("sat_all")
	# The panels are not the neutral body: only the grey fifth counts for `tone_sat`.
	assert_float(SameScene.measure(panels)[&"sat"]).is_less(0.01)


## Every material of both palettes that is not the fixed faction colour is neutral to the
## classifier (hue and saturation, whatever its tone), the faction colours are not, and the
## sentinel and the route triads count as the marker.
func test_the_classifier_calls_every_non_faction_material_neutral() -> void:
	for faction: StringName in ArtPalette.MATERIALS:
		for material: StringName in ArtPalette.MATERIALS[faction]:
			for level: int in 3:
				var hex: String = ArtPalette.tone(faction, material, level)
				var edge: String = ArtPalette.edge(faction, material, level == 0)
				for tone: String in [hex, edge]:
					var found: bool = SameScene.is_faction(Color(tone), _bands)
					(
						assert_bool(found)
						. override_failure_message("%s %s %s" % [faction, material, tone])
						. is_equal(material == ArtPalette.FACTION)
					)
	for material: StringName in ArtPalette.SHARED:
		for level: int in 3:
			var tone: String = ArtPalette.tone(&"fossil", material, level)
			assert_bool(SameScene.is_faction(Color(tone), _bands)).is_false()
	for hex: String in ArtPalette.SENTINEL + SameScene.ROUTE_TRIAD[&"fossil"]:
		assert_bool(SameScene.is_faction(Color(hex), _bands)).is_true()


func _problems(id: StringName) -> PackedStringArray:
	return _problems_of(SameScene.sprite(id, _bands, 1.0))


func _problems_of(sprite: SameScene.Sprite) -> PackedStringArray:
	return SameScene.problems(String(sprite.id), SameScene.measure(sprite), _bands)


func _is_rim(image: Image, x: int, y: int) -> bool:
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if image.get_pixelv(Vector2i(x, y) + step).a < 0.5:
			return true
	return false
