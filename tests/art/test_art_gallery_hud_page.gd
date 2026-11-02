extends GdUnitTestSuite
## The Hud page of the art gallery (plan row P118g, STYLE.md "Gallery"): the fourteen glyphs of the
## corner HUD at 48 dp with their names, the glyphs they stand beside, the fourteen again at 32 and
## 24 dp, and each faction's power building with the construction badge and the offline glyph over
## it, all on the HUD panel's backdrop, laid out to fit at the three base sizes of the gallery. The
## glyph files are in test_icon_art.gd and test_hud_v2_glyphs.gd, the other pages in
## test_art_gallery_icon_pages.gd and test_art_gallery_pages.gd.

const Gallery: GDScript = preload("res://game/view/art_gallery.gd")
const GALLERY_PATH: String = "res://scenes/dev/art_gallery.tscn"
## The tightest 16:9 phone, a wider one and a 4:3 tablet (the sizes of test_art_assets.gd).
const BASES: Array[Vector2] = [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 960)]
const PX_PER_DP: float = 1.75  ## Base px per dp on the 6-inch phone profile.
const HUD_PAGE: int = 6
const ROW_NAMES: Array[String] = ["Bar", "Pause", "Panels", "Beside", "Small32", "Small24", "Sites"]


## A gallery switches `SceneTree.quit_on_go_back` off while it is open and restores what it found,
## so galleries alive together restore it in the wrong order (see test_art_assets.gd).
func before_test() -> void:
	_assert_quit_on_go_back_restored()


func after() -> void:
	_assert_quit_on_go_back_restored()


func test_the_hud_page_is_the_last_of_seven_and_the_button_reaches_it() -> void:
	assert_array(Gallery.PAGES).is_equal(
		["Units", "Build", "Ground", "Icons", "Iso", "Terrain", "Hud"]
	)
	var gallery: Control = await _open_gallery()
	var button: Button = gallery.get_node("%PageButton")
	_turn_to(gallery, HUD_PAGE - 1)
	assert_bool(gallery.get_node("HudPage").visible).is_false()
	button.pressed.emit()
	assert_str(button.text).is_equal("Hud")
	assert_bool(gallery.get_node("HudPage").visible).is_true()
	assert_bool(gallery.get_node("TerrainPage").visible).is_false()
	button.pressed.emit()
	assert_str(button.text).is_equal("Units")
	assert_bool(gallery.get_node("HudPage").visible).is_false()


func test_the_hud_page_is_one_dark_panel_with_its_rows_in_order() -> void:
	var gallery: Control = await _open_gallery()
	var page: Node = gallery.get_node("HudPage")
	assert_array(page.get_children().map(_node_name)).is_equal(["Hud"])
	var panel: ColorRect = page.get_node("Hud")
	assert_that(panel.color).is_equal(Gallery.HUD_BACKDROP)
	assert_array(panel.get_children().map(_node_name)).is_equal(ROW_NAMES)


## The fourteen new glyphs by the part of the HUD that uses them, then the eight they stand beside:
## rows of the same names as `HUD_V2_ROWS`, each glyph a square `TextureRect` of 48 dp with the tint
## the HUD gives it and its name under it.
func test_each_row_shows_its_glyphs_at_48_dp_with_their_tints_and_names() -> void:
	var gallery: Control = await _open_gallery()
	var panel: Node = gallery.get_node("HudPage/Hud")
	var shown: int = 0
	assert_array(Gallery.HUD_V2_ROWS.keys()).is_equal(["Bar", "Pause", "Panels", "Beside"])
	for row_name: String in Gallery.HUD_V2_ROWS:
		var icons: Array = Gallery.HUD_V2_ROWS[row_name]
		var row: Node = panel.get_node(row_name)
		assert_int(row.get_child_count()).is_equal(icons.size() * 2)
		for icon: String in icons:
			var rect: TextureRect = row.get_node(icon.to_pascal_case())
			assert_str(rect.texture.resource_path).ends_with("icons/%s.svg" % icon)
			var want: float = Gallery.HUD_GLYPH_DP * PX_PER_DP
			assert_vector(rect.size).override_failure_message(icon).is_equal(Vector2.ONE * want)
			var tint: Color = Color.WHITE
			if Gallery.GLYPH_TINTS.has(icon):
				tint = Gallery.GLYPH_TINTS[icon]
			assert_that(rect.modulate).override_failure_message(icon).is_equal(tint)
			var short: String = icon.trim_prefix("glyph_")
			var label: Label = row.get_node("Label" + short.to_pascal_case())
			assert_str(label.text).is_equal(short.replace("_", " "))
			assert_float(label.get_rect().position.y).is_greater_equal(rect.get_rect().end.y)
			# the name is under its own glyph, not one pitch to either side
			(
				assert_float(label.get_rect().get_center().x)
				. override_failure_message(icon)
				. is_equal_approx(rect.get_rect().get_center().x, 0.5)
			)
			shown += 1
	assert_int(shown).is_equal(14 + 8)


func test_the_fourteen_new_glyphs_are_shown_again_at_32_and_24_dp() -> void:
	var gallery: Control = await _open_gallery()
	var panel: Node = gallery.get_node("HudPage/Hud")
	var fresh: Array[String] = []
	for row_name: String in Gallery.HUD_V2_NEW_ROWS:
		fresh.append_array(Gallery.HUD_V2_ROWS[row_name])
	assert_array(Gallery.HUD_SMALL_DP).is_equal([32.0, 24.0])
	for dp: float in Gallery.HUD_SMALL_DP:
		var row: Node = panel.get_node("Small%d" % int(dp))
		assert_array(row.get_children().map(_node_name)).is_equal(
			fresh.map(func(icon: String) -> String: return icon.to_pascal_case())
		)
		for rect: TextureRect in row.get_children():
			assert_vector(rect.size).is_equal(Vector2.ONE * dp * PX_PER_DP)


## Each faction's power building on its ground with the construction badge and the offline glyph
## side by side over its body, at the size of a glyph on the map, so that Michael sees how the badge
## stands on a white ceramic roof and on the Derrick League's concrete, beside the glyph it is
## meant to match.
func test_each_faction_has_a_building_with_the_two_badges_over_it() -> void:
	var gallery: Control = await _open_gallery()
	var sites: Node = gallery.get_node("HudPage/Hud/Sites")
	assert_array(sites.get_children().map(_node_name)).is_equal(
		["SiteFossil", "SiteRenew", "LabelSites"]
	)
	var grounds: Dictionary[String, Color] = {
		"SiteFossil": Gallery.TERRAIN_COLORS[&"grass_b"],
		"SiteRenew": Gallery.TERRAIN_COLORS[&"sand"]
	}
	assert_array(Gallery.HUD_SITE_BADGES).is_equal(["glyph_construct", "glyph_offline"])
	for swatch_name: String in grounds:
		var swatch: ColorRect = sites.get_node(swatch_name)
		assert_that(swatch.color).is_equal(grounds[swatch_name])
		assert_vector(swatch.size).is_equal(Gallery.HUD_SITE_SIZE)
		assert_array(swatch.get_children().map(_node_name)).is_equal(
			["Building", "GlyphConstruct", "GlyphOffline"]
		)
		var building: TextureRect = swatch.get_node("Building")
		assert_vector(building.size).is_greater(Vector2(100, 100))
		assert_vector(building.size).is_less(Vector2(Gallery.HUD_SITE_SIZE.x, 140.0))
		var construct: TextureRect = swatch.get_node("GlyphConstruct")
		var offline: TextureRect = swatch.get_node("GlyphOffline")
		for badge: TextureRect in [construct, offline]:
			assert_vector(badge.size).is_equal(Vector2.ONE * Gallery.MAP_GLYPH_DP * PX_PER_DP)
			# over the building's body, inside its frame
			assert_bool(building.get_rect().encloses(badge.get_rect())).is_true()
		assert_that(construct.modulate).is_equal(Color.WHITE)
		assert_that(offline.modulate).is_equal(Gallery.GLYPH_TINTS["glyph_offline"])
		assert_float(construct.get_rect().end.x).is_less(offline.get_rect().position.x)
		assert_float(construct.position.y).is_equal(offline.position.y)


## Only the glyph that says a state has a tint of its own: the stalled queue's "!" in the neutral
## grey of a tab at rest. The other thirteen are white and the plate behind them says the rest.
func test_only_the_alert_glyph_of_the_new_ones_has_a_tint() -> void:
	var tinted: Array[String] = []
	for row_name: String in Gallery.HUD_V2_NEW_ROWS:
		for icon: String in Gallery.HUD_V2_ROWS[row_name]:
			if Gallery.GLYPH_TINTS.has(icon):
				tinted.append(icon)
	assert_array(tinted).is_equal(["glyph_alert"])
	assert_that(Gallery.GLYPH_TINTS["glyph_alert"]).is_equal(Color("9AA5B1"))


## Everything on the page is inside it, clear of the two corner buttons and of every other glyph,
## name and swatch, at the three base sizes.
func test_the_hud_page_fits_and_keeps_clear_of_the_buttons_at_three_sizes() -> void:
	for base: Vector2 in BASES:
		var gallery: Control = await _open_gallery(base)
		_turn_to(gallery, HUD_PAGE)
		await await_idle_frame()
		var page: Rect2 = (gallery.get_node("HudPage") as Control).get_global_rect()
		var buttons: Array[Rect2] = _button_rects(gallery)
		var seen: Array[Rect2] = []
		var problems: Array[String] = []
		var panel: Node = gallery.get_node("HudPage/Hud")
		var things: Array[Node] = panel.find_children("*", "TextureRect", true, false)
		things.append_array(panel.find_children("*", "Label", true, false))
		things.append_array(panel.find_children("Site*", "ColorRect", true, false))
		for thing: Node in things:
			# a glyph on a swatch is inside the swatch, which is what is checked for overlaps
			if thing.get_parent() is ColorRect and thing.get_parent().name != "Hud":
				if not (thing.get_parent() as Control).get_global_rect().encloses(
					(thing as Control).get_global_rect()
				):
					problems.append(str(thing.get_path()) + " is outside its swatch")
				continue
			var box: Rect2 = (thing as Control).get_global_rect()
			if not page.encloses(box):
				problems.append(str(thing.get_path()) + " is outside the page")
			for button: Rect2 in buttons:
				if box.intersects(button):
					problems.append(str(thing.get_path()) + " is over a button")
			for other: Rect2 in seen:
				if box.grow(-0.5).intersects(other.grow(-0.5)):
					problems.append("%s overlaps %s" % [thing.get_path(), other])
			seen.append(box)
		# 22 glyphs at 48 dp with their 22 names, 14 + 14 small glyphs, two swatches and the line.
		assert_int(seen.size()).override_failure_message(str(base)).is_equal(22 * 2 + 28 + 2 + 1)
		assert_array(problems).override_failure_message(str(base)).is_empty()
		gallery.get_parent().free()


func _turn_to(gallery: Control, page: int) -> void:
	for step: int in page:
		gallery.get_node("%PageButton").pressed.emit()


func _button_rects(gallery: Control) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for button: Control in [gallery.get_node("%BackButton"), gallery.get_node("%PageButton")]:
		rects.append(button.get_global_rect())
	return rects


func _node_name(node: Node) -> String:
	return String(node.name)


func _assert_quit_on_go_back_restored() -> void:
	var restored: bool = get_tree().quit_on_go_back
	assert_bool(restored).override_failure_message("quit_on_go_back leaked").is_true()


## The gallery in a parent of `base_size`, the base size of a 16:9 phone unless given.
func _open_gallery(base_size: Vector2 = Vector2(1280, 720)) -> Control:
	var gallery: Control = auto_free((load(GALLERY_PATH) as PackedScene).instantiate())
	var parent: Control = auto_free(Control.new())
	parent.size = base_size
	add_child(parent)
	parent.add_child(gallery)
	await await_idle_frame()
	return gallery
