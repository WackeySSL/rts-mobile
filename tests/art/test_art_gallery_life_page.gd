extends GdUnitTestSuite
## The Life page of the art gallery (plan row P135, STYLE.md "Gallery" and "Life effects"): the two
## life atlases whole, then a row for every kind of the region table with its frames at the three
## camera zooms on grass and on sand, laid out to fit at the three base sizes of the gallery and to
## scroll sideways to the sand on a narrow screen. The regions the page draws are held to the cells
## STYLE.md's table implies (tests/art/life_art_support.gd), not to `LifeRegions` alone. The atlases
## are in test_life_atlases.gd, the other pages in test_art_gallery_pages.gd.

const Gallery: GDScript = preload("res://game/view/art_gallery.gd")
const Life: GDScript = preload("res://game/view/art_gallery_life.gd")
const Support: GDScript = preload("res://tests/art/life_art_support.gd")
const GALLERY_PATH: String = "res://scenes/dev/art_gallery.tscn"
## The tightest 16:9 phone, a wider one and a 4:3 tablet (the sizes of test_art_assets.gd).
const BASES: Array[Vector2] = [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 960)]
const PORTRAIT: Vector2 = Vector2(720, 1280)
const LIFE_PAGE: int = 7
const ZOOM_GROUPS: Dictionary[String, float] = {"Z075": 0.75, "Z100": 1.0, "Z150": 1.5}


## A gallery switches `SceneTree.quit_on_go_back` off while it is open and restores what it found,
## so galleries alive together restore it in the wrong order (see test_art_assets.gd).
func before_test() -> void:
	_assert_quit_on_go_back_restored()


func after() -> void:
	_assert_quit_on_go_back_restored()


func test_the_life_page_is_the_last_of_eight_and_is_built_when_the_button_first_shows_it() -> void:
	assert_array(Gallery.PAGES).is_equal(
		["Units", "Build", "Ground", "Icons", "Iso", "Terrain", "Hud", "Life"]
	)
	var gallery: Control = await _open_gallery()
	var page: Control = gallery.get_node("LifePage")
	assert_bool(page.visible).is_false()
	assert_int(page.get_child_count()).is_equal(0)
	_turn_to(gallery, LIFE_PAGE)
	assert_str((gallery.get_node("%PageButton") as Button).text).is_equal("Life")
	assert_bool(page.visible).is_true()
	assert_array(page.get_children().map(_node_name)).is_equal(["Scroll"])
	_turn_to(gallery, 1)
	assert_str((gallery.get_node("%PageButton") as Button).text).is_equal("Units")
	assert_bool(page.visible).is_false()


## The first row after the spacer, then one for every kind of the table in the guide's order; every
## half of every row is its ground.
func test_the_rows_are_the_atlases_then_every_kind_of_the_table_in_order() -> void:
	var gallery: Control = await _open_gallery()
	_turn_to(gallery, LIFE_PAGE)
	var want: Array[String] = ["Spacer", "RowAtlases"]
	for row: Dictionary in Support.table():
		want.append("Row" + String(row["kind"]).to_pascal_case())
	var rows: Node = gallery.get_node("LifePage/Scroll/Rows")
	assert_array(rows.get_children().map(_node_name)).is_equal(want)
	assert_int(want.size()).is_equal(23)
	for row: Node in rows.get_children():
		assert_array(row.get_children().map(_node_name)).is_equal(["Grass", "Sand"])
		assert_that((row.get_node("Grass") as ColorRect).color).is_equal(
			Gallery.TERRAIN_COLORS[&"grass_b"]
		)
		assert_that((row.get_node("Sand") as ColorRect).color).is_equal(
			Gallery.TERRAIN_COLORS[&"sand"]
		)


func test_the_atlas_row_shows_both_atlases_whole_at_scale_1_on_each_ground() -> void:
	var gallery: Control = await _open_gallery()
	_turn_to(gallery, LIFE_PAGE)
	var row: Node = gallery.get_node("LifePage/Scroll/Rows/RowAtlases")
	for ground: String in ["Grass", "Sand"]:
		var half: Node = row.get_node(ground)
		for atlas: String in ["LifeAtlas", "StrikeAtlas"]:
			var rect: TextureRect = half.get_node(atlas)
			assert_vector(rect.size).is_equal(rect.texture.get_size())
		assert_str((half.get_node("LifeAtlas") as TextureRect).texture.resource_path).is_equal(
			LifeRegions.LIFE_ART
		)
		assert_str((half.get_node("StrikeAtlas") as TextureRect).texture.resource_path).is_equal(
			LifeRegions.STRIKE_ART
		)
	assert_bool(row.get_node("Grass").has_node("Label")).is_true()
	assert_bool(row.get_node("Sand").has_node("Label")).is_false()


## Every frame is the region STYLE.md's table implies for it (frame 0 moved by frame x step), of the
## atlas the table names, as big as the region in world px times the zoom, standing on the row's
## ground line, the kind named on the grass half only. One texture is made for each frame and the
## three zooms and both grounds share it.
func test_each_kind_shows_its_frames_at_the_three_zooms_on_both_grounds() -> void:
	var gallery: Control = await _open_gallery()
	_turn_to(gallery, LIFE_PAGE)
	var shown: int = 0
	var textures: Dictionary[AtlasTexture, bool] = {}
	for row_data: Dictionary in Support.table():
		var kind: String = row_data["kind"]
		var frames: int = row_data["frames"]
		var row: Node = gallery.get_node("LifePage/Scroll/Rows/Row" + kind.to_pascal_case())
		var tallest: float = (row_data["rect"] as Rect2i).size.y * 1.5
		var path: String = (
			LifeRegions.LIFE_ART if row_data["atlas"] == "life" else LifeRegions.STRIKE_ART
		)
		for ground: String in ["Grass", "Sand"]:
			var half: Node = row.get_node(ground)
			assert_bool(half.has_node("Label")).is_equal(ground == "Grass")
			if ground == "Grass":
				assert_str((half.get_node("Label") as Label).text).is_equal(
					"%s (%d)" % [kind, frames]
				)
			for group_name: String in ZOOM_GROUPS:
				var group: Node = half.get_node(group_name)
				assert_int(group.get_child_count()).is_equal(frames)
				for frame: int in frames:
					var rect: TextureRect = group.get_node("F%d" % frame)
					var texture: AtlasTexture = rect.texture as AtlasTexture
					var box: Rect2i = _cell(row_data, frame)
					assert_str(texture.atlas.resource_path).is_equal(path)
					(
						assert_that(texture.region)
						. override_failure_message("%s %d" % [kind, frame])
						. is_equal(Rect2(box))
					)
					assert_vector(rect.size).is_equal(Vector2(box.size) * ZOOM_GROUPS[group_name])
					assert_float(rect.position.y + rect.size.y).is_equal(tallest)
					textures[texture] = true
					shown += 1
	# 24 frames of the life atlas and 12 of the strike atlas, each on two grounds at three zooms.
	assert_int(shown).is_equal(36 * 2 * 3)
	assert_int(textures.size()).is_equal(36)


## Everything is inside its half, clear of the corner buttons and of the other frames and rows, at
## the three base sizes; the halves are the same width and meet.
func test_the_life_page_fits_each_half_and_keeps_clear_of_the_buttons_at_three_sizes() -> void:
	for base: Vector2 in BASES:
		var gallery: Control = await _open_gallery(base)
		_turn_to(gallery, LIFE_PAGE)
		await await_idle_frame()
		await await_idle_frame()
		var problems: Array[String] = []
		var rows: Node = gallery.get_node("LifePage/Scroll/Rows")
		var above: float = -1.0
		for row: Node in rows.get_children():
			var grass: Control = row.get_node("Grass")
			var sand: Control = row.get_node("Sand")
			var grass_rect: Rect2 = grass.get_global_rect()
			var sand_rect: Rect2 = sand.get_global_rect()
			if not is_equal_approx(grass_rect.size.x, sand_rect.size.x):
				problems.append("%s halves differ in width" % row.name)
			if not is_equal_approx(grass_rect.end.x, sand_rect.position.x):
				problems.append("%s halves do not meet" % row.name)
			if grass_rect.position.y < above:
				problems.append("%s overlaps the row above" % row.name)
			above = grass_rect.end.y
			for half: Control in [grass, sand]:
				problems.append_array(_clashes(half, str(row.name)))
		var first: Control = rows.get_node("RowAtlases/Grass")
		# The first row starts below the corner buttons; the rows after it scroll under them.
		for button: Rect2 in _button_rects(gallery):
			if first.get_global_rect().intersects(button):
				problems.append("the first row is over a button")
		(
			assert_array(problems)
			. override_failure_message(str(base) + str(problems.slice(0, 4)))
			. is_empty()
		)
		gallery.get_parent().free()


## The page scrolls (it is longer than the screen), and on a narrow screen it scrolls sideways too,
## so the sand half is reachable.
func test_the_page_scrolls_up_and_down_and_on_a_narrow_screen_sideways() -> void:
	var wide: Control = await _open_gallery()
	_turn_to(wide, LIFE_PAGE)
	await await_idle_frame()
	await await_idle_frame()
	var scroll: ScrollContainer = wide.get_node("LifePage/Scroll")
	assert_float(scroll.get_v_scroll_bar().max_value).is_greater(scroll.get_v_scroll_bar().page)
	assert_float(scroll.get_h_scroll_bar().max_value).is_less_equal(scroll.get_h_scroll_bar().page)
	wide.get_parent().free()
	var narrow: Control = await _open_gallery(PORTRAIT)
	_turn_to(narrow, LIFE_PAGE)
	await await_idle_frame()
	await await_idle_frame()
	scroll = narrow.get_node("LifePage/Scroll")
	assert_float(scroll.get_h_scroll_bar().max_value).is_greater(scroll.get_h_scroll_bar().page)
	var sand: Control = narrow.get_node("LifePage/Scroll/Rows/RowAtlases/Sand")
	assert_float(sand.get_global_rect().end.x).is_greater(PORTRAIT.x)
	narrow.get_parent().free()


## Frames and labels of `half` that are outside it or over one another.
func _clashes(half: Control, row_name: String) -> Array[String]:
	var found: Array[String] = []
	var box: Rect2 = half.get_global_rect()
	var seen: Array[Rect2] = []
	var things: Array[Node] = half.find_children("*", "TextureRect", true, false)
	things.append_array(half.find_children("*", "Label", true, false))
	for thing: Node in things:
		var rect: Rect2 = (thing as Control).get_global_rect()
		if not box.encloses(rect):
			found.append("%s %s is outside its half" % [row_name, thing.get_path()])
		for other: Rect2 in seen:
			if rect.grow(-0.5).intersects(other.grow(-0.5)):
				found.append("%s %s overlaps %s" % [row_name, thing.get_path(), other])
		seen.append(rect)
	return found


## The cell of frame `frame` of a row of the table: frame 0 moved right by frame x step.
func _cell(row: Dictionary, frame: int) -> Rect2i:
	var box: Rect2i = row["rect"]
	return Rect2i(box.position + Vector2i(frame * row["step"], 0), box.size)


func _turn_to(gallery: Control, steps: int) -> void:
	for step: int in steps:
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
