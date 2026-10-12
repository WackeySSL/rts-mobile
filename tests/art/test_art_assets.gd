extends GdUnitTestSuite
## STYLE.md rules a plain check can hold, the unit art that UnitLayer builds on (one canvas per
## unit, half import scale, grey team layers, no turret on a squad), the ring texture and the
## effects atlas that P40 and P44 copy numbers from, the terrain tiles and fog alpha that P36 and
## P47 copy, and the gallery's squads, rings and terrain patch.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const Gallery: GDScript = preload("res://game/view/art_gallery.gd")
const UNIT_ART: String = "res://assets/art/svg/units/%s_%s.svg"
const GALLERY_PATH: String = "res://scenes/dev/art_gallery.tscn"
const SIDE_PX: Dictionary[String, int] = {"light_tank": 64, "rifle_squad": 32, "rocket_squad": 32}
## Words the plain `grep` of STYLE.md forbids (comments too); the elements allowed besides `svg`.
const FORBIDDEN: Array[String] = ["text", "image", "filter", "mask", "href", "style", "script"]
const OK_TAGS: String = " g path rect circle ellipse polygon polyline line linearGradient stop "
const ATLAS_PATH: String = "res://assets/art/svg/fx/effects_atlas.svg"
## Each map tile as the style guide draws it, rows from the top: 0 is the tile's own colour, 1 and 2
## its `_b` and `_c` tone, x the grid (the base darkened by 10 %, each channel truncated, see
## GRID_HEX: 94 x 0.9 is 84). The rock's lit edge is drawn over the grid.
const PICTURES: Dictionary[StringName, String] = {
	&"grass": "xxxxxxxx/x0000000/x0000000/x0000000/x0000000/x0000000/x0000000/x0000000",
	&"grass_b": "xxxxxxxx/x0000000/x0000000/x0000000/x0000000/x0000000/x0000000/x0000000",
	&"sand": "xxxxxxxx/x0000000/x0000000/x0000000/x0000000/x0000000/x0000000/x0000000",
	&"scrub": "xxxxxxxx/x2110000/x1110000/x1110000/x0002110/x0001110/x0001110/x0000000",
	&"rock": "11111112/10000002/10000002/10000002/10000002/10000002/10000002/22222222",
	&"water": "xxxxxxxx/x0000000/x1111000/x0000000/x0000000/x0000000/x0001111/x0000000",
}
## The grid texel of each tile in the order of PICTURES (rock has none): the base colour darkened.
const GRID_HEX: String = "547042 63804e b8a680 465134 - 295471"
## Rec. 601 luminance of the 8-bit texels of a whole tile (STYLE.md): "mean spread fogged", the
## spread being the standard deviation and fogged the mean under the explored fog (alpha 140).
const GREYSCALE: Dictionary[StringName, String] = {
	&"grass": "107.2 4.9 48",
	&"grass_b": "123.9 5.7 56",
	&"sand": "181.7 8.1 82",
	&"scrub": "90.2 17.4 41",
	&"rock": "105.4 19.9 48",
	&"water": "83.6 8.0 38",
}
## The map patch of the gallery's terrain row, left to right, rows 0 and 1 (grass by x + y parity).
const PATCH_TILES: Array[Array] = [
	[&"grass", &"grass_b", &"scrub", &"scrub", &"grass", &"rock", &"water", &"sand"],
	[&"grass_b", &"grass", &"scrub", &"scrub", &"grass_b", &"rock", &"water", &"sand"],
]
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


func test_every_texel_of_the_map_tiles_is_the_picture_of_the_style_guide() -> void:
	assert_array(Gallery.TERRAIN_TILES.keys()).is_equal(PICTURES.keys())
	var wrong: Array[String] = []
	for id: StringName in PICTURES:
		var image: Image = Gallery.tile_image(Gallery.TERRAIN_TILES[id])
		var rows: PackedStringArray = PICTURES[id].split("/")
		for y: int in 8:
			for x: int in 8:
				var tone: String = rows[y][x]
				var hex: String = GRID_HEX.split(" ")[PICTURES.keys().find(id)]
				if tone != "x":
					var key: StringName = id
					if tone != "0":
						key = StringName("%s_%s" % [id, "b" if tone == "1" else "c"])
					hex = Gallery.TERRAIN_COLORS[key].to_html(false)
				if image.get_pixel(x, y).to_html(false) != hex:
					wrong.append("%s %d,%d" % [id, x, y])
	assert_array(wrong).is_empty()


func test_the_map_tiles_have_the_luminance_of_the_style_guide_and_scrub_and_rock_read_apart(
) -> void:
	var got: Dictionary[StringName, String] = {}
	var means: Dictionary[StringName, float] = {}
	var spreads: Dictionary[StringName, float] = {}
	for id: StringName in GREYSCALE:
		var image: Image = Gallery.tile_image(Gallery.TERRAIN_TILES[id])
		var lums: Array[float] = []
		for y: int in 8:
			for x: int in 8:
				var c: Color = image.get_pixel(x, y)
				lums.append(0.299 * c.r8 + 0.587 * c.g8 + 0.114 * c.b8)
		means[id] = lums.reduce(func(a: float, b: float) -> float: return a + b, 0.0) / 64.0
		var variance: float = 0.0
		for lum: float in lums:
			variance += (lum - means[id]) * (lum - means[id]) / 64.0
		spreads[id] = sqrt(variance)
		var fogged: int = roundi(means[id] * (1.0 - 140.0 / 255.0))
		got[id] = "%.1f %.1f %d" % [means[id], spreads[id], fogged]
	assert_dict(got).is_equal(GREYSCALE)
	# Scrub is 17 below the darker grass and has three times its spread (the acceptance item).
	assert_float(means[&"grass"] - means[&"scrub"]).is_greater_equal(17.0)
	assert_float(spreads[&"scrub"]).is_greater_equal(3.0 * spreads[&"grass_b"])
	# The rock's lit edge is lighter than any grass texel (127) and its shade edge darker (98).
	var rock: Image = Gallery.tile_image(Gallery.TERRAIN_TILES[&"rock"])
	assert_float(rock.get_pixel(3, 0).get_luminance() * 255.0).is_greater(127.1)
	assert_float(rock.get_pixel(7, 3).get_luminance() * 255.0).is_less(98.0)


func test_the_style_guide_lists_every_colour_key_with_its_hex_and_a_probe_texel() -> void:
	var section: String = _terrain_section()
	var row: RegEx = RegEx.create_from_string(
		"\\| `(\\w+)` \\| #([0-9A-F]{6}) \\|[^|]*\\| (\\d),(\\d) \\|"
	)
	var keys: Array[StringName] = []
	var wrong: Array[String] = []
	for found: RegExMatch in row.search_all(section):
		var key: StringName = StringName(found.get_string(1))
		keys.append(key)
		# The tile of a key is its terrain id: the key without `_b` or `_c`, but `grass_b` is a tile.
		var id: StringName = key
		if not Gallery.TERRAIN_TILES.has(key):
			id = StringName(String(key).left(-2))
		var image: Image = Gallery.tile_image(Gallery.TERRAIN_TILES[id])
		var probe: Color = image.get_pixel(int(found.get_string(3)), int(found.get_string(4)))
		var hex: String = Gallery.TERRAIN_COLORS[key].to_html(false)
		if found.get_string(2) != hex.to_upper() or probe.to_html(false) != hex:
			wrong.append(key)
	assert_array(wrong).is_empty()
	assert_array(keys).is_equal(Gallery.TERRAIN_COLORS.keys())
	for id: StringName in Gallery.TERRAIN_TILES:
		assert_str(section).contains("`%s`" % Gallery.TERRAIN_TILES[id])
	assert_str(section).contains("`grid_color = Color(0, 0, 0, %s)`" % Gallery.GRID_DARKEN)


func test_the_gallery_terrain_row_is_a_patch_of_map_tiles_with_the_fog_over_its_second_row(
) -> void:
	var gallery: Node = await _open_gallery()
	var row: Control = gallery.get_node("TerrainRow")
	assert_bool(row.is_visible_in_tree()).is_true()
	# Over both grounds, in the order frame, patch, squads, fog.
	assert_bool(row.get_index() > gallery.get_node("Sand").get_index()).is_true()
	var names: Array = row.get_children().map(func(c: Node) -> String: return c.name)
	assert_array([names[0], names[1], names[-1]]).is_equal(["Frame", "Patch", "ExploredFog"])
	var patch: TextureRect = row.get_node("Patch")
	var frame: ColorRect = row.get_node("Frame")
	var fog: ColorRect = row.get_node("ExploredFog")
	for control: Control in [frame, patch, fog]:
		assert_int(control.mouse_filter).override_failure_message(control.name).is_equal(
			Control.MOUSE_FILTER_IGNORE
		)
	assert_int(patch.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_vector(patch.texture.get_size()).is_equal(Vector2(64, 16))
	assert_vector(patch.size).is_equal(Vector2(512, 128))
	assert_vector(patch.position).is_equal(Vector2(-256, 0))
	assert_that(frame.get_rect()).is_equal(patch.get_rect().grow(4.0))
	assert_that(frame.color).is_equal(Color("1C2127"))
	var half: Vector2 = patch.size / Vector2(1, 2)
	assert_that(fog.get_rect()).is_equal(Rect2(patch.position + Vector2(0, half.y), half))
	assert_that(fog.color).is_equal(Color(0.0, 0.0, 0.0, 140.0 / 255.0))
	# Every 8x8 cell of the patch is the tile of its place.
	var image: Image = patch.texture.get_image()
	var wrong: Array[String] = []
	for y: int in 2:
		for x: int in 8:
			var cell: Image = image.get_region(Rect2i(8 * x, 8 * y, 8, 8))
			var tile: Image = Gallery.tile_image(Gallery.TERRAIN_TILES[PATCH_TILES[y][x]])
			if cell.get_data() != tile.get_data():
				wrong.append("%d,%d %s" % [x, y, PATCH_TILES[y][x]])
	assert_array(wrong).is_empty()


func test_the_gallery_patch_has_both_teams_squads_on_the_scrub_tiles_above_the_fog() -> void:
	var gallery: Node = await _open_gallery()
	var row: Control = gallery.get_node("TerrainRow")
	var patch: Rect2 = (row.get_node("Patch") as Control).get_global_rect()
	var fog: Control = row.get_node("ExploredFog")
	for column: int in [2, 3]:
		var tile: Rect2 = Rect2(patch.position + Vector2(64.0 * column, 0.0), Vector2(64, 64))
		var team: Color = Color("2F80ED") if column == 2 else Color("E5484D")
		for squad: String in ["RifleSquad", "RocketSquad"]:
			var rig: Node2D = row.get_node("%sScrub%d" % [squad, column])
			var inside: bool = tile.has_point(rig.global_position)
			assert_bool(inside).override_failure_message(rig.name).is_true()
			assert_bool(fog.get_global_rect().intersects(_box(rig.get_node("Hull")))).is_false()
			assert_that((rig.get_node("Team") as Sprite2D).modulate).is_equal(team)
			assert_bool(rig.get_index() < fog.get_index()).is_true()
	assert_int(row.find_children("*Scrub*", "Node2D", false, false).size()).is_equal(4)


## At the base size of a 16:9 phone (the tightest: 720 high), a wider one and a 4:3 tablet.
func test_the_gallery_terrain_row_is_inside_and_clear_of_the_back_button_atlases_and_sprites(
) -> void:
	for base: Vector2 in [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 960)]:
		var gallery: Control = await _open_gallery(base)
		var row: Control = gallery.get_node("TerrainRow")
		var frame: Rect2 = (row.get_node("Frame") as Control).get_global_rect()
		var avoid: Array[Rect2] = [(gallery.get_node("%BackButton") as Control).get_global_rect()]
		for ground: String in ["Grass", "Sand"]:
			avoid.append((gallery.get_node(ground + "/EffectsAtlas") as Control).get_global_rect())
		for label: Node in gallery.find_children("*", "Label", true, false):
			avoid.append((label as Control).get_global_rect())
		for sprite: Node in gallery.find_children("*", "Sprite2D", true, false):
			if not row.is_ancestor_of(sprite):
				avoid.append(_box(sprite))
		assert_int(avoid.size()).is_greater(20)
		var hits: Array[String] = []
		if not gallery.get_global_rect().encloses(frame):
			hits.append("outside")
		for box: Rect2 in avoid:
			if frame.intersects(box):
				hits.append(str(box))
		assert_array(hits).override_failure_message(str(base)).is_empty()


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


## The text of STYLE.md from the "Fog and terrain" heading to the next one.
func _terrain_section() -> String:
	var style: String = FileAccess.get_file_as_string("res://assets/art/STYLE.md")
	var start: int = style.find("## Fog and terrain")
	return style.substr(start, style.find("\n## ", start + 1) - start)


## The gallery in a parent of `base_size`, the base size of a 16:9 phone unless given.
func _open_gallery(base_size: Vector2 = Vector2(1280, 720)) -> Control:
	var gallery: Control = auto_free((load(GALLERY_PATH) as PackedScene).instantiate())
	var parent: Control = auto_free(Control.new())
	parent.size = base_size
	add_child(parent)
	parent.add_child(gallery)
	await await_idle_frame()
	return gallery
