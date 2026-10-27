extends GdUnitTestSuite
## The Build page of the art gallery (plan row P103, ADR 0023 sections 2 and 5): one building at a
## time on the iso ground with a tank of its faction in front of it and one behind it, at the
## camera zoom levels 1, 0.75 and 1.5 in the two triads, grass on the left and sand on the right.
## The frames are the one atlas `IsoAtlas` bakes for the two players, the rigs hang under one
## y-sorted node, the cast shadows lie under every body, and a defence's head faces the tank in
## front of it. The buildings themselves are pinned in test_fossil_buildings.gd.

const GALLERY_PATH: String = "res://scenes/dev/art_gallery.tscn"
const BUILD_PAGE: int = 1
const BASES: Array[Vector2] = [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 960)]
const SECTIONS: Array[String] = [
	"Zoom100Signal",
	"Zoom100Arktisk",
	"Zoom75Signal",
	"Zoom75Arktisk",
	"Zoom150Signal",
	"Zoom150Arktisk"
]
const ZOOM_OF: Dictionary[String, float] = {"Zoom100": 1.0, "Zoom75": 0.75, "Zoom150": 1.5}
const TRIAD_OF: Dictionary[String, int] = {"Signal": 0, "Arktisk": 1}
const SIGNAL_MID: String = "E8681F"
const ARKTISK_MID: String = "1FA6C8"
const ART_SCALE: float = 0.5


## A gallery switches `SceneTree.quit_on_go_back` off while it is open and restores what it found,
## so galleries alive together restore it in the wrong order (see test_art_assets.gd).
func before_test() -> void:
	_assert_quit_on_go_back_restored()


func after() -> void:
	_assert_quit_on_go_back_restored()


func test_the_page_steps_through_every_building_of_both_factions_with_two_big_buttons() -> void:
	var gallery: Control = await _open_gallery()
	var page: Control = await _build_page(gallery)
	var total: int = _building_paths().size()
	assert_int(total).is_greater_equal(16)
	assert_str((page.get_node("Title") as Label).text).contains("1 / %d" % total)
	var first: String = (page.get_node("Title") as Label).text
	for button_name: String in ["Previous", "Next"]:
		var button: Button = page.get_node(button_name)
		assert_vector(button.size).is_greater_equal(Vector2(120, 120))
		assert_bool(button.get_global_rect().intersects(_corner_buttons(gallery)[0])).is_false()
		assert_bool(button.get_global_rect().intersects(_corner_buttons(gallery)[1])).is_false()
	page.get_node("Next").pressed.emit()
	assert_str((page.get_node("Title") as Label).text).contains("2 / %d" % total)
	page.get_node("Previous").pressed.emit()
	assert_str((page.get_node("Title") as Label).text).is_equal(first)
	page.get_node("Previous").pressed.emit()
	assert_str((page.get_node("Title") as Label).text).contains("%d / %d" % [total, total])
	# The faction's emblem, tinted in its key colour, beside the item card, where the file exists.
	var scroll: ScrollContainer = page.get_node("Scroll")
	assert_int(scroll.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	assert_int(scroll.mouse_filter).is_not_equal(Control.MOUSE_FILTER_IGNORE)
	await _show(page, "barracks")
	var emblem: TextureRect = page.get_node("Emblem")
	assert_str(emblem.texture.resource_path).ends_with("icons/emblem_fossil.svg")
	assert_that(emblem.modulate).is_equal(Color(SIGNAL_MID))
	assert_str((page.get_node("Icon") as TextureRect).texture.resource_path).ends_with(
		"item_barracks.svg"
	)


func test_a_building_is_shown_at_three_zooms_in_two_triads_on_grass_and_sand() -> void:
	var gallery: Control = await _open_gallery()
	var page: Control = await _build_page(gallery)
	for id: String in _fossil_ids():
		await _show(page, id)
		for ground: String in ["Grass", "Sand"]:
			var rows: Node = page.get_node("Scroll/Content/" + ground)
			assert_array(rows.get_children().map(_node_name)).override_failure_message(id).is_equal(
				SECTIONS
			)
			for section: Node in rows.get_children():
				assert_str((section.get_child(0) as Label).text).is_equal(
					"%s, zoom %s" % [_triad_name(section), _zoom(section)]
				)
				assert_array(section.get_node("Scene").get_children().map(_node_name)).is_equal(
					["Ground", "Rigs"]
				)
		# Six sections tall: a list to drag, with room to scroll on the tightest phone.
		assert_float((page.get_node("Scroll/Content") as Control).custom_minimum_size.y).is_greater(
			720.0
		)


## The scene is what a match draws: the diamonds of the ground under a y-sorted node of three rigs,
## each Shadow (under every body), Hull and, for the tank, the Turret or, for the defence, the Head
## at its mount, all regions of the one atlas at `0.5 / bake_scale` times the zoom.
func test_the_scene_is_a_sorted_world_of_one_building_and_two_tanks_on_iso_ground() -> void:
	var gallery: Control = await _open_gallery()
	var page: Control = await _build_page(gallery)
	var checked: int = 0
	for id: String in ["barracks", "defence_turret", "headquarters"]:
		await _show(page, id)
		var index: IsoIndex = load(IsoIndex.PATH) as IsoIndex
		var sheet: IsoSheetDef = index.sheet(StringName(id))
		var tank: IsoSheetDef = index.sheet(&"heavy_tank")
		var n: int = sheet.footprint
		for ground: String in ["Grass", "Sand"]:
			for section: Node in page.get_node("Scroll/Content/" + ground).get_children():
				var zoom: float = _zoom(section)
				var triad: int = TRIAD_OF[_triad_name(section)]
				var scene: Node2D = section.get_node("Scene")
				var floor_tiles: Node2D = scene.get_node("Ground")
				assert_int(floor_tiles.z_index).is_equal(-2)
				assert_int(floor_tiles.get_child_count()).is_equal((n + 2) * (n + 2))
				for tile: Sprite2D in floor_tiles.get_children():
					var cell: PackedStringArray = tile.name.trim_prefix("Cell").split("_")
					var variant: String = "ab"[(int(cell[0]) + int(cell[1])) & 1]
					var want: String = "%s_%s.svg" % [ground.to_lower(), variant]
					assert_str(tile.texture.resource_path).override_failure_message(id).ends_with(
						"ground/" + want
					)
					assert_vector(tile.scale).is_equal(Vector2.ONE * zoom)
				var rigs: Node2D = scene.get_node("Rigs")
				assert_bool(rigs.y_sort_enabled).is_true()
				assert_array(rigs.get_children().map(_node_name)).is_equal(
					["Building", "Front", "Behind"]
				)
				var building: Node2D = rigs.get_node("Building")
				var front: Node2D = rigs.get_node("Front")
				var behind: Node2D = rigs.get_node("Behind")
				assert_vector(building.position).is_equal(Vector2.ZERO)
				# In front means south of the building's centre on the screen, behind north of it
				# (the sort key of `WorldSort`), and the tank in front stands clear of the footprint.
				assert_float(front.position.y).is_greater(building.position.y)
				assert_float(behind.position.y).is_less(building.position.y)
				assert_vector(front.position).is_equal_approx(
					IsoProjection.ground_to_px(n * 500 + 700, n * 500 + 700) * zoom,
					Vector2(0.01, 0.01)
				)
				assert_float(front.position.y).is_greater(16.0 * n * zoom)
				assert_float(behind.position.y).is_less(-16.0 * n * zoom)
				var parts: Array = (
					["Shadow", "Hull", "Head"] if id == "defence_turret" else ["Shadow", "Hull"]
				)
				assert_array(building.get_children().map(_node_name)).is_equal(parts)
				for unit: Node2D in [front, behind]:
					assert_array(unit.get_children().map(_node_name)).is_equal(
						["Shadow", "Hull", "Turret"]
					)
				_check_rig(page, building, sheet, -1, zoom, triad)
				_check_rig(page, front, tank, 6, zoom, triad)
				_check_rig(page, behind, tank, 6, zoom, triad)
				checked += 1
	assert_int(checked).is_equal(3 * 2 * SECTIONS.size())


## The Redoubt's head faces down the screen, at the tank in front, and stands at its mount.
func test_the_defences_head_faces_the_tank_in_front_at_its_mount() -> void:
	var gallery: Control = await _open_gallery()
	var page: Control = await _build_page(gallery)
	await _show(page, "defence_turret")
	var sheet: IsoSheetDef = (load(IsoIndex.PATH) as IsoIndex).sheet(&"defence_turret")
	for section: Node in page.get_node("Scroll/Content/Grass").get_children():
		var zoom: float = _zoom(section)
		var triad: int = TRIAD_OF[_triad_name(section)]
		var head: Sprite2D = section.get_node("Scene/Rigs/Building/Head")
		var atlas: IsoAtlas = page.atlas
		assert_that(head.region_rect).is_equal(
			Rect2(atlas.region(&"defence_turret", &"head", 8, triad))
		)
		assert_vector(head.position).is_equal_approx(
			sheet.mount(0) * ART_SCALE * zoom, Vector2.ONE * 0.01
		)
		assert_bool(head.region_rect.has_area()).is_true()


## Signal in the first row of each zoom and Arktisk in the second: the key triad of the Derrick
## League's frames is replaced by the player's in the atlas, so the Signal hull has Signal's mid
## colour and none of Arktisk's, and the Arktisk hull the other way round.
func test_the_two_triads_are_the_two_players_of_the_atlas() -> void:
	var gallery: Control = await _open_gallery()
	var page: Control = await _build_page(gallery)
	await _show(page, "headquarters")
	var sheet: IsoSheetDef = (load(IsoIndex.PATH) as IsoIndex).sheet(&"headquarters")
	var image: Image = page.atlas.texture().get_image()
	var signal_region: Rect2i = page.atlas.region(&"headquarters", &"hull", -1, 0)
	var arktisk_region: Rect2i = page.atlas.region(&"headquarters", &"hull", -1, 1)
	assert_bool(signal_region != arktisk_region).is_true()
	assert_vector(Vector2(signal_region.size)).is_equal(
		Vector2(sheet.frame_size(&"hull")) * page.atlas.bake_scale()
	)
	assert_int(_pixels_near(image, signal_region, SIGNAL_MID)).is_greater(100)
	assert_int(_pixels_near(image, signal_region, ARKTISK_MID)).is_equal(0)
	assert_int(_pixels_near(image, arktisk_region, ARKTISK_MID)).is_greater(100)
	assert_int(_pixels_near(image, arktisk_region, SIGNAL_MID)).is_equal(0)
	# And the sections use them: the first of each zoom is Signal's, the second Arktisk's.
	for ground: String in ["Grass", "Sand"]:
		for section: Node in page.get_node("Scroll/Content/" + ground).get_children():
			var hull: Sprite2D = section.get_node("Scene/Rigs/Building/Hull")
			var triad: int = TRIAD_OF[_triad_name(section)]
			assert_that(hull.region_rect).is_equal(
				Rect2(page.atlas.region(&"headquarters", &"hull", -1, triad))
			)


## Every scene is inside its half of the screen and under the one before it, and the first is
## clear of the corner buttons, on the tightest 16:9 phone, a wider one and a 4:3 tablet.
func test_every_scene_fits_its_ground_and_keeps_clear_of_the_buttons_at_three_sizes() -> void:
	for base: Vector2 in BASES:
		var gallery: Control = await _open_gallery(base)
		var page: Control = await _build_page(gallery)
		var problems: Array[String] = []
		var corners: Array[Rect2] = _corner_buttons(gallery)
		for id: String in ["barracks", "defence_turret", "headquarters", "fossil_strike"]:
			await _show(page, id)
			for ground_name: String in ["Grass", "Sand"]:
				var ground: ColorRect = page.get_node("Scroll/Content/" + ground_name)
				var half: Rect2 = ground.get_global_rect()
				var last_bottom: float = -INF
				for section: Node in ground.get_children():
					var box: Rect2 = _scene_box(section.get_node("Scene"))
					var label: String = "%s %s %s" % [id, ground_name, section.name]
					if box.position.x < half.position.x or box.end.x > half.end.x:
						problems.append(label + " is outside its ground")
					if box.position.y < last_bottom - 0.5:
						problems.append(label + " overlaps the section before it")
					last_bottom = box.end.y
					if section == ground.get_child(0):
						for corner: Rect2 in corners:
							if box.intersects(corner):
								problems.append(label + " is under a button")
		assert_array(problems).override_failure_message(str(base)).is_empty()
		gallery.get_parent().free()


## Both factions' buildings build: the blockouts of the Lumen Accord stand beside the Derrick
## League's until the art row P104 replaces them, with the tank of their own faction.
func test_every_building_of_both_factions_builds_with_frames_for_every_sprite() -> void:
	var gallery: Control = await _open_gallery()
	var page: Control = await _build_page(gallery)
	var seen: int = 0
	for step: int in _building_paths().size():
		for sprite: Sprite2D in page.find_children("*", "Sprite2D", true, false):
			if sprite.name in [&"Shadow", &"Hull", &"Turret", &"Head"]:
				(
					assert_bool(sprite.region_rect.has_area())
					. override_failure_message(
						"%s %s" % [(page.get_node("Title") as Label).text, sprite.get_path()]
					)
					. is_true()
				)
				seen += 1
		assert_bool(page.atlas.is_empty()).is_false()
		page.get_node("Next").pressed.emit()
	assert_int(seen).is_greater_equal(16 * 2 * SECTIONS.size() * 8)


## The sprites of a rig are regions of the atlas, drawn at the zoom, standing on the rig's origin.
func _check_rig(
	page: Control, rig: Node2D, sheet: IsoSheetDef, dir: int, zoom: float, triad: int
) -> void:
	var atlas: IsoAtlas = page.atlas
	var scale_px: float = ART_SCALE * zoom / atlas.bake_scale()
	for sprite: Sprite2D in rig.get_children():
		var part: StringName = StringName(String(sprite.name).to_lower())
		var frame: int = dir if part in [&"shadow", &"hull"] else (8 if part == &"head" else dir)
		var region: Rect2i = atlas.region(sheet.art_id, part, frame, triad)
		var message: String = "%s %s" % [rig.get_path(), part]
		assert_bool(region.has_area()).override_failure_message(message).is_true()
		assert_that(sprite.region_rect).override_failure_message(message).is_equal(Rect2(region))
		assert_bool(sprite.region_enabled).is_true()
		assert_bool(sprite.centered).is_false()
		assert_object(sprite.texture).is_same(atlas.texture())
		assert_vector(sprite.scale).override_failure_message(message).is_equal_approx(
			Vector2.ONE * scale_px, Vector2.ONE * 0.0001
		)
		assert_vector(sprite.offset).override_failure_message(message).is_equal_approx(
			-Vector2(sheet.origin(part)) * atlas.bake_scale(), Vector2.ONE * 0.01
		)
		assert_int(sprite.z_index).override_failure_message(message).is_equal(
			-1 if part == &"shadow" else 0
		)


## The rectangle every sprite of a scene covers, in global coordinates.
func _scene_box(scene: Node2D) -> Rect2:
	var box: Rect2 = Rect2()
	var first: bool = true
	for sprite: Sprite2D in scene.find_children("*", "Sprite2D", true, false):
		var size: Vector2 = (
			sprite.region_rect.size if sprite.region_enabled else sprite.texture.get_size()
		)
		var rect: Rect2 = sprite.get_global_transform() * Rect2(sprite.offset, size)
		box = rect if first else box.merge(rect)
		first = false
	return box


func _pixels_near(image: Image, region: Rect2i, hex: String) -> int:
	var want: Color = Color(hex)
	var count: int = 0
	for y: int in range(region.position.y, region.end.y):
		for x: int in range(region.position.x, region.end.x):
			var pixel: Color = image.get_pixel(x, y)
			if (
				pixel.a > 0.95
				and absf(pixel.r - want.r) + absf(pixel.g - want.g) + absf(pixel.b - want.b) < 0.06
			):
				count += 1
	return count


func _zoom(section: Node) -> float:
	return ZOOM_OF[String(section.name).substr(
		0, String(section.name).length() - _triad_name(section).length()
	)]


func _triad_name(section: Node) -> String:
	return "Signal" if String(section.name).ends_with("Signal") else "Arktisk"


## The models of the buildings, in the page's order.
func _building_paths() -> Array[String]:
	var found: Array[String] = []
	for path: String in ArtGen.model_paths():
		if (load(path) as ArtModel).category == &"bld":
			found.append(path)
	return found


func _fossil_ids() -> Array[String]:
	var found: Array[String] = []
	for path: String in _building_paths():
		if path.contains("/fossil/"):
			found.append(path.get_file().get_basename())
	return found


## Presses Next until the page shows the building `id`.
func _show(page: Control, id: String) -> void:
	for step: int in _building_paths().size():
		if (page.get_node("Title") as Label).text.contains(": %s (" % id):
			return
		page.get_node("Next").pressed.emit()
	assert_str((page.get_node("Title") as Label).text).contains(": %s (" % id)
	await await_idle_frame()


func _corner_buttons(gallery: Control) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for button: Control in [gallery.get_node("%BackButton"), gallery.get_node("%PageButton")]:
		rects.append(button.get_global_rect())
	return rects


func _node_name(node: Node) -> String:
	return String(node.name)


func _assert_quit_on_go_back_restored() -> void:
	var restored: bool = get_tree().quit_on_go_back
	assert_bool(restored).override_failure_message("quit_on_go_back leaked").is_true()


## The page, shown: the page button pressed once from the Units page.
func _build_page(gallery: Control) -> Control:
	for step: int in BUILD_PAGE:
		gallery.get_node("%PageButton").pressed.emit()
	await await_idle_frame()
	return gallery.get_node("BuildingsPage")


## The gallery in a parent of `base_size`, the base size of a 16:9 phone unless given.
func _open_gallery(base_size: Vector2 = Vector2(1280, 720)) -> Control:
	var gallery: Control = auto_free((load(GALLERY_PATH) as PackedScene).instantiate())
	var parent: Control = auto_free(Control.new())
	parent.size = base_size
	add_child(parent)
	parent.add_child(gallery)
	await await_idle_frame()
	return gallery
