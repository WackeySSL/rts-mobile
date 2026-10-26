extends GdUnitTestSuite
## The style probe (STYLE.md, "Style probe (2026-10-26, not approved)"): its twelve SVG files follow
## the probe's own rules (the technical rules of the guide, except the 20 KB limit and the elements
## `radialGradient`, `clipPath`, `defs` and `use`) and import at half scale, its team layers hold
## only greys, and the Probe page of the art gallery shows A, B and C in three labelled columns with
## both team colours on grass and sand, builds without orphans and keeps its titles clear of the
## corner buttons.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const Gallery: GDScript = preload("res://game/view/art_gallery.gd")
const Probe: GDScript = preload("res://game/view/art_gallery_probe.gd")
const GALLERY_PATH: String = "res://scenes/dev/art_gallery.tscn"
const PROBE_DIR: String = "res://assets/art/svg/probe"
const PROBE_PAGE: int = 5
## The tightest 16:9 phone, a wider one and a 4:3 tablet (the sizes of test_art_assets.gd).
const BASES: Array[Vector2] = [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 960)]
const TEAM_A: Color = Color("2F80ED")
const TEAM_B: Color = Color("E5484D")
## The canvas of each probe file in file px; the imported texture is half of it (import scale 0.5).
const CANVAS: Dictionary[String, Vector2i] = {
	"a_refinery_hull": Vector2i(384, 384),
	"a_refinery_team": Vector2i(384, 384),
	"b_refinery_hull": Vector2i(384, 480),
	"b_refinery_team": Vector2i(384, 480),
	"a_heavy_tank_hull": Vector2i(128, 128),
	"a_heavy_tank_team": Vector2i(128, 128),
	"a_heavy_tank_turret": Vector2i(128, 128),
	"a_grass_a": Vector2i(128, 128),
	"a_grass_b": Vector2i(128, 128),
	"a_sand_a": Vector2i(128, 128),
	"a_sand_b": Vector2i(128, 128),
	"a_ore": Vector2i(128, 128),
}
## The probe's own size limit. The guide's 20 KB holds for the shipped art; the oblique refinery
## and its texture need more, and STYLE.md says what a chosen direction would do about it.
const MAX_BYTES: int = 28672
## What a probe file may use. `pattern` is left out on purpose: the engine's SVG loader (ThorVG)
## draws nothing for it, so a file that used one would look right in an editor and empty in game.
const OK_TAGS: String = (
	" g path rect circle ellipse polygon polyline line linearGradient radialGradient stop "
	+ "defs clipPath use "
)
const FORBIDDEN_TAGS: Array[String] = [
	"text", "image", "filter", "foreignObject", "script", "style", "pattern", "mask", "a"
]
const BOX_SLACK: float = 0.01
## How far a sprite of the oblique refinery rises above its footprint: 480 - 384 px at import scale.
const B_RISE_PX: float = 48.0


## A gallery switches `SceneTree.quit_on_go_back` off while it is open and restores what it found,
## so galleries alive together restore it in the wrong order (see test_art_assets.gd).
func before_test() -> void:
	_assert_quit_on_go_back_restored()


func after() -> void:
	_assert_quit_on_go_back_restored()


func test_the_probe_folder_holds_the_twelve_files_and_each_follows_the_probe_rules() -> void:
	var files: Array[String] = FileScan.list_files(PROBE_DIR, ".svg")
	assert_int(files.size()).is_equal(CANVAS.size())
	var tag: RegEx = RegEx.create_from_string("<(?!svg)([a-zA-Z]+)")
	var canvas: RegEx = RegEx.create_from_string(
		'<svg[^>]* width="(\\d+)" height="(\\d+)" viewBox="0 0 (\\d+) (\\d+)"'
	)
	var href: RegEx = RegEx.create_from_string('href="([^"]*)"')
	var problems: Array[String] = []
	for path: String in files:
		var key: String = path.get_file().get_basename()
		if not CANVAS.has(key):
			problems.append(path + " is not in the probe's list")
			continue
		var text: String = FileAccess.get_file_as_string(path)
		if text.length() > MAX_BYTES:
			problems.append("%s is %d bytes, over %d" % [path, text.length(), MAX_BYTES])
		for found: RegExMatch in tag.search_all(text):
			var name: String = found.get_string(1)
			if FORBIDDEN_TAGS.has(name) or not OK_TAGS.contains(" %s " % name):
				problems.append("%s has <%s>" % [path, name])
		for found: RegExMatch in href.search_all(text):
			if not found.get_string(1).begins_with("#"):
				problems.append("%s has an external href %s" % [path, found.get_string(1)])
		for word: String in ["data:", "xlink", "<!ENTITY", "base64"]:
			if text.contains(word):
				problems.append("%s has '%s'" % [path, word])
		var size: RegExMatch = canvas.search(text)
		var want: Vector2i = CANVAS[key]
		if (
			size == null
			or Vector2i(int(size.get_string(1)), int(size.get_string(2))) != want
			or Vector2i(int(size.get_string(3)), int(size.get_string(4))) != want
		):
			problems.append("%s width, height and viewBox are not %s" % [path, str(want)])
		var texture: Texture2D = load(path) as Texture2D
		if texture == null:
			problems.append(path + " does not import")
		elif Vector2i(texture.get_size()) != want / 2:
			problems.append("%s imports at %s" % [path, str(texture.get_size())])
	assert_array(problems).is_empty()


func test_the_probe_team_layers_hold_only_greys_and_are_not_empty() -> void:
	var paths: Array[String] = FileScan.list_files(PROBE_DIR, "_team.svg")
	assert_int(paths.size()).is_equal(3)
	for path: String in paths:
		var image: Image = (load(path) as Texture2D).get_image()
		image.convert(Image.FORMAT_RGBA8)
		var data: PackedByteArray = image.get_data()
		var drawn: int = 0
		var coloured: int = 0
		for i: int in range(0, data.size(), 4):
			if data[i + 3] > 0:
				drawn += 1
				coloured += int(data[i] != data[i + 1] or data[i + 1] != data[i + 2])
		assert_int(coloured).override_failure_message(path).is_equal(0)
		# A team layer marks at least one pixel in a hundred of its canvas.
		assert_int(drawn).override_failure_message(path).is_greater(data.size() / 4 / 100)


func test_the_probe_page_has_three_labelled_columns_with_both_teams_on_both_grounds() -> void:
	var gallery: Control = await _open_gallery()
	_turn_to(gallery, PROBE_PAGE)
	assert_str((gallery.get_node("%PageButton") as Button).text).is_equal("Probe")
	var page: Control = gallery.get_node("ProbePage")
	assert_bool(page.visible).is_true()
	assert_array(page.get_children().map(_node_name)).is_equal(
		["ColumnA", "ColumnB", "ColumnC", "Statement"]
	)
	var titles: Dictionary[String, String] = {
		"ColumnA": "Realistic top-down",
		"ColumnB": "Oblique 3/4 buildings",
		"ColumnC": "Current",
	}
	var refinery: Dictionary[String, String] = {
		"ColumnA": "probe/a_refinery_",
		"ColumnB": "probe/b_refinery_",
		"ColumnC": "buildings/refinery_",
	}
	var tank: Dictionary[String, String] = {
		"ColumnA": "probe/a_heavy_tank_",
		"ColumnB": "probe/a_heavy_tank_",
		"ColumnC": "units/heavy_tank_",
	}
	for column: String in titles:
		var path: String = "ProbePage/" + column
		assert_str((gallery.get_node(path + "/Title") as Label).text).contains(titles[column])
		for ground: String in ["Grass", "Sand"]:
			var is_a: bool = ground == "Grass"
			var row_path: String = "%s/%s/Row" % [path, ground]
			var rig: Node2D = gallery.get_node(row_path + "/Refinery")
			_assert_rig(rig, is_a, refinery[column], ["Hull", "Team"], "%s %s" % [column, ground])
			for team: String in ["A", "B"]:
				var unit: Node2D = gallery.get_node("%s/HeavyTank%s" % [row_path, team])
				var label: String = "%s %s tank %s" % [column, ground, team]
				_assert_rig(unit, team == "A", tank[column], ["Hull", "Team", "Turret"], label)


func test_the_probe_tanks_turn_the_hull_to_two_headings_and_the_turrets_keep_turning() -> void:
	var gallery: Control = await _open_gallery()
	for column: String in ["ColumnA", "ColumnB", "ColumnC"]:
		var row: String = "ProbePage/%s/Grass/Row/" % column
		var tank_a: Node2D = gallery.get_node(row + "HeavyTankA")
		var tank_b: Node2D = gallery.get_node(row + "HeavyTankB")
		assert_float(tank_a.rotation).is_equal(0.0)
		assert_float(tank_b.rotation).is_equal_approx(deg_to_rad(150.0), 0.0001)
		var turret: Sprite2D = tank_a.get_node("Turret")
		var before: float = turret.rotation
		gallery.call("_process", 0.5)
		assert_float(turret.rotation).override_failure_message(column).is_not_equal(before)
		assert_float(tank_a.rotation).is_equal(0.0)


## The frame of a 3x3 footprint is the same 192 px box in every column and every ground; each
## refinery stands on its bottom edge. A and C fill the frame, B rises 48 px above it.
func test_each_refinery_stands_on_a_192_px_footprint_frame_and_only_b_rises_above_it() -> void:
	var gallery: Control = await _open_gallery()
	_turn_to(gallery, PROBE_PAGE)
	await await_idle_frame()
	for column: String in ["ColumnA", "ColumnB", "ColumnC"]:
		for ground: String in ["Grass", "Sand"]:
			var row: String = "ProbePage/%s/%s/Row/" % [column, ground]
			var frame: Rect2 = (gallery.get_node(row + "Footprint") as Control).get_global_rect()
			var hull: Sprite2D = gallery.get_node(row + "Refinery/Hull")
			var box: Rect2 = hull.get_global_transform() * hull.get_rect()
			var label: String = "%s %s" % [column, ground]
			assert_vector(frame.size).override_failure_message(label).is_equal(Vector2(192, 192))
			assert_float(box.size.x).override_failure_message(label).is_equal_approx(
				192.0, BOX_SLACK
			)
			assert_float(box.end.y).override_failure_message(label).is_equal_approx(
				frame.end.y, BOX_SLACK
			)
			assert_float(box.position.x).override_failure_message(label).is_equal_approx(
				frame.position.x, BOX_SLACK
			)
			var rise: float = B_RISE_PX if column == "ColumnB" else 0.0
			(
				assert_float(frame.position.y - box.position.y)
				. override_failure_message(label)
				. is_equal_approx(rise, BOX_SLACK)
			)


## One ore cell in each patch, between grass and sand, and the same twelve cells in every column:
## A and B on the probe's tiles, C on the flat colours of the map today and the ore tile of P91.
func test_each_patch_has_twelve_cells_with_one_ore_cell_between_grass_and_sand() -> void:
	var gallery: Control = await _open_gallery()
	var rows: Array[PackedStringArray] = Probe.patch_tokens()
	assert_int(rows.size() * rows[0].size()).is_equal(12)
	for column: String in ["ColumnA", "ColumnB", "ColumnC"]:
		var patch: Node = gallery.get_node("ProbePage/%s/Patch" % column)
		var cells: Array[Node] = patch.get_children().filter(
			func(node: Node) -> bool: return String(node.name).begins_with("Tile")
		)
		assert_int(cells.size()).override_failure_message(column).is_equal(12)
		var ore_cells: int = 0
		for y: int in rows.size():
			for x: int in rows[y].size():
				var cell: Control = patch.get_node("Tile%d_%d" % [x, y])
				var token: String = rows[y][x]
				assert_vector(cell.size).is_equal(Vector2(64, 64))
				if token == "o":
					ore_cells += 1
					assert_str((cell as TextureRect).texture.resource_path).ends_with(
						"ore/ore_3a.svg" if column == "ColumnC" else "probe/a_ore.svg"
					)
				elif column == "ColumnC":
					(
						assert_bool(cell is ColorRect)
						. override_failure_message(column + token)
						. is_true()
					)
				else:
					(
						assert_bool(cell is TextureRect)
						. override_failure_message(column + token)
						. is_true()
					)
		assert_int(ore_cells).override_failure_message(column).is_equal(1)
		# Grass to the left of the ore cell's row, sand to the right.
		assert_str(rows[1][2]).is_equal("o")
		assert_str(rows[1][1][0]).is_equal("g")
		assert_str(rows[1][3][0]).is_equal("s")


## The Back and Probe buttons cover 24 to 144 px from the top and the left or right edge; the title
## text of the outer columns stays clear of them at all three base sizes.
func test_the_probe_titles_keep_clear_of_the_corner_buttons_at_three_sizes() -> void:
	for base: Vector2 in BASES:
		var gallery: Control = await _open_gallery(base)
		_turn_to(gallery, PROBE_PAGE)
		await await_idle_frame()
		var buttons: Array[Rect2] = [
			(gallery.get_node("%BackButton") as Control).get_global_rect(),
			(gallery.get_node("%PageButton") as Control).get_global_rect(),
		]
		var spans: Array[Rect2] = []
		for column: String in ["ColumnA", "ColumnB", "ColumnC"]:
			var title: Label = gallery.get_node("ProbePage/%s/Title" % column)
			var font: Font = title.get_theme_font(&"font")
			var size: int = title.get_theme_font_size(&"font_size")
			var width: float = (
				font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			)
			var box: Rect2 = title.get_global_rect()
			var text: Rect2 = Rect2(
				box.get_center().x - width / 2.0, box.position.y, width, box.size.y
			)
			for button: Rect2 in buttons:
				(
					assert_bool(text.intersects(button))
					. override_failure_message("%s at %s" % [column, str(base)])
					. is_false()
				)
			for other: Rect2 in spans:
				assert_bool(text.intersects(other)).is_false()
			spans.append(text)
		gallery.get_parent().free()


func test_building_and_freeing_the_probe_page_leaves_no_orphan_nodes() -> void:
	var before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var page: Control = Control.new()
	Probe.build(page)
	assert_int(page.get_child_count()).is_equal(4)
	page.free()
	assert_int(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))).is_equal(before)


## A rig in the right team group with exactly `layers` as children, the texture of each from the
## `art` fragment of a file name, and the team tint on its `Team` layer.
func _assert_rig(
	rig: Node2D, is_a: bool, art: String, layers: Array[String], label: String
) -> void:
	var group: StringName = Gallery.TEAM_A_GROUP if is_a else Gallery.TEAM_B_GROUP
	assert_bool(rig.is_in_group(group)).override_failure_message(label).is_true()
	assert_array(rig.get_children().map(_node_name)).override_failure_message(label).is_equal(
		layers
	)
	for layer: String in layers:
		var texture: Texture2D = (rig.get_node(layer) as Sprite2D).texture
		assert_str(texture.resource_path).override_failure_message(label).contains(
			art + layer.to_lower()
		)
	(
		assert_that((rig.get_node("Team") as Sprite2D).modulate)
		. override_failure_message(label)
		. is_equal(TEAM_A if is_a else TEAM_B)
	)


func _turn_to(gallery: Control, page: int) -> void:
	for step: int in page:
		gallery.get_node("%PageButton").pressed.emit()


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
