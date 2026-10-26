extends GdUnitTestSuite
## The Build and Ground pages of the art gallery (plan row P91): the six buildings at gameplay zoom
## on grass and sand in both team colours, the ore patches, the three ghosts and the two pattern
## tiles, and the button that turns the pages (the Vehicles and Icons pages of plan row P92 are in
## test_art_gallery_icon_pages.gd). The gallery opens on the Units page, which
## tests/art/test_art_assets.gd covers.

const Gallery: GDScript = preload("res://game/view/art_gallery.gd")
const GALLERY_PATH: String = "res://scenes/dev/art_gallery.tscn"
## The tightest 16:9 phone, a wider one and a 4:3 tablet (the sizes of test_art_assets.gd).
const BASES: Array[Vector2] = [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 960)]
const SMALL: Array[String] = ["PowerPlant", "Barracks", "DefenceTurret"]
const LARGE: Array[String] = ["Headquarters", "Refinery", "VehicleFactory"]
const TEAM_A: Color = Color("2F80ED")
const TEAM_B: Color = Color("E5484D")


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


## The pages are opaque, so the two buttons are the last children: nothing covers them.
func test_the_back_and_page_buttons_stay_above_every_page() -> void:
	var gallery: Control = await _open_gallery()
	var last: int = gallery.get_child_count() - 1
	assert_int(gallery.get_node("%PageButton").get_index()).is_equal(last)
	assert_int(gallery.get_node("%BackButton").get_index()).is_equal(last - 1)
	assert_int(gallery.get_node("BuildingsPage").get_index()).is_less(last - 1)
	assert_int(gallery.get_node("GroundPage").get_index()).is_less(last - 1)
	assert_int(gallery.get_node("VehiclesPage").get_index()).is_less(last - 1)
	assert_int(gallery.get_node("IconsPage").get_index()).is_less(last - 1)
	assert_int(gallery.get_node("ProbePage").get_index()).is_less(last - 1)
	for button: Control in [gallery.get_node("%PageButton"), gallery.get_node("%BackButton")]:
		assert_vector(button.size).is_greater_equal(Vector2(120, 120))


func test_the_build_page_has_the_six_buildings_in_each_of_the_four_slots_in_its_team_colour(
) -> void:
	var gallery: Control = await _open_gallery()
	var rows: Dictionary[String, Array] = {"SmallA": SMALL, "SmallB": SMALL}
	rows["LargeA"] = LARGE
	rows["LargeB"] = LARGE
	for ground: String in ["Grass", "Sand"]:
		for row_name: String in rows:
			var is_a: bool = row_name.ends_with("A")
			var row: Node = gallery.get_node("BuildingsPage/%s/%s" % [ground, row_name])
			assert_int(row.get_child_count()).is_equal(3)
			for building: String in rows[row_name]:
				var rig: Node2D = row.get_node(building)
				var id: String = building.to_snake_case()
				var layers: Array[String] = ["Hull", "Team"]
				if building == "DefenceTurret":
					layers.append("Turret")
				assert_int(rig.get_child_count()).is_equal(layers.size())
				for layer: String in layers:
					var texture: Texture2D = (rig.get_node(layer) as Sprite2D).texture
					assert_str(texture.resource_path).ends_with(
						"%s_%s.svg" % [id, layer.to_lower()]
					)
				var tint: Color = (rig.get_node("Team") as Sprite2D).modulate
				var path: String = "%s %s %s" % [ground, row_name, building]
				assert_that(tint).override_failure_message(path).is_equal(
					TEAM_A if is_a else TEAM_B
				)
				var group: StringName = Gallery.TEAM_A_GROUP if is_a else Gallery.TEAM_B_GROUP
				assert_bool(rig.is_in_group(group)).override_failure_message(path).is_true()
				assert_vector(rig.scale).is_equal(Vector2.ONE)


func test_the_defence_turret_gun_head_turns_with_the_other_turrets() -> void:
	var gallery: Control = await _open_gallery()
	var head: Sprite2D = gallery.get_node("BuildingsPage/Grass/SmallA/DefenceTurret/Turret")
	var before: float = head.rotation
	gallery.call("_process", 0.5)
	assert_float(head.rotation).is_not_equal(before)
	var rig: Node2D = gallery.get_node("BuildingsPage/Grass/SmallA/DefenceTurret")
	assert_float(rig.rotation).is_equal(0.0)


## Each building is at scale 1 inside its half, clear of its neighbours and of both buttons, on the
## phone that is tightest in height, a wider one and a tablet.
func test_the_build_page_fits_each_half_and_keeps_clear_of_the_buttons_at_three_sizes() -> void:
	for base: Vector2 in BASES:
		var gallery: Control = await _open_gallery(base)
		_turn_to(gallery, 1)
		await await_idle_frame()
		var problems: Array[String] = []
		var seen: Array[Rect2] = []
		var buttons: Array[Rect2] = _button_rects(gallery)
		for ground_name: String in ["Grass", "Sand"]:
			var half: Rect2 = (
				(gallery.get_node("BuildingsPage/" + ground_name) as Control).get_global_rect()
			)
			for node: Node in gallery.get_node("BuildingsPage/" + ground_name).find_children(
				"Hull", "Sprite2D", true, false
			):
				var box: Rect2 = _box(node)
				problems.append_array(_clashes(box, str(node.get_path()), half, buttons, seen))
				seen.append(box)
		assert_int(seen.size()).is_equal(24)
		assert_array(problems).override_failure_message(str(base)).is_empty()
		gallery.get_parent().free()


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


## Valid: the own team's building at a fade, a green wash and a solid green frame. Blocked: the same
## in red with the hatch tile over it and the occupied glyph, 32 dp and red like the hatch, in the
## middle of the footprint. Seen: the other team's building under the dots and the explored fog,
## with no frame and no wash.
func test_the_three_ghosts_are_drawn_as_the_style_guide_says() -> void:
	var gallery: Control = await _open_gallery()
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
			assert_vector(cell.size).is_equal(Vector2(128, 128))
			assert_str((rig.get_node("Hull") as Sprite2D).texture.resource_path).ends_with(
				"barracks_hull.svg"
			)
		assert_array(valid.get_children().map(_node_name)).is_equal(["Rig", "Wash", "Frame"])
		assert_array(blocked.get_children().map(_node_name)).is_equal(
			["Rig", "Wash", "PatternHatch", "Frame", "GlyphReasonOccupied"]
		)
		assert_array(seen.get_children().map(_node_name)).is_equal(
			["Rig", "PatternSeen", "ExploredFog"]
		)
		# The fade goes through `self_modulate` of the group: `modulate` would reach the Hull and
		# the Team sprite too, blend twice and show the hull through the team plate.
		var faded: Color = Color(1, 1, 1, Gallery.GHOST_SPRITE_ALPHA)
		assert_that((valid.get_node("Rig") as CanvasGroup).self_modulate).is_equal(faded)
		assert_that((blocked.get_node("Rig") as CanvasGroup).self_modulate).is_equal(faded)
		assert_that(valid.get_node("Wash").color).is_equal(
			Color(Gallery.GHOST_OK, Gallery.GHOST_WASH_ALPHA)
		)
		assert_that(blocked.get_node("Wash").color).is_equal(
			Color(Gallery.GHOST_DANGER, Gallery.GHOST_WASH_ALPHA)
		)
		for frame: ReferenceRect in [valid.get_node("Frame"), blocked.get_node("Frame")]:
			assert_bool(frame.editor_only).is_false()
			assert_float(frame.border_width).is_equal(Gallery.GHOST_FRAME_PX)
			assert_vector(frame.size).is_equal(Vector2(128, 128))
		assert_that((valid.get_node("Frame") as ReferenceRect).border_color).is_equal(
			Gallery.GHOST_OK
		)
		assert_that((blocked.get_node("Frame") as ReferenceRect).border_color).is_equal(
			Gallery.GHOST_DANGER
		)
		var hatch: TextureRect = blocked.get_node("PatternHatch")
		var dots: TextureRect = seen.get_node("PatternSeen")
		assert_str(hatch.texture.resource_path).ends_with("ui/ghost_hatch.svg")
		assert_str(dots.texture.resource_path).ends_with("ui/ghost_seen.svg")
		assert_that(hatch.modulate).is_equal(Color(Gallery.GHOST_DANGER, Gallery.GHOST_HATCH_ALPHA))
		assert_that(dots.modulate).is_equal(Color(Gallery.GHOST_NEUTRAL, Gallery.GHOST_DOTS_ALPHA))
		for pattern: TextureRect in [hatch, dots]:
			assert_int(pattern.stretch_mode).is_equal(TextureRect.STRETCH_TILE)
			assert_vector(pattern.size).is_equal(Vector2(128, 128))
		assert_that((seen.get_node("ExploredFog") as ColorRect).color).is_equal(
			Color(0.0, 0.0, 0.0, 140.0 / 255.0)
		)
		# The reason glyph is on top of the frame, red like the hatch (its seat keeps it apart from
		# the bands, STYLE.md "Icons and glyphs"), at the 32 dp of a glyph on the map (1.75 base px
		# per dp), centred in the 128 px footprint.
		var glyph: TextureRect = blocked.get_node("GlyphReasonOccupied")
		assert_str(glyph.texture.resource_path).ends_with("icons/glyph_reason_occupied.svg")
		assert_vector(glyph.size).is_equal(Vector2(56, 56))
		assert_vector(glyph.position).is_equal(Vector2(36, 36))
		assert_that(glyph.modulate).is_equal(Gallery.GHOST_DANGER)
		assert_that(glyph.modulate).is_equal(Gallery.GLYPH_TINTS["glyph_reason_occupied"])
		# Own team's ghost in team A, the last seen enemy building in team B.
		assert_that((valid.get_node("Rig/Team") as Sprite2D).modulate).is_equal(TEAM_A)
		assert_that((blocked.get_node("Rig/Team") as Sprite2D).modulate).is_equal(TEAM_A)
		assert_that((seen.get_node("Rig/Team") as Sprite2D).modulate).is_equal(TEAM_B)
		assert_that((seen.get_node("Rig") as CanvasGroup).self_modulate).is_equal(Color.WHITE)


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
## the three base sizes.
func test_the_ground_page_fits_each_half_and_keeps_clear_of_the_buttons_at_three_sizes() -> void:
	for base: Vector2 in BASES:
		var gallery: Control = await _open_gallery(base)
		_turn_to(gallery, 2)
		await await_idle_frame()
		var problems: Array[String] = []
		var seen: Array[Rect2] = []
		var buttons: Array[Rect2] = _button_rects(gallery)
		for ground_name: String in ["Grass", "Sand"]:
			var ground: Control = gallery.get_node("GroundPage/" + ground_name)
			var half: Rect2 = ground.get_global_rect()
			var things: Array[Control] = []
			for patch: String in ["OreLevels", "OreField"]:
				things.append(ground.get_node(patch + "/Frame"))
			for kind: String in ["Valid", "Blocked", "Seen"]:
				things.append(ground.get_node("Ghosts/Ghost" + kind))
			things.append(ground.get_node("Swatches/SwatchHatch"))
			things.append(ground.get_node("Swatches/SwatchSeen"))
			for thing: Control in things:
				var box: Rect2 = thing.get_global_rect()
				problems.append_array(_clashes(box, str(thing.get_path()), half, buttons, seen))
				seen.append(box)
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
	assert_bool(gallery.get_node("GroundPage").visible).is_equal(page == 2)
	assert_bool(gallery.get_node("VehiclesPage").visible).is_equal(page == 3)
	assert_bool(gallery.get_node("IconsPage").visible).is_equal(page == 4)
	assert_bool(gallery.get_node("ProbePage").visible).is_equal(page == 5)


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
