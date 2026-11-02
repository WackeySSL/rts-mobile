extends GdUnitTestSuite
## The Life page of the art gallery (plan row P135, STYLE.md "Gallery" and "Life effects"): the two
## life atlases whole, then a row for every kind of the region table with its frames at the three
## camera zooms on grass and on sand, laid out to fit at the three base sizes of the gallery. The
## atlases are in test_life_atlases.gd, the other pages in test_art_gallery_pages.gd.

const Gallery: GDScript = preload("res://game/view/art_gallery.gd")
const Life: GDScript = preload("res://game/view/art_gallery_life.gd")
const GALLERY_PATH: String = "res://scenes/dev/art_gallery.tscn"
## The tightest 16:9 phone, a wider one and a 4:3 tablet (the sizes of test_art_assets.gd).
const BASES: Array[Vector2] = [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 960)]
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
	assert_array(page.get_children().map(_node_name)).is_equal(["Grass", "Sand", "Scroll"])
	assert_that((page.get_node("Grass") as ColorRect).color).is_equal(
		Gallery.TERRAIN_COLORS[&"grass_b"]
	)
	assert_that((page.get_node("Sand") as ColorRect).color).is_equal(
		Gallery.TERRAIN_COLORS[&"sand"]
	)
	_turn_to(gallery, 1)
	assert_str((gallery.get_node("%PageButton") as Button).text).is_equal("Units")
	assert_bool(page.visible).is_false()


func test_the_rows_are_the_atlases_then_every_kind_of_the_table_in_order() -> void:
	var gallery: Control = await _open_gallery()
	_turn_to(gallery, LIFE_PAGE)
	var want: Array[String] = ["Spacer", "RowAtlases"]
	for kind: String in Life.LIFE_KINDS:
		want.append("Row" + kind.to_pascal_case())
	for kind: String in Life.STRIKE_KINDS:
		want.append("Row" + kind.to_pascal_case())
	var rows: Node = gallery.get_node("LifePage/Scroll/Rows")
	assert_array(rows.get_children().map(_node_name)).is_equal(want)
	assert_int(Life.LIFE_KINDS.size() + Life.STRIKE_KINDS.size()).is_equal(21)


func test_the_atlas_row_shows_both_atlases_whole_at_scale_1_on_each_ground() -> void:
	var gallery: Control = await _open_gallery()
	_turn_to(gallery, LIFE_PAGE)
	var row: Node = gallery.get_node("LifePage/Scroll/Rows/RowAtlases")
	assert_array(row.get_children().map(_node_name)).is_equal(["Grass", "Sand"])
	for ground: String in ["Grass", "Sand"]:
		var half: Node = row.get_node(ground)
		for atlas: String in ["LifeAtlas", "StrikeAtlas"]:
			var rect: TextureRect = half.get_node(atlas)
			assert_vector(rect.size).is_equal(rect.texture.get_size())
		assert_str((half.get_node("LifeAtlas") as TextureRect).texture.resource_path).ends_with(
			"fx/life_atlas.svg"
		)
		assert_str((half.get_node("StrikeAtlas") as TextureRect).texture.resource_path).ends_with(
			"fx/strike_atlas.svg"
		)
	assert_bool(row.get_node("Grass").has_node("Label")).is_true()
	assert_bool(row.get_node("Sand").has_node("Label")).is_false()


## Every frame is a region of the imported atlas, as big as the region in world px times the zoom,
## standing on the row's ground line, the kind named on the grass half only.
func test_each_kind_shows_its_frames_at_the_three_zooms_on_both_grounds() -> void:
	var gallery: Control = await _open_gallery()
	_turn_to(gallery, LIFE_PAGE)
	var shown: int = 0
	for atlas: String in ["life", "strike"]:
		var kinds: Dictionary[String, String] = (
			Life.LIFE_KINDS if atlas == "life" else Life.STRIKE_KINDS
		)
		var path: String = Life.LIFE_ART if atlas == "life" else Life.STRIKE_ART
		for kind: String in kinds:
			var spec: String = kinds[kind]
			var frames: int = Life.frame_count(spec)
			var row: Node = gallery.get_node("LifePage/Scroll/Rows/Row" + kind.to_pascal_case())
			var tallest: float = Life.region(spec).size.y * Life.MAX_ZOOM
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
						var box: Rect2i = Life.region(spec, frame)
						assert_str(texture.atlas.resource_path).is_equal(path)
						assert_that(texture.region).is_equal(Rect2(box))
						assert_vector(rect.size).is_equal(
							Vector2(box.size) * ZOOM_GROUPS[group_name]
						)
						assert_float(rect.position.y + rect.size.y).is_equal(tallest)
						shown += 1
	# 24 frames of the life atlas and 12 of the strike atlas, each on two grounds at three zooms.
	assert_int(shown).is_equal((3 + 3 + 2 + 2 + 2 + 2 + 4 + 3 + 3 + 12) * 2 * 3)


## Everything is inside its half, clear of the corner buttons and of the other frames and rows, at
## the three base sizes.
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
			if row.name == &"Spacer":
				continue
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
		# The two ground colours cover the halves of the page.
		var page: Rect2 = (gallery.get_node("LifePage") as Control).get_global_rect()
		assert_that((gallery.get_node("LifePage/Grass") as Control).get_global_rect()).is_equal(
			Rect2(page.position, Vector2(base.x / 2.0, base.y))
		)
		(
			assert_float(
				(gallery.get_node("LifePage/Sand") as Control).get_global_rect().position.x
			)
			. is_equal(base.x / 2.0)
		)
		gallery.get_parent().free()


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
