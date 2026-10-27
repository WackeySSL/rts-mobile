extends GdUnitTestSuite
## The Terrain page of the art gallery (plan row P105): the iso ground, the field stages, the
## wellhead and the crater on the off-map colour, at gameplay zoom. The tiles are the imported
## textures, so what the page shows is what a match will draw; the art is in test_ground_art.gd.

const Support: GDScript = preload("res://tests/art/ground_art_support.gd")
const TerrainPage: GDScript = preload("res://game/view/art_gallery_ground.gd")
const GALLERY_PATH: String = "res://scenes/dev/art_gallery.tscn"
const TERRAIN_PAGE: int = 5
const BASE: Vector2 = Vector2(1280, 720)
const CONTENT: String = "Scroll/Content/"


## A gallery switches `SceneTree.quit_on_go_back` off while it is open and restores what it found,
## so galleries alive together restore it in the wrong order (see test_art_assets.gd).
func before_test() -> void:
	_assert_quit_on_go_back_restored()


func after() -> void:
	_assert_quit_on_go_back_restored()


func test_the_terrain_page_is_built_when_first_shown_and_sits_on_the_off_map_colour() -> void:
	var gallery: Control = await _open_gallery()
	var page: Control = gallery.get_node("TerrainPage")
	assert_bool(page.visible).is_false()
	assert_int(page.get_child_count()).is_equal(0)
	_show(gallery)
	await await_idle_frame()
	assert_bool(page.visible).is_true()
	assert_str((gallery.get_node("%PageButton") as Button).text).is_equal("Terrain")
	var back: ColorRect = page.get_node("OffMap")
	assert_that(back.color).is_equal(Color("16191D"))
	assert_that(back.color).is_equal(TerrainPage.OFF_MAP_COLOR)
	# The page is opaque: the units page below it shows through nowhere.
	assert_that(back.get_rect().size).is_equal(page.get_rect().size)
	var names: Array[StringName] = []
	for child: Node in page.get_node(CONTENT.trim_suffix("/")).get_children():
		if not child is Label:
			names.append(child.name)
	assert_array(names).is_equal([&"Patch", &"Map", &"Fields", &"Props"])


func test_the_patch_is_six_terrains_of_six_cells_with_a_and_b_alternating_in_the_diamond_grid(
) -> void:
	var gallery: Control = await _open_gallery()
	var patch: Node2D = _show(gallery).get_node(CONTENT + "Patch")
	assert_int(patch.get_child_count()).is_equal(36)
	var first: Vector2 = (patch.get_child(0) as Sprite2D).position
	for row: int in Support.TERRAIN_IDS.size():
		for column: int in 6:
			var sprite: Sprite2D = patch.get_child(row * 6 + column)
			var path: String = Support.ground_path(
				Support.TERRAIN_IDS[row], "ab"[(column + row) % 2]
			)
			assert_object(sprite.texture).override_failure_message(path).is_same(load(path))
			# One cell is 64 x 32: +gx runs down and to the right, +gy down and to the left.
			var want: Vector2 = Vector2((column - row) * 32.0, (column + row) * 16.0)
			assert_vector(sprite.position - first).override_failure_message(path).is_equal(want)
			assert_vector(sprite.texture.get_size()).is_equal(Vector2(64, 32))


func test_the_map_mixes_the_terrains_with_an_oil_and_a_gas_field_wellheads_and_two_craters(
) -> void:
	var gallery: Control = await _open_gallery()
	var map: Node2D = _show(gallery).get_node(CONTENT + "Map")
	var cells: int = 0
	var field_cells: int = 0
	for row: String in TerrainPage.MAP_ROWS:
		assert_int(row.length()).is_equal(12)
		cells += row.length()
		field_cells += row.count("o")
	assert_int(TerrainPage.MAP_ROWS.size()).is_equal(10)
	var overlays: Array[Sprite2D] = []
	var craters: Array[Sprite2D] = []
	var wellheads: Array[Node2D] = []
	for child: Node in map.get_children():
		if child is Node2D and String(child.name).begins_with("Wellhead"):
			wellheads.append(child)
		elif String(child.name).begins_with("Crater"):
			craters.append(child)
		elif String(child.name).begins_with("oil_") or String(child.name).begins_with("gas_"):
			overlays.append(child)
	assert_int(map.get_child_count()).is_equal(cells + field_cells + 2 + 2)
	assert_int(overlays.size()).is_equal(field_cells)
	# Oil left of column 6 and gas right of it; the stage steps full, half, dry with the column.
	for overlay: Sprite2D in overlays:
		var parts: PackedStringArray = String(overlay.name).split("_")
		var column: int = int(parts[2])
		assert_str(parts[0]).is_equal("oil" if column < 6 else "gas")
		assert_str(parts[1]).is_equal(["full", "half", "dry"][(2 * column) % 3])
		assert_object(overlay.texture).is_same(load(Support.field_path(parts[0], parts[1])))
	var stages: Dictionary[String, int] = {}
	for overlay: Sprite2D in overlays:
		stages[String(overlay.name).get_slice("_", 0) + String(overlay.name).get_slice("_", 1)] = 1
	assert_int(stages.size()).is_equal(6)
	(
		assert_array(craters.map(func(c: Sprite2D) -> float: return c.scale.x))
		. contains_exactly_in_any_order([1.0, 0.5])
	)
	for crater: Sprite2D in craters:
		assert_object(crater.texture).is_same(load(Support.DECALS_DIR + "/crater.svg"))
	assert_int(wellheads.size()).is_equal(2)
	for rig: Node2D in wellheads:
		assert_object((rig.get_node("Wellhead") as Sprite2D).texture).is_same(
			load(Support.FIELDS_DIR + "/wellhead.svg")
		)
		assert_object((rig.get_node("WellheadShadow") as Sprite2D).texture).is_same(
			load(Support.FIELDS_DIR + "/wellhead_shadow.svg")
		)
		# The anchors of STYLE.md, in imported px: the middle of the pad and of the shadow's pad.
		assert_vector((rig.get_node("Wellhead") as Sprite2D).offset).is_equal(Vector2(-28, -44))
		assert_vector((rig.get_node("WellheadShadow") as Sprite2D).offset).is_equal(
			Vector2(-28, -15.5)
		)


func test_the_fields_page_shows_each_stage_as_three_by_three_cells_over_the_ore_earth_on_grass(
) -> void:
	var gallery: Control = await _open_gallery()
	var blocks: Node2D = _show(gallery).get_node(CONTENT + "Fields")
	var names: Array[StringName] = []
	for block: Node in blocks.get_children():
		names.append(block.name)
	assert_array(names).is_equal(
		[&"OilFull", &"OilHalf", &"OilDry", &"GasFull", &"GasHalf", &"GasDry"]
	)
	for index: int in 6:
		var block: Node2D = blocks.get_child(index)
		var stage: String = ["oil_full", "oil_half", "oil_dry", "gas_full", "gas_half", "gas_dry"][index]
		assert_that((block.get_node("Grass") as ColorRect).color).is_equal(Color("6F8F57"))
		# The grass pad, nine cells of ore earth in a and b, then nine of the stage over them.
		assert_int(block.get_child_count()).is_equal(1 + 9 + 9)
		for row: int in 3:
			for column: int in 3:
				var earth: Sprite2D = block.get_child(1 + row * 3 + column)
				var overlay: Sprite2D = block.get_child(10 + row * 3 + column)
				var variant: String = "ab"[(column + row) % 2]
				assert_object(earth.texture).is_same(load(Support.ground_path("ore", variant)))
				assert_object(overlay.texture).is_same(
					load("%s/%s.svg" % [Support.FIELDS_DIR, stage])
				)
				assert_vector(overlay.position).is_equal(earth.position)


func test_the_props_swatches_hold_the_wellhead_at_the_three_camera_zooms_and_the_crater() -> void:
	var gallery: Control = await _open_gallery()
	var props: Control = _show(gallery).get_node(CONTENT + "Props")
	for swatch_name: String in ["GrassSwatch", "SandSwatch"]:
		var swatch: ColorRect = props.get_node(swatch_name)
		var want: Color = Color("6F8F57") if swatch_name == "GrassSwatch" else Color("CDB98F")
		assert_that(swatch.color).is_equal(want)
		var zooms: Array[float] = []
		var craters: int = 0
		for child: Node in swatch.get_children():
			if child is Node2D and String(child.name).begins_with("Wellhead"):
				zooms.append((child as Node2D).scale.x)
			elif child is Sprite2D:
				craters += 1
		assert_array(zooms).is_equal([0.75, 1.0, 1.5])
		assert_int(craters).is_equal(1)


## At the base size of a phone held the wide way: nothing under the two corner buttons, and
## everything inside the width of the page (the list scrolls up and down, not sideways).
func test_everything_is_clear_of_the_two_corner_buttons_and_inside_the_page_width() -> void:
	var gallery: Control = await _open_gallery(BASE)
	var page: Control = _show(gallery)
	await await_idle_frame()
	var corners: Array[Rect2] = [
		(gallery.get_node("%BackButton") as Control).get_global_rect(),
		(gallery.get_node("%PageButton") as Control).get_global_rect(),
	]
	var inside: Rect2 = Rect2(Vector2.ZERO, Vector2(BASE.x, 100000.0))
	var seen: int = 0
	for node: Node in page.find_children("*", "Sprite2D", true, false):
		var sprite: Sprite2D = node as Sprite2D
		var box: Rect2 = sprite.get_global_transform() * sprite.get_rect()
		seen += 1
		assert_bool(inside.encloses(box)).override_failure_message(str(box)).is_true()
		for corner: Rect2 in corners:
			assert_bool(box.intersects(corner)).override_failure_message(str(box)).is_false()
	var labels: Array[Rect2] = []
	for node: Node in page.find_children("*", "Label", true, false):
		var label: Label = node as Label
		for corner: Rect2 in corners:
			assert_bool(label.get_global_rect().intersects(corner)).is_false()
		for other: Rect2 in labels:
			(
				assert_bool(label.get_global_rect().intersects(other))
				. override_failure_message(label.text)
				. is_false()
			)
		labels.append(label.get_global_rect())
	assert_int(labels.size()).is_equal(3)
	assert_int(seen).is_greater(250)


func _open_gallery(base_size: Vector2 = BASE) -> Control:
	var gallery: Control = auto_free((load(GALLERY_PATH) as PackedScene).instantiate())
	var parent: Control = auto_free(Control.new())
	parent.size = base_size
	add_child(parent)
	parent.add_child(gallery)
	await await_idle_frame()
	return gallery


func _show(gallery: Control) -> Control:
	for step: int in TERRAIN_PAGE:
		gallery.get_node("%PageButton").pressed.emit()
	return gallery.get_node("TerrainPage")


func _assert_quit_on_go_back_restored() -> void:
	var restored: bool = get_tree().quit_on_go_back
	assert_bool(restored).override_failure_message("quit_on_go_back leaked").is_true()
