extends GdUnitTestSuite
## The Build, Seam and Ground pages of the art gallery (plan rows P91 and P91b): the six buildings
## in their oblique view at the camera zoom levels on grass and sand in both team colours, each cut
## at its footprint's middle line with a tank north and south of it, the building the vision edge
## crosses, the ore patches, the three ghosts and the two pattern tiles, and the button that turns
## the pages (the Vehicles and Icons pages of plan row P92 are in test_art_gallery_icon_pages.gd).
## The gallery opens on the Units page, which tests/art/test_art_assets.gd covers.

const Gallery: GDScript = preload("res://game/view/art_gallery.gd")
const Buildings: GDScript = preload("res://game/view/art_gallery_buildings.gd")
const GALLERY_PATH: String = "res://scenes/dev/art_gallery.tscn"
## The tightest 16:9 phone, a wider one and a 4:3 tablet (the sizes of test_art_assets.gd).
const BASES: Array[Vector2] = [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 960)]
const TEAM_A: Color = Color("2F80ED")
const TEAM_B: Color = Color("E5484D")
const BUILD_PAGE: int = 1
const GROUND_PAGE: int = 2
const SEAM_PAGE: int = 5
## The sections of the Build page in order: zoom 1 first, then the other two camera zoom levels.
const SECTIONS: Array[String] = [
	"Zoom100A", "Zoom100B", "Zoom75A", "Zoom75B", "Zoom150A", "Zoom150B"
]
const IDS: Array[String] = [
	"headquarters", "refinery", "vehicle_factory", "power_plant", "barracks", "defence_turret"
]
const TANK_REACH: float = 26.0
const RISE: float = 48.0


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
	for page: String in [
		"BuildingsPage",
		"GroundPage",
		"VehiclesPage",
		"IconsPage",
		"SeamPage",
		"IsoPage",
		"TerrainPage",
	]:
		assert_int(gallery.get_node(page).get_index()).is_less(last - 1)
	for button: Control in [gallery.get_node("%PageButton"), gallery.get_node("%BackButton")]:
		assert_vector(button.size).is_greater_equal(Vector2(120, 120))


func test_the_build_page_is_a_scroll_list_of_six_sections_on_grass_and_sand() -> void:
	var gallery: Control = await _open_gallery()
	var scroll: ScrollContainer = gallery.get_node("BuildingsPage/Scroll")
	assert_int(scroll.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	# A finger can drag it: the list takes the touch (nothing over it ignores it) and it has a range.
	assert_int(scroll.mouse_filter).is_not_equal(Control.MOUSE_FILTER_IGNORE)
	_turn_to(gallery, BUILD_PAGE)
	await await_idle_frame()
	assert_float(scroll.get_v_scroll_bar().max_value).is_greater(3.0 * 720.0)
	var content: Control = scroll.get_node("Content")
	assert_float(content.custom_minimum_size.y).is_greater(3.0 * 720.0)
	for ground: String in ["Grass", "Sand"]:
		var sections: Array[Node] = content.get_node(ground).get_children()
		assert_array(sections.map(_node_name)).is_equal(SECTIONS)
		for section: Node in sections:
			var zoom: float = float(
				String(section.name).substr(4, -1).trim_suffix("A").trim_suffix("B")
			)
			var is_a: bool = String(section.name).ends_with("A")
			var label: Label = section.get_child(0)
			var text: String = "Zoom %s, team %s" % [zoom / 100.0, "A" if is_a else "B"]
			assert_str(label.text).override_failure_message(section.name).is_equal(text)
			var cells: Array[Node] = section.get_children().slice(1)
			var want: Array = IDS.map(func(id: String) -> String: return id.to_pascal_case())
			assert_array(cells.map(_node_name)).override_failure_message(section.name).is_equal(
				want
			)
			for cell: Node2D in cells:
				assert_vector(cell.scale).is_equal(Vector2.ONE * zoom / 100.0)


## The base part is the sprite rows south of the footprint's middle line, the roof part the rows
## north of it, and the cell draws base, tanks, roof in that order (ADR 0022 section 2).
func test_each_cell_draws_the_base_part_then_the_tanks_then_the_roof_part_cut_at_the_middle_line(
) -> void:
	var gallery: Control = await _open_gallery()
	for ground: String in ["Grass", "Sand"]:
		for section: String in SECTIONS:
			var is_a: bool = section.ends_with("A")
			var team: Color = TEAM_A if is_a else TEAM_B
			var group: StringName = Gallery.TEAM_A_GROUP if is_a else Gallery.TEAM_B_GROUP
			for id: String in IDS:
				var path: String = (
					"BuildingsPage/Scroll/Content/%s/%s/%s" % [ground, section, id.to_pascal_case()]
				)
				var cell: Node = gallery.get_node(path)
				(
					assert_array(cell.get_children().map(_node_name))
					. override_failure_message(path)
					. is_equal(["Base", "TankNorth", "TankSouth", "Roof"])
				)
				var size: Vector2 = (
					(load("res://assets/art/svg/buildings/%s_hull.svg" % id) as Texture2D)
					. get_size()
				)
				var cut: float = size.y - size.x / 2.0
				var parts: Dictionary[String, Rect2] = {
					"Base": Rect2(0.0, cut, size.x, size.y - cut),
					"Roof": Rect2(0.0, 0.0, size.x, cut)
				}
				for part: String in parts:
					var rig: Node2D = cell.get_node(part)
					(
						assert_bool(rig.is_in_group(group))
						. override_failure_message(path + part)
						. is_true()
					)
					assert_vector(rig.position).is_equal(parts[part].position)
					for layer: String in ["Hull", "Team"]:
						var sprite: Sprite2D = rig.get_node(layer)
						assert_str(sprite.texture.resource_path).ends_with(
							"%s_%s.svg" % [id, layer.to_lower()]
						)
						assert_bool(sprite.region_enabled).is_true()
						assert_bool(sprite.centered).is_false()
						assert_that(sprite.region_rect).is_equal(parts[part])
					assert_that((rig.get_node("Team") as Sprite2D).modulate).is_equal(team)
				var head: Node = cell.get_node("Roof").get_node_or_null("Turret")
				assert_bool(head != null).override_failure_message(path).is_equal(
					id == "defence_turret"
				)
				for tank_name: String in ["TankNorth", "TankSouth"]:
					var tank: Node2D = cell.get_node(tank_name)
					assert_array(tank.get_children().map(_node_name)).is_equal(
						["Hull", "Team", "Turret"]
					)
					assert_bool(tank.is_in_group(group)).is_true()
					assert_that((tank.get_node("Team") as Sprite2D).modulate).is_equal(team)


## A unit north of a building has its centre at or north of the footprint's north edge and a unit
## south of it at or south of the south edge, by the light tank's reach
## (HealthBarLayer.VEHICLE_REACH_PX).
func test_the_tanks_stand_off_the_footprints_north_and_south_walls_by_their_reach() -> void:
	var gallery: Control = await _open_gallery()
	for id: String in IDS:
		var cell: Node2D = gallery.get_node(
			"BuildingsPage/Scroll/Content/Grass/Zoom100A/" + id.to_pascal_case()
		)
		var size: Vector2 = (
			(load("res://assets/art/svg/buildings/%s_hull.svg" % id) as Texture2D).get_size()
		)
		var north: Node2D = cell.get_node("TankNorth")
		var south: Node2D = cell.get_node("TankSouth")
		assert_vector(north.position).override_failure_message(id).is_equal(
			Vector2(size.x / 2.0, RISE - TANK_REACH)
		)
		assert_vector(south.position).override_failure_message(id).is_equal(
			Vector2(size.x / 2.0, size.y + TANK_REACH)
		)
		# The tank on the north side faces the building, the one on the south side faces it too.
		assert_float(north.rotation).is_equal_approx(PI / 2.0, 0.0001)
		assert_float(south.rotation).is_equal_approx(-PI / 2.0, 0.0001)
		# The extent of a cell is the sprite box with a tank's canvas beyond both walls.
		var extent: Vector2 = Buildings.cell_extent(size)
		assert_float(extent.x).is_equal(RISE - TANK_REACH - 32.0)
		assert_float(extent.y).is_equal(size.y + TANK_REACH + 32.0)


## The head of the defence turret turns about the roof's centre, the footprint's centre lifted by
## the rise, and turns with the other turrets; the roof part that carries it does not turn.
func test_the_defence_turret_gun_head_turns_about_the_roofs_centre_with_the_other_turrets() -> void:
	var gallery: Control = await _open_gallery()
	var roof: Node2D = gallery.get_node(
		"BuildingsPage/Scroll/Content/Grass/Zoom100A/DefenceTurret/Roof"
	)
	var head: Sprite2D = roof.get_node("Turret")
	assert_str(head.texture.resource_path).ends_with("defence_turret_turret.svg")
	assert_bool(head.centered).is_false()
	assert_vector(head.position).is_equal(Vector2(32, 32))
	assert_vector(head.offset).is_equal(Vector2(-32, -32))
	var before: float = head.rotation
	gallery.call("_process", 0.5)
	assert_float(head.rotation).is_not_equal(before)
	assert_float(roof.rotation).is_equal(0.0)


## Every cell is inside its ground, clear of the other cells and, at the top of the list, of both
## buttons, on the phone that is tightest in height, a wider one and a tablet.
func test_the_build_page_fits_each_half_and_keeps_clear_of_the_buttons_at_three_sizes() -> void:
	for base: Vector2 in BASES:
		var gallery: Control = await _open_gallery(base)
		_turn_to(gallery, BUILD_PAGE)
		await await_idle_frame()
		var problems: Array[String] = []
		var buttons: Array[Rect2] = _button_rects(gallery)
		var count: int = 0
		for ground_name: String in ["Grass", "Sand"]:
			var ground: Control = gallery.get_node("BuildingsPage/Scroll/Content/" + ground_name)
			var half: Rect2 = ground.get_global_rect()
			var seen: Array[Rect2] = []
			for cell: Node in ground.find_children("*", "Node2D", true, false):
				if not IDS.has(String(cell.name).to_snake_case()):
					continue
				var hull: Vector2 = (cell.get_node("Roof/Hull") as Sprite2D).texture.get_size()
				var extent: Vector2 = Buildings.cell_extent(hull)
				var box: Rect2 = (
					(cell as Node2D).get_global_transform()
					* Rect2(0.0, extent.x, hull.x, extent.y - extent.x)
				)
				count += 1
				var label: String = str(cell.get_path())
				if box.position.x < half.position.x or box.end.x > half.end.x:
					problems.append(label + " is outside its ground")
				for other: Rect2 in seen:
					if box.intersects(other):
						problems.append(label + " overlaps another cell")
				if cell.get_parent().name == SECTIONS[0]:
					for button: Rect2 in buttons:
						if box.intersects(button):
							problems.append(label + " is under a button")
				seen.append(box)
		assert_int(count).is_equal(2 * SECTIONS.size() * IDS.size())
		assert_array(problems).override_failure_message(str(base)).is_empty()
		gallery.get_parent().free()


## The Seam page (ADR 0022 section 4): the refinery with the explored fog over the west column of
## its footprint, drawn between the tanks and the roof part, beside the same refinery seen.
func test_the_seam_page_shows_the_fog_over_the_west_column_under_the_roof_part() -> void:
	var gallery: Control = await _open_gallery()
	_turn_to(gallery, SEAM_PAGE)
	assert_str((gallery.get_node("%PageButton") as Button).text).is_equal("Seam")
	for ground: String in ["Grass", "Sand"]:
		var row: Node = gallery.get_node("SeamPage/%s/Row" % ground)
		var cells: Array[Node] = row.get_children().filter(
			func(n: Node) -> bool: return n is Node2D
		)
		assert_int(cells.size()).is_equal(2)
		var size: Vector2 = (
			(load("res://assets/art/svg/buildings/refinery_hull.svg") as Texture2D).get_size()
		)
		assert_float(size.x).is_greater_equal(128.0)
		var fogged: Node2D = cells[0]
		var seen: Node2D = cells[1]
		assert_array(fogged.get_children().map(_node_name)).is_equal(
			["Base", "TankNorth", "TankSouth", "ExploredFog", "Roof"]
		)
		assert_array(seen.get_children().map(_node_name)).is_equal(
			["Base", "TankNorth", "TankSouth", "Roof"]
		)
		var fog: ColorRect = fogged.get_node("ExploredFog")
		assert_vector(fog.position).is_equal(Vector2(0, size.y - size.x))
		assert_vector(fog.size).is_equal(Vector2(64, size.x))
		assert_that(fog.color).is_equal(Color(0.0, 0.0, 0.0, 140.0 / 255.0))
		assert_int(fog.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
		var team: Color = TEAM_A if ground == "Grass" else TEAM_B
		assert_that((fogged.get_node("Roof/Team") as Sprite2D).modulate).is_equal(team)


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


## Valid: the wash on the footprint, the own team's building at a fade over it and a solid green
## frame on the footprint. Blocked: the same in red with the hatch tile over the sprite and the
## occupied glyph, 32 dp and red like the hatch, in the middle of the footprint. Seen: the other
## team's building under the dots and the explored fog, over the whole sprite box, with no frame and
## no wash (ADR 0022 sections 4 and 5). The sprite stands on the footprint's south edge.
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
			# The sprite box is the footprint with the rise above it: the rig is centred on it.
			assert_vector(rig.position).is_equal(Vector2(64, 64 - RISE / 2.0))
			assert_str((rig.get_node("Hull") as Sprite2D).texture.resource_path).ends_with(
				"barracks_hull.svg"
			)
			assert_vector((rig.get_node("Hull") as Sprite2D).texture.get_size()).is_equal(
				Vector2(128, 176)
			)
		assert_array(valid.get_children().map(_node_name)).is_equal(["Wash", "Rig", "Frame"])
		assert_array(blocked.get_children().map(_node_name)).is_equal(
			["Wash", "Rig", "PatternHatch", "Frame", "GlyphReasonOccupied"]
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
		# The wash, the hatch and the frame mark the footprint; the dots and the fog the sprite box.
		for node: Control in [valid.get_node("Wash"), blocked.get_node("Wash")]:
			assert_vector(node.size).is_equal(Vector2(128, 128))
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
		assert_vector(hatch.size).is_equal(Vector2(128, 128))
		assert_vector(dots.position).is_equal(Vector2(0, -RISE))
		assert_vector(dots.size).is_equal(Vector2(128, 128 + RISE))
		var fog: ColorRect = seen.get_node("ExploredFog")
		assert_that(fog.color).is_equal(Color(0.0, 0.0, 0.0, 140.0 / 255.0))
		assert_vector(fog.position).is_equal(Vector2(0, -RISE))
		assert_vector(fog.size).is_equal(Vector2(128, 128 + RISE))
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
## the three base sizes; a ghost counts with the rise of its sprite above its footprint.
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
				var box: Rect2 = (
					(ground.get_node("Ghosts/Ghost" + kind) as Control).get_global_rect()
				)
				things.append(Rect2(box.position - Vector2(0, RISE), box.size + Vector2(0, RISE)))
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
	assert_bool(gallery.get_node("BuildingsPage").visible).is_equal(page == BUILD_PAGE)
	assert_bool(gallery.get_node("GroundPage").visible).is_equal(page == GROUND_PAGE)
	assert_bool(gallery.get_node("VehiclesPage").visible).is_equal(page == 3)
	assert_bool(gallery.get_node("IconsPage").visible).is_equal(page == 4)
	assert_bool(gallery.get_node("SeamPage").visible).is_equal(page == SEAM_PAGE)
	assert_bool(gallery.get_node("IsoPage").visible).is_equal(page == 6)
	assert_bool(gallery.get_node("TerrainPage").visible).is_equal(page == 7)


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
