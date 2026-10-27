extends GdUnitTestSuite
## The Ground page of the art gallery (plan rows P91, P91b and P103): the ore patches, the three
## ghosts of a barracks on the iso footprint (the sprite is the generated frame, the marks lie on
## the footprint's diamond) and the two pattern tiles, and the button that turns the pages (the
## Build page of P103 is in test_art_gallery_build.gd, the Icons page of plan row P92 in
## test_art_gallery_icon_pages.gd). The gallery opens on the Units page, which
## tests/art/test_art_gallery_units.gd and test_art_assets.gd cover. Plan row P101 deleted the
## Vehicles page and plan row P103 the oblique Buildings page with its Seam page.

const Gallery: GDScript = preload("res://game/view/art_gallery.gd")
const GALLERY_PATH: String = "res://scenes/dev/art_gallery.tscn"
## The tightest 16:9 phone, a wider one and a 4:3 tablet (the sizes of test_art_assets.gd).
const BASES: Array[Vector2] = [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 960)]
const TEAM_A: Color = Color("2F80ED")
const TEAM_B: Color = Color("E5484D")
const GROUND_PAGE: int = 2
const ART_SCALE: float = 0.5  ## The 2x art at zoom 1.


## A gallery switches `SceneTree.quit_on_go_back` off while it is open and restores what it found,
## so galleries alive together restore it in the wrong order (see test_art_assets.gd).
func before_test() -> void:
	_assert_quit_on_go_back_restored()


func after() -> void:
	_assert_quit_on_go_back_restored()


func test_the_gallery_opens_on_units_and_the_button_turns_through_the_pages() -> void:
	var gallery: Control = await _open_gallery()
	var button: Button = gallery.get_node("%PageButton")
	assert_str(button.text).is_equal("Units")
	_assert_page(gallery, 0)
	var pages: int = Gallery.PAGES.size()
	for step: int in pages:
		button.pressed.emit()
		_assert_page(gallery, (step + 1) % pages)
		assert_str(button.text).is_equal(Gallery.PAGES[(step + 1) % pages])
	assert_str(button.text).is_equal("Units")
	for gone: String in ["SeamPage", "VehiclesPage"]:
		assert_bool(gallery.has_node(gone)).override_failure_message(gone).is_false()


## The pages are opaque, so the two buttons are the last children: nothing covers them.
func test_the_back_and_page_buttons_stay_above_every_page() -> void:
	var gallery: Control = await _open_gallery()
	var last: int = gallery.get_child_count() - 1
	assert_int(gallery.get_node("%PageButton").get_index()).is_equal(last)
	assert_int(gallery.get_node("%BackButton").get_index()).is_equal(last - 1)
	for page: String in ["BuildingsPage", "GroundPage", "IconsPage", "IsoPage", "TerrainPage"]:
		assert_int(gallery.get_node(page).get_index()).is_less(last - 1)
	for button: Control in [gallery.get_node("%PageButton"), gallery.get_node("%BackButton")]:
		assert_vector(button.size).is_greater_equal(Vector2(120, 120))


func test_the_ground_page_has_the_ore_patches_the_ghosts_and_the_swatches() -> void:
	var gallery: Control = await _open_gallery()
	for ground: String in ["Grass", "Sand"]:
		var page: Node = gallery.get_node("GroundPage/" + ground)
		assert_array(page.get_children().map(_node_name)).is_equal(
			["OreLevels", "OreField", "Ghosts", "Swatches"]
		)
		for patch: String in ["OreLevels", "OreField"]:
			var rows: Array[String] = (
				Gallery.ORE_LEVEL_ROWS if patch == "OreLevels" else Gallery.ORE_FIELD_ROWS
			)
			var row: Node = page.get_node(patch)
			var tiles: Array[Node] = row.get_children().filter(
				func(node: Node) -> bool: return node is TextureRect
			)
			var count: int = 0
			for y: int in rows.size():
				var names: PackedStringArray = rows[y].split(" ")
				for x: int in names.size():
					var tile: TextureRect = row.get_node("Ore%d_%d" % [x, y])
					assert_str(tile.texture.resource_path).ends_with("ore_%s.svg" % names[x])
					# Side by side with no gap, so the tiles join.
					assert_vector(tile.position).is_equal(
						(row.get_node("Ore0_0") as Control).position + Vector2(x, y) * 64.0
					)
					assert_vector(tile.size).is_equal(Vector2(64, 64))
					count += 1
			assert_int(tiles.size()).is_equal(count)


## Valid: the wash on the footprint's diamond, the own building at a fade over it and a solid frame
## round the diamond. Blocked: the same in red with the hatch tile over the diamond and the
## occupied glyph, 32 dp and red like the hatch, in the middle of the footprint. Seen: the other
## player's building under the dots and the explored fog, over the whole sprite box, with no frame
## and no wash (ADR 0023 section 3). The sprite is the generated frame and stands on the diamond's
## back corner.
func test_the_three_ghosts_are_drawn_as_the_style_guide_says() -> void:
	var gallery: Control = await _open_gallery()
	var sheet: IsoSheetDef = (load(IsoIndex.PATH) as IsoIndex).sheet(&"barracks")
	var box: Vector2 = Vector2(sheet.frame_size(&"hull")) * ART_SCALE
	var back: Vector2 = Vector2(box.x / 2.0, sheet.anchor(&"hull").y * ART_SCALE)
	var diamond: PackedVector2Array = PackedVector2Array(
		[back, back + Vector2(64, 32), back + Vector2(0, 64), back + Vector2(-64, 32)]
	)
	assert_float(box.x).is_equal(128.0)
	for ground: String in ["Grass", "Sand"]:
		var row: Node = gallery.get_node("GroundPage/%s/Ghosts" % ground)
		assert_array(row.get_children().map(_node_name)).is_equal(
			["GhostValid", "GhostBlocked", "GhostSeen"]
		)
		var valid: Node = row.get_node("GhostValid")
		var blocked: Node = row.get_node("GhostBlocked")
		var seen: Node = row.get_node("GhostSeen")
		for cell: Control in [valid, blocked, seen]:
			var rig: CanvasGroup = cell.get_node("Rig")
			assert_that(rig.modulate).is_equal(Color.WHITE)
			assert_vector(cell.size).is_equal(box)
			assert_vector(rig.position).is_equal(Vector2.ZERO)
			var hull: Sprite2D = rig.get_node("Hull")
			assert_vector(hull.texture.get_size()).is_equal(box)
			assert_bool(hull.centered).is_false()
		assert_array(valid.get_children().map(_node_name)).is_equal(["Wash", "Rig", "Frame"])
		assert_array(blocked.get_children().map(_node_name)).is_equal(
			["Wash", "Rig", "PatternHatch", "Frame", "GlyphReasonOccupied"]
		)
		assert_array(seen.get_children().map(_node_name)).is_equal(
			["Rig", "PatternSeen", "ExploredFog"]
		)
		# The fade goes through `self_modulate` of the group: `modulate` would reach the Hull too.
		var faded: Color = Color(1, 1, 1, Gallery.GHOST_SPRITE_ALPHA)
		assert_that((valid.get_node("Rig") as CanvasGroup).self_modulate).is_equal(faded)
		assert_that((blocked.get_node("Rig") as CanvasGroup).self_modulate).is_equal(faded)
		assert_that((seen.get_node("Rig") as CanvasGroup).self_modulate).is_equal(Color.WHITE)
		for kind: Node in [valid, blocked]:
			var wash: Polygon2D = kind.get_node("Wash")
			assert_array(Array(wash.polygon)).is_equal(Array(diamond))
			var frame: Line2D = kind.get_node("Frame")
			assert_array(Array(frame.points)).is_equal(Array(diamond))
			assert_bool(frame.closed).is_true()
			assert_float(frame.width).is_equal(Gallery.GHOST_FRAME_PX)
		assert_that(valid.get_node("Wash").color).is_equal(
			Color(Gallery.GHOST_OK, Gallery.GHOST_WASH_ALPHA)
		)
		assert_that(blocked.get_node("Wash").color).is_equal(
			Color(Gallery.GHOST_DANGER, Gallery.GHOST_WASH_ALPHA)
		)
		assert_that((valid.get_node("Frame") as Line2D).default_color).is_equal(Gallery.GHOST_OK)
		assert_that((blocked.get_node("Frame") as Line2D).default_color).is_equal(
			Gallery.GHOST_DANGER
		)
		# The hatch is one tiled polygon on the diamond, the dots a tiled rect over the sprite box.
		var hatch: Polygon2D = blocked.get_node("PatternHatch")
		var dots: TextureRect = seen.get_node("PatternSeen")
		assert_str(hatch.texture.resource_path).ends_with("ui/ghost_hatch.svg")
		assert_str(dots.texture.resource_path).ends_with("ui/ghost_seen.svg")
		assert_array(Array(hatch.polygon)).is_equal(Array(diamond))
		assert_array(Array(hatch.uv)).is_equal(Array(diamond))
		assert_int(hatch.texture_repeat).is_equal(CanvasItem.TEXTURE_REPEAT_ENABLED)
		assert_that(hatch.color).is_equal(Color(Gallery.GHOST_DANGER, Gallery.GHOST_HATCH_ALPHA))
		assert_that(dots.modulate).is_equal(Color(Gallery.GHOST_NEUTRAL, Gallery.GHOST_DOTS_ALPHA))
		assert_int(dots.stretch_mode).is_equal(TextureRect.STRETCH_TILE)
		assert_vector(dots.position).is_equal(Vector2.ZERO)
		assert_vector(dots.size).is_equal(box)
		var fog: ColorRect = seen.get_node("ExploredFog")
		assert_that(fog.color).is_equal(Color(0.0, 0.0, 0.0, 140.0 / 255.0))
		assert_vector(fog.position).is_equal(Vector2.ZERO)
		assert_vector(fog.size).is_equal(box)
		# The reason glyph is on top of the frame, red like the hatch (its seat keeps it apart from
		# the bands, STYLE.md "Icons and glyphs"), at the 32 dp of a glyph on the map (1.75 base px
		# per dp), centred in the footprint's diamond.
		var glyph: TextureRect = blocked.get_node("GlyphReasonOccupied")
		assert_str(glyph.texture.resource_path).ends_with("icons/glyph_reason_occupied.svg")
		assert_vector(glyph.size).is_equal(Vector2(56, 56))
		assert_vector(glyph.position).is_equal((diamond[0] + diamond[2]) / 2.0 - Vector2(28, 28))
		assert_that(glyph.modulate).is_equal(Gallery.GHOST_DANGER)
		assert_that(glyph.modulate).is_equal(Gallery.GLYPH_TINTS["glyph_reason_occupied"])
		# Own building in the Signal triad of the Derrick League's frames, the last seen one in the
		# other player's Arktisk (the bake's replacement of the key triad).
		var own: int = _pixels_near((valid.get_node("Rig/Hull") as Sprite2D).texture, "E8681F")
		var theirs: int = _pixels_near((seen.get_node("Rig/Hull") as Sprite2D).texture, "E8681F")
		assert_int(own).is_greater(50)
		assert_int(theirs).is_equal(0)
		(
			assert_int(_pixels_near((seen.get_node("Rig/Hull") as Sprite2D).texture, "1FA6C8"))
			. is_greater(50)
		)
		(
			assert_int(_pixels_near((valid.get_node("Rig/Hull") as Sprite2D).texture, "1FA6C8"))
			. is_equal(0)
		)


func test_the_swatches_show_each_pattern_tile_whole_times_over() -> void:
	var gallery: Control = await _open_gallery()
	for ground: String in ["Grass", "Sand"]:
		var row: Node = gallery.get_node("GroundPage/%s/Swatches" % ground)
		for swatch_name: String in ["SwatchHatch", "SwatchSeen"]:
			var swatch: TextureRect = row.get_node(swatch_name)
			assert_int(swatch.stretch_mode).is_equal(TextureRect.STRETCH_TILE)
			# The tile is 64 px, so the swatch holds whole tiles and every seam is a join.
			assert_vector(swatch.size / swatch.texture.get_size()).is_equal(Vector2(3, 2))
			assert_float(swatch.modulate.a).is_equal(1.0)


## Everything on the Ground page is inside its half and clear of the buttons and of each other, at
## the three base sizes; a ghost is its whole sprite box.
func test_the_ground_page_fits_each_half_and_keeps_clear_of_the_buttons_at_three_sizes() -> void:
	for base: Vector2 in BASES:
		var gallery: Control = await _open_gallery(base)
		_turn_to(gallery, GROUND_PAGE)
		await await_idle_frame()
		var problems: Array[String] = []
		var seen: Array[Rect2] = []
		var buttons: Array[Rect2] = _button_rects(gallery)
		for ground_name: String in ["Grass", "Sand"]:
			var ground: Control = gallery.get_node("GroundPage/" + ground_name)
			var half: Rect2 = ground.get_global_rect()
			var things: Array[Rect2] = []
			var names: Array[String] = []
			for patch: String in ["OreLevels", "OreField"]:
				things.append((ground.get_node(patch + "/Frame") as Control).get_global_rect())
				names.append(patch)
			for kind: String in ["Valid", "Blocked", "Seen"]:
				things.append((ground.get_node("Ghosts/Ghost" + kind) as Control).get_global_rect())
				names.append("Ghost" + kind)
			for swatch: String in ["SwatchHatch", "SwatchSeen"]:
				things.append((ground.get_node("Swatches/" + swatch) as Control).get_global_rect())
				names.append(swatch)
			for index: int in things.size():
				problems.append_array(_clashes(things[index], names[index], half, buttons, seen))
				seen.append(things[index])
		assert_int(seen.size()).is_equal(14)
		assert_array(problems).override_failure_message(str(base)).is_empty()
		gallery.get_parent().free()


## Every hidden page is out of sight, so the Units page keeps the screen to itself.
func _assert_page(gallery: Control, page: int) -> void:
	for node_name: String in ["Grass", "Sand", "TerrainRow"]:
		(
			assert_bool(gallery.get_node(node_name).visible)
			. override_failure_message(node_name)
			. is_equal(page == 0)
		)
	assert_bool(gallery.get_node("BuildingsPage").visible).is_equal(page == 1)
	assert_bool(gallery.get_node("GroundPage").visible).is_equal(page == GROUND_PAGE)
	assert_bool(gallery.get_node("IconsPage").visible).is_equal(page == 3)
	assert_bool(gallery.get_node("IsoPage").visible).is_equal(page == 4)
	assert_bool(gallery.get_node("TerrainPage").visible).is_equal(page == 5)


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


## How many opaque pixels of `texture` lie within a few units of `hex` in every channel.
func _pixels_near(texture: Texture2D, hex: String) -> int:
	var image: Image = texture.get_image()
	var want: Color = Color(hex)
	var count: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if (
				pixel.a > 0.95
				and absf(pixel.r - want.r) + absf(pixel.g - want.g) + absf(pixel.b - want.b) < 0.06
			):
				count += 1
	return count


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
