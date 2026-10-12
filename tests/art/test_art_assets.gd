extends GdUnitTestSuite
## STYLE.md rules a plain check can hold, the unit art that UnitLayer builds on (one canvas per
## unit, half import scale, grey team layers, no turret on a squad), the ring texture and the
## effects atlas that P40 and P44 copy numbers from, and the gallery's squads and rings.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const UNIT_ART: String = "res://assets/art/svg/units/%s_%s.svg"
const GALLERY_PATH: String = "res://scenes/dev/art_gallery.tscn"
const SIDE_PX: Dictionary[String, int] = {"light_tank": 64, "rifle_squad": 32, "rocket_squad": 32}
## Words the plain `grep` of STYLE.md forbids (comments too); the elements allowed besides `svg`.
const FORBIDDEN: Array[String] = ["text", "image", "filter", "mask", "href", "style", "script"]
const OK_TAGS: String = " g path rect circle ellipse polygon polyline line linearGradient stop "
const ATLAS_PATH: String = "res://assets/art/svg/fx/effects_atlas.svg"
## Atlas regions in imported px (STYLE.md, Combat effects): burst, puff, flash, shell, rocket.
const REGIONS: Array[Rect2i] = [
	Rect2i(0, 0, 80, 80),
	Rect2i(84, 0, 56, 56),
	Rect2i(144, 0, 32, 32),
	Rect2i(84, 60, 16, 8),
	Rect2i(84, 72, 36, 12),
]
## The colours the atlas bakes in (STYLE.md): palette colours, no team colour.
const ATLAS_COLOURS: PackedStringArray = [
	"#1C2127", "#5B6670", "#7D8893", "#A9B4BE", "#F2B705", "#F5A524", "#FFD84D", "#FFFFFF"
]


func test_every_svg_follows_the_technical_rules() -> void:
	var files: Array[String] = FileScan.list_files("res://assets/art/svg", ".svg")
	assert_int(files.size()).is_greater_equal(9)
	var tag: RegEx = RegEx.create_from_string("<(?!svg)([a-zA-Z]+)")
	var canvas: RegEx = RegEx.create_from_string(
		'<svg[^>]* width="(\\d+)" height="(\\d+)" viewBox="0 0 (\\d+) (\\d+)"'
	)
	var opacity: RegEx = RegEx.create_from_string('opacity="[^"]*"')
	var two_decimals: RegEx = RegEx.create_from_string("\\d\\.\\d\\d")
	var problems: Array[String] = []
	for path: String in files:
		var text: String = FileAccess.get_file_as_string(path)
		if text.length() > 20480:
			problems.append(path + " is over 20 KB")
		for word: String in FORBIDDEN:
			if text.containsn(word):
				problems.append("%s has '%s'" % [path, word])
		for found: RegExMatch in tag.search_all(text):
			if not OK_TAGS.contains(" %s " % found.get_string(1)):
				problems.append("%s has <%s>" % [path, found.get_string(1)])
		var size: RegExMatch = canvas.search(text)
		if size == null or size.get_string(1) != size.get_string(3):
			problems.append(path + " width and viewBox disagree")
		elif size.get_string(2) != size.get_string(4):
			problems.append(path + " height and viewBox disagree")
		if two_decimals.search(opacity.sub(text, "", true)) != null:
			problems.append(path + " has a two-decimal coordinate")
	assert_array(problems).is_empty()


func test_unit_layers_are_one_canvas_at_half_scale_and_squads_have_no_turret() -> void:
	for unit: String in SIDE_PX:
		for layer: String in ["hull", "team"]:
			var size: Vector2 = (load(UNIT_ART % [unit, layer]) as Texture2D).get_size()
			assert_vector(size).override_failure_message(unit + layer).is_equal(
				Vector2.ONE * SIDE_PX[unit]
			)
	assert_bool(ResourceLoader.exists(UNIT_ART % ["rifle_squad", "turret"])).is_false()
	assert_bool(ResourceLoader.exists(UNIT_ART % ["rocket_squad", "turret"])).is_false()


func test_team_layers_hold_only_greys() -> void:
	var paths: Array[String] = FileScan.list_files("res://assets/art/svg/units", "_team.svg")
	assert_int(paths.size()).is_equal(SIDE_PX.size())
	for path: String in paths:
		var image: Image = (load(path) as Texture2D).get_image()
		image.convert(Image.FORMAT_RGBA8)
		var data: PackedByteArray = image.get_data()
		var colored: int = 0
		for i: int in range(0, data.size(), 4):
			colored += int(
				data[i + 3] > 0 and (data[i] != data[i + 1] or data[i + 1] != data[i + 2])
			)
		assert_int(colored).override_failure_message(path).is_equal(0)


func test_the_gallery_has_both_squads_in_all_four_slots_tinted_by_slot() -> void:
	var gallery: Node = await _open_gallery()
	for slot: String in ["Grass/SlotA", "Grass/SlotB", "Sand/SlotA", "Sand/SlotB"]:
		for squad: String in ["RifleSquad", "RocketSquad"]:
			var rig: Node = gallery.get_node("%s/%s" % [slot, squad])
			assert_int(rig.get_child_count()).is_equal(2)
			for layer: String in ["Hull", "Team"]:
				var texture: Texture2D = (rig.get_node(layer) as Sprite2D).texture
				assert_str(texture.resource_path).ends_with(
					"%s_%s.svg" % [squad.to_snake_case(), layer.to_lower()]
				)
			var team: Color = Color("2F80ED") if slot.ends_with("A") else Color("E5484D")
			var tint: Color = (rig.get_node("Team") as Sprite2D).modulate
			assert_that(tint).override_failure_message(slot).is_equal(team)


func test_the_gallery_squads_turn_and_repeat_in_a_row_at_the_camera_zoom_levels() -> void:
	var gallery: Node = await _open_gallery()
	var squad: Node2D = gallery.get_node("Grass/SlotA/RifleSquad")
	var before: float = squad.rotation
	gallery.call("_process", 0.5)
	assert_float(squad.rotation).is_not_equal(before)
	var levels: Array[float] = []
	for level: float in (load("res://data/input_settings.tres") as InputSettings).zoom_levels:
		levels.append_array([level, level])  # One rifle and one rocket rig per level.
	for ground: String in ["Grass", "Sand"]:
		var scales: Array[float] = []
		for rig: Node in gallery.get_node(ground + "/SquadZoomRow").get_children():
			scales.append((rig as Node2D).scale.x)
		scales.sort()
		assert_array(scales).override_failure_message(ground).is_equal(levels)


## RING_TEX_RADIUS_PX is 72: from the centre 62 px clear, 4 dark, 12 white (centred on 72), 4 dark,
## 2 clear. Along a row and along a column, so a squashed ring or a fill fails too.
func test_the_ring_texture_has_the_centre_line_radius_and_stroke_of_the_style_guide() -> void:
	var texture: Texture2D = load("res://assets/art/svg/ui/selection_ring.svg")
	assert_vector(texture.get_size()).is_equal(Vector2(168, 168))
	var image: Image = texture.get_image()
	var want: String = ".".repeat(62) + "DDDD" + "W".repeat(12) + "DDDD" + ".."
	for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
		var along: String = ""
		for i: int in 84:
			along += _ink(image.get_pixelv(Vector2i(84, 84) + step * i))
		assert_str(along).override_failure_message(str(step)).is_equal(want)


func test_the_effects_atlas_has_ink_at_the_centre_of_its_five_regions_and_nowhere_else() -> void:
	var texture: Texture2D = load(ATLAS_PATH)
	assert_vector(texture.get_size()).is_equal(Vector2(176, 84))
	var image: Image = texture.get_image()
	var stray: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var inside: bool = REGIONS.any(
				func(r: Rect2i) -> bool: return r.has_point(Vector2i(x, y))
			)
			stray += int(image.get_pixel(x, y).a > 0.02 and not inside)
	assert_int(stray).is_equal(0)
	var hollow: Array[Rect2i] = REGIONS.filter(
		func(r: Rect2i) -> bool:
			var c: Vector2i = r.get_center()
			return image.get_pixel(c.x, c.y).a < 0.9
	)
	assert_array(hollow).is_empty()


func test_the_effects_atlas_bakes_in_palette_colours_only_and_the_rocket_faces_east() -> void:
	var foreign: PackedStringArray = PackedStringArray()
	var hex: RegEx = RegEx.create_from_string("#[0-9A-Fa-f]{6}")
	for found: RegExMatch in hex.search_all(FileAccess.get_file_as_string(ATLAS_PATH)):
		if not ATLAS_COLOURS.has(found.get_string().to_upper()):
			foreign.append(found.get_string())
	assert_array(foreign).is_empty()
	# The yellow flame core trails 7 px behind the rocket's centre, the orange nose leads 7 px.
	var image: Image = (load(ATLAS_PATH) as Texture2D).get_image()
	var centre: Vector2i = REGIONS[4].get_center()
	assert_that(image.get_pixelv(centre - Vector2i(7, 0))).is_equal(Color("FFD84D"))
	assert_that(image.get_pixelv(centre + Vector2i(7, 0))).is_equal(Color("F5A524"))


func test_the_gallery_ring_row_draws_the_team_a_ring_under_the_hull_at_31_5_35_2_and_52_8_px(
) -> void:
	var gallery: Node = await _open_gallery()
	for ground: String in ["Grass", "Sand"]:
		var radii: Array[float] = []
		for rig: Node in gallery.get_node(ground + "/RingRow").get_children():
			var ring: Sprite2D = rig.get_child(0) as Sprite2D
			assert_str(String(ring.name)).is_equal("Ring")
			assert_str(ring.texture.resource_path).ends_with("ui/selection_ring.svg")
			assert_bool(ring.is_visible_in_tree()).is_true()
			assert_that(ring.modulate).is_equal(Color.WHITE)
			assert_that((rig.get_node("Team") as Sprite2D).modulate).is_equal(Color("2F80ED"))
			radii.append(snappedf((rig as Node2D).scale.x * ring.scale.x * 72.0, 0.01))
		radii.sort()
		assert_str(str(radii)).override_failure_message(ground).is_equal("[31.5, 35.2, 52.8]")


func test_the_gallery_keeps_every_ring_clear_of_the_other_sprites() -> void:
	var gallery: Node = await _open_gallery()
	var sprites: Array[Node] = gallery.find_children("*", "Sprite2D", true, false)
	var rings: Array[Node] = gallery.find_children("Ring", "Sprite2D", true, false)
	assert_int(rings.size()).is_equal(6)
	for ring: Node in rings:
		for other: Node in sprites:
			if other.get_parent() != ring.get_parent():
				(
					assert_bool(_box(ring).intersects(_box(other)))
					. override_failure_message("%s over %s" % [ring.get_path(), other.get_path()])
					. is_false()
				)


func test_each_ground_carries_the_atlas_at_scale_1_clear_of_the_back_button_and_the_sprites(
) -> void:
	var gallery: Node = await _open_gallery()
	var back: Rect2 = (gallery.get_node("%BackButton") as Control).get_global_rect()
	for ground_name: String in ["Grass", "Sand"]:
		var ground: Control = gallery.get_node(ground_name)
		var atlas: TextureRect = ground.get_node("EffectsAtlas") as TextureRect
		assert_vector(atlas.texture.get_size()).is_equal(Vector2(176, 84))
		assert_vector(atlas.scale).is_equal(Vector2.ONE)
		var box: Rect2 = atlas.get_global_rect()
		assert_vector(box.size).is_equal(Vector2(176, 84))
		assert_bool(ground.get_global_rect().encloses(box)).is_true()
		assert_bool(box.intersects(back)).override_failure_message(ground_name).is_false()
		for sprite: Node in gallery.find_children("*", "Sprite2D", true, false):
			(
				assert_bool(box.intersects(_box(sprite)))
				. override_failure_message("%s over %s" % [ground_name, sprite.get_path()])
				. is_false()
			)


## One character per pixel: clear, white, dark (#1C2127, luminance 0.127) or anything else. The
## rasteriser antialiases stroke edges, so the match is by luminance.
func _ink(pixel: Color) -> String:
	if pixel.a < 0.05:
		return "."
	if pixel.a < 0.95:
		return "?"
	if pixel.get_luminance() > 0.95:
		return "W"
	return "D" if absf(pixel.get_luminance() - 0.127) < 0.05 else "?"


## The bounding box of a sprite on screen.
func _box(sprite: Node) -> Rect2:
	var node: Sprite2D = sprite as Sprite2D
	return node.get_global_transform() * node.get_rect()


func _open_gallery() -> Node:
	var gallery: Node = auto_free((load(GALLERY_PATH) as PackedScene).instantiate())
	add_child(gallery)
	await await_idle_frame()
	return gallery
