extends GdUnitTestSuite
## The Icons page of the art gallery (plan row P92): the tab, item and glyph icons at their size in
## dp on the HUD panel, the map glyphs and rally flags on grass and sand. The gallery opens on the
## Units page (tests/art/test_art_gallery_units.gd); the Build page is in
## test_art_gallery_build.gd, the Ground page in test_art_gallery_pages.gd. Plan row P101 deleted
## the Vehicles page with the top-down units.

const Gallery: GDScript = preload("res://game/view/art_gallery.gd")
const GALLERY_PATH: String = "res://scenes/dev/art_gallery.tscn"
## The tightest 16:9 phone, a wider one and a 4:3 tablet (the sizes of test_art_assets.gd).
const BASES: Array[Vector2] = [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 960)]
const TEAM_A: Color = Color("2F80ED")
const TEAM_B: Color = Color("E5484D")
const PX_PER_DP: float = 1.75  ## Base px per dp on the 6-inch phone profile.
const ICONS_PAGE: int = 3


## A gallery switches `SceneTree.quit_on_go_back` off while it is open and restores what it found,
## so galleries alive together restore it in the wrong order (see test_art_assets.gd).
func before_test() -> void:
	_assert_quit_on_go_back_restored()


func after() -> void:
	_assert_quit_on_go_back_restored()


func test_the_gallery_has_six_pages_and_the_button_reaches_the_icons_page() -> void:
	assert_array(Gallery.PAGES).is_equal(["Units", "Build", "Ground", "Icons", "Iso", "Terrain"])
	var gallery: Control = await _open_gallery()
	var button: Button = gallery.get_node("%PageButton")
	_turn_to(gallery, ICONS_PAGE - 1)
	assert_bool(gallery.get_node("IconsPage").visible).is_false()
	button.pressed.emit()
	assert_str(button.text).is_equal("Icons")
	assert_bool(gallery.get_node("IconsPage").visible).is_true()
	assert_bool(gallery.has_node("VehiclesPage")).is_false()


func test_the_icons_page_has_the_hud_panel_and_the_two_grounds() -> void:
	var gallery: Control = await _open_gallery()
	var page: Node = gallery.get_node("IconsPage")
	assert_array(page.get_children().map(_node_name)).is_equal(["Hud", "Grass", "Sand"])
	assert_that((page.get_node("Hud") as ColorRect).color).is_equal(Gallery.HUD_BACKDROP)
	assert_that((page.get_node("Grass") as ColorRect).color).is_equal(
		Gallery.TERRAIN_COLORS[&"grass_b"]
	)
	assert_that((page.get_node("Sand") as ColorRect).color).is_equal(
		Gallery.TERRAIN_COLORS[&"sand"]
	)
	assert_array(page.get_node("Hud").get_children().map(_node_name)).is_equal(
		["Tabs", "Items", "Glyphs", "Emblems", "MenuGlyphs"]
	)
	for ground: String in ["Grass", "Sand"]:
		assert_array(page.get_node(ground).get_children().map(_node_name)).is_equal(
			["MapGlyphs", "Flags"]
		)


## Every icon is a square `TextureRect` named by its file, of its size in dp at 1.75 base px per
## dp, with the tint the HUD gives it; an item icon sits on a tile a step lighter than the panel.
func test_every_icon_is_shown_at_its_size_in_dp_with_its_tint_and_an_item_on_its_tile() -> void:
	var gallery: Control = await _open_gallery()
	var hud: Node = gallery.get_node("IconsPage/Hud")
	var groups: Dictionary[String, Array] = {
		"Tabs": [Gallery.TAB_ICONS, Gallery.TAB_ICON_DP],
		"Items": [Gallery.ITEM_ICONS, Gallery.ITEM_ICON_DP],
		"Glyphs": [Gallery.HUD_GLYPHS, Gallery.HUD_GLYPH_DP],
		"Emblems": [Gallery.EMBLEMS, Gallery.HUD_GLYPH_DP],
		"MenuGlyphs": [Gallery.MENU_GLYPHS, Gallery.HUD_GLYPH_DP],
	}
	for row_name: String in groups:
		var icons: Array = groups[row_name][0]
		var size_px: float = (groups[row_name][1] as float) * PX_PER_DP
		for icon: String in icons:
			var rect: TextureRect = hud.get_node("%s/%s" % [row_name, icon.to_pascal_case()])
			assert_str(rect.texture.resource_path).ends_with("icons/%s.svg" % icon)
			assert_vector(rect.size).override_failure_message(icon).is_equal(Vector2.ONE * size_px)
			var tint: Color = (
				Gallery.GLYPH_TINTS[icon] if Gallery.GLYPH_TINTS.has(icon) else Color.WHITE
			)
			assert_that(rect.modulate).override_failure_message(icon).is_equal(tint)
			var has_tile: bool = hud.get_node(row_name).has_node("Tile" + icon.to_pascal_case())
			assert_bool(has_tile).override_failure_message(icon).is_equal(row_name == "Items")
	var tile: ColorRect = hud.get_node("Items/TileItemRefinery")
	assert_that(tile.color).is_equal(Gallery.TILE_BACKDROP)
	var rect: Control = hud.get_node("Items/ItemRefinery")
	assert_that(tile.get_rect()).is_equal(rect.get_rect().grow(Gallery.TILE_MARGIN_PX))
	assert_int(Gallery.ITEM_ICONS.size()).is_equal(11)
	assert_float(Gallery.ITEM_ICON_DP).is_equal(64.0)


func test_the_map_glyphs_the_arrow_and_the_rally_flags_are_on_both_grounds() -> void:
	var gallery: Control = await _open_gallery()
	for ground: String in ["Grass", "Sand"]:
		var glyphs: Node = gallery.get_node("IconsPage/%s/MapGlyphs" % ground)
		assert_array(glyphs.get_children().map(_node_name)).is_equal(
			Gallery.MAP_GLYPHS.map(func(icon: String) -> String: return icon.to_pascal_case())
		)
		for icon: String in Gallery.MAP_GLYPHS:
			var rect: TextureRect = glyphs.get_node(icon.to_pascal_case())
			assert_vector(rect.size).is_equal(Vector2.ONE * Gallery.MAP_GLYPH_DP * PX_PER_DP)
		var flags: Node = gallery.get_node("IconsPage/%s/Flags" % ground)
		var arrow: TextureRect = flags.get_node("GlyphUnderAttack")
		assert_vector(arrow.size).is_greater_equal(Vector2.ONE * 48.0 * PX_PER_DP)
		assert_that(arrow.modulate).is_equal(Color("E5484D"))
		var rigs: Array[Node] = flags.get_children().filter(
			func(node: Node) -> bool: return node is Node2D
		)
		assert_array(rigs.map(_node_name)).is_equal(
			["RallyInfantryA", "RallyInfantryB", "RallyVehiclesA", "RallyVehiclesB"]
		)
		for rig: Node2D in rigs:
			var is_a: bool = String(rig.name).ends_with("A")
			var tab: String = String(rig.name).trim_suffix("A" if is_a else "B").to_snake_case()
			assert_array(rig.get_children().map(_node_name)).is_equal(["Hull", "Team"])
			assert_str((rig.get_node("Hull") as Sprite2D).texture.resource_path).ends_with(
				"flags/%s_hull.svg" % tab
			)
			assert_str((rig.get_node("Team") as Sprite2D).texture.resource_path).ends_with(
				"flags/%s_team.svg" % tab
			)
			assert_that((rig.get_node("Team") as Sprite2D).modulate).is_equal(
				TEAM_A if is_a else TEAM_B
			)
			var group: StringName = Gallery.TEAM_A_GROUP if is_a else Gallery.TEAM_B_GROUP
			assert_bool(rig.is_in_group(group)).is_true()


## The tints are palette colours (STYLE.md): the neutral team colour, the ore colour and the three
## UI accents; every tinted file exists.
func test_the_glyph_tints_are_palette_colours_of_icons_that_exist() -> void:
	var palette: PackedStringArray = ["9AA5B1", "F2B705", "30A46C", "F5A524", "E5484D"]
	for icon: String in Gallery.GLYPH_TINTS:
		var tint: String = (Gallery.GLYPH_TINTS[icon] as Color).to_html(false).to_upper()
		assert_bool(palette.has(tint)).override_failure_message(icon + " " + tint).is_true()
		assert_bool(ResourceLoader.exists(Gallery.ICON_ART % icon)).is_true()


## Everything on the Icons page is inside its half and clear of the two corner buttons and of every
## other icon, at the three base sizes; the item tiles are inside the HUD panel.
func test_the_icons_page_fits_each_half_and_keeps_clear_of_the_buttons_at_three_sizes() -> void:
	for base: Vector2 in BASES:
		var gallery: Control = await _open_gallery(base)
		_turn_to(gallery, ICONS_PAGE)
		await await_idle_frame()
		var problems: Array[String] = []
		var seen: Array[Rect2] = []
		var buttons: Array[Rect2] = _button_rects(gallery)
		for half_name: String in ["Hud", "Grass", "Sand"]:
			var half_node: Control = gallery.get_node("IconsPage/" + half_name)
			var half: Rect2 = half_node.get_global_rect()
			for rect: Node in half_node.find_children("*", "TextureRect", true, false):
				var box: Rect2 = (rect as Control).get_global_rect()
				problems.append_array(_clashes(box, str(rect.get_path()), half, buttons, seen))
				seen.append(box)
			for hull: Node in half_node.find_children("Hull", "Sprite2D", true, false):
				var box: Rect2 = _box(hull)
				problems.append_array(_clashes(box, str(hull.get_path()), half, buttons, seen))
				seen.append(box)
			for tile: Node in half_node.find_children("Tile*", "ColorRect", true, false):
				if not half.encloses((tile as Control).get_global_rect()):
					problems.append(str(tile.get_path()) + " is outside its half")
		# 26 on the HUD panel, 12 on each ground (7 glyphs, the arrow and four flags).
		assert_int(seen.size()).is_equal(26 + 12 + 12)
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


## What is wrong with `box`: outside `half`, over a button, or over one of the boxes already `seen`.
func _clashes(
	box: Rect2, label: String, half: Rect2, buttons: Array[Rect2], seen: Array[Rect2]
) -> Array[String]:
	var found: Array[String] = []
	if not half.encloses(box):
		found.append(label + " is outside its half")
	for button: Rect2 in buttons:
		if box.intersects(button):
			found.append(label + " is over a button")
	for other: Rect2 in seen:
		if box.intersects(other):
			found.append(label + " overlaps " + str(other))
	return found


func _node_name(node: Node) -> String:
	return String(node.name)


## The bounding box of a sprite on screen.
func _box(sprite: Node) -> Rect2:
	var node: Sprite2D = sprite as Sprite2D
	return node.get_global_transform() * node.get_rect()


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
