extends RefCounted
## The Probe page of the art gallery (STYLE.md, "Style probe (2026-10-26, not approved)"): the
## refinery, the heavy tank and a ground patch in three directions, side by side at gameplay zoom
## (scale 1) with both team colours, so Michael can choose a look on his phone.
##
## Three columns, left to right: A "Realistic top-down", B "Oblique 3/4 buildings" and C "Current"
## (the P91 and P92 files, unchanged). Each column has a grass half (left) and a sand half (right).
## A and B stand on the probe's own ground tiles, C on the flat colours the map uses today. Per
## column, top to bottom: a title, the refinery (team A on grass, team B on sand) inside a frame
## that marks its 3x3 footprint, the heavy tank in both team colours on both grounds, and a ground
## patch of grass, sand and one ore cell. B's tank and ground are A's: B only changes the building.
##
## Every sprite is a rig `Node2D` in the team group with the layers `Hull`, `Team` and, for a tank,
## `Turret`, so the gallery's tint and turret turn find them like any other rig. The tanks stand at
## two headings to show that the hull may face any way. View-only: no sim, no `delta`.

const TEAM_A_GROUP: StringName = &"gallery_team_a"
const TEAM_B_GROUP: StringName = &"gallery_team_b"
const DIRECTIONS: Array[StringName] = [&"a", &"b", &"c"]
const TITLES: Dictionary[StringName, String] = {
	&"a": "A  Realistic top-down",
	&"b": "B  Oblique 3/4 buildings",
	&"c": "C  Current (P91, P92)",
}
const CAPTIONS: Dictionary[StringName, String] = {
	&"a": "frame = 3x3 footprint",
	&"b": "frame = 3x3 footprint, the sprite rises above it",
	&"c": "frame = 3x3 footprint",
}
const REFINERY_ART: Dictionary[StringName, String] = {
	&"a": "res://assets/art/svg/probe/a_refinery_%s.svg",
	&"b": "res://assets/art/svg/probe/b_refinery_%s.svg",
	&"c": "res://assets/art/svg/buildings/refinery_%s.svg",
}
## B changes the buildings only, so its tank is A's.
const TANK_ART: Dictionary[StringName, String] = {
	&"a": "res://assets/art/svg/probe/a_heavy_tank_%s.svg",
	&"b": "res://assets/art/svg/probe/a_heavy_tank_%s.svg",
	&"c": "res://assets/art/svg/units/heavy_tank_%s.svg",
}
## The patch tiles by token: grass and sand each in two variants, and one ore cell.
const TILE_ART: Dictionary[String, String] = {
	"g0": "res://assets/art/svg/probe/a_grass_a.svg",
	"g1": "res://assets/art/svg/probe/a_grass_b.svg",
	"s0": "res://assets/art/svg/probe/a_sand_a.svg",
	"s1": "res://assets/art/svg/probe/a_sand_b.svg",
	"o": "res://assets/art/svg/probe/a_ore.svg",
}
## The current map, as the Units page draws it: flat colours by token, and the ore tile of a file.
const CURRENT_TILE_COLORS: Dictionary[String, Color] = {
	"g0": Color("5E7D4A"),
	"g1": Color("6F8F57"),
	"s0": Color("CDB98F"),
	"s1": Color("CDB98F"),
}
const CURRENT_ORE_ART: String = "res://assets/art/svg/ore/ore_3a.svg"
## Rows of the patch, left to right: three grass, three sand, one ore cell between them.
const PATCH_ROWS: Array[String] = ["g0 g1 g0 s0 s1 s0", "g1 g0 o s1 s0 s1"]
const GRASS_COLOR: Color = Color("6F8F57")
const SAND_COLOR: Color = Color("CDB98F")
const BAND_COLOR: Color = Color("0F141C")
const FRAME_COLOR: Color = Color("1C2127")
const MARKER_COLOR: Color = Color(0.0, 0.0, 0.0, 0.12)
const FOOTPRINT_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)
const TILE_PX: float = 64.0  ## One tile at gameplay zoom.
const FOOTPRINT_PX: float = 192.0  ## 3 x 3 tiles.
const FRAME_PX: float = 4.0
const BAND_PX: float = 56.0
const TITLE_PX: int = 22
const NOTE_PX: int = 15
## The corner buttons cover 24 to 144 px from the top and the left or right edge: the title of the
## outer columns keeps this far from the screen edge.
const BUTTON_CLEAR_PX: float = 152.0
## In column px from the top: where the footprint ends (a 3x3 sprite stands on it, a taller one
## rises above), the tank tile row and the patch.
const FOOT_BOTTOM: float = 404.0
const TANK_TOP: float = 452.0
const PATCH_TOP: float = 542.0
const CAPTION_TOP: float = 410.0
const CAPTION_WIDTH_PX: float = 204.0
const TANK_DX: float = 46.0  ## Team A's tank is this far left of the half's middle, team B's right.
const HEADINGS: Array[float] = [0.0, 150.0]  ## Degrees, team A then team B.
const STATEMENT: String = "Style probe 2026-10-26, not approved. Nothing here is used in the game."


## Builds the three columns and the statement line into `page`.
static func build(page: Control) -> void:
	for index: int in DIRECTIONS.size():
		_add_column(page, DIRECTIONS[index], index)
	var line: Label = Label.new()
	line.name = "Statement"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.text = STATEMENT
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override(&"font_size", NOTE_PX)
	line.add_theme_color_override(&"font_color", Color.WHITE)
	line.add_theme_color_override(&"font_shadow_color", FRAME_COLOR)
	line.add_theme_constant_override(&"shadow_offset_x", 1)
	line.add_theme_constant_override(&"shadow_offset_y", 1)
	line.anchor_left = 0.0
	line.anchor_right = 1.0
	line.anchor_top = 1.0
	line.anchor_bottom = 1.0
	line.offset_top = -28.0
	line.offset_bottom = -4.0
	page.add_child(line)


## The ids of the ground cells of `PATCH_ROWS`, row by row, as `Vector2i` of (column, row) -> token.
static func patch_tokens() -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	for spec: String in PATCH_ROWS:
		rows.append(spec.split(" "))
	return rows


static func _add_column(page: Control, id: StringName, index: int) -> void:
	var column: Control = Control.new()
	column.name = "Column" + String(id).to_upper()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.anchor_left = index / 3.0
	column.anchor_right = (index + 1) / 3.0
	column.anchor_bottom = 1.0
	column.clip_contents = true
	page.add_child(column)
	for ground_name: String in ["Grass", "Sand"]:
		var half: Control = _add_half(column, id, ground_name)
		_add_refinery(half, id, ground_name == "Grass")
		_add_tanks(half, id)
	_add_patch(column, id)
	_add_title(column, id, index)


## One half of a column: its ground, clipped, with the content rows anchored on its middle.
static func _add_half(column: Control, id: StringName, ground_name: String) -> Control:
	var is_grass: bool = ground_name == "Grass"
	var half: Control = Control.new()
	half.name = ground_name
	half.mouse_filter = Control.MOUSE_FILTER_IGNORE
	half.anchor_left = 0.0 if is_grass else 0.5
	half.anchor_right = 0.5 if is_grass else 1.0
	half.anchor_bottom = 1.0
	half.clip_contents = true
	column.add_child(half)
	if id == &"c":
		var flat: ColorRect = ColorRect.new()
		flat.name = "Ground"
		flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flat.color = GRASS_COLOR if is_grass else SAND_COLOR
		flat.anchor_right = 1.0
		flat.anchor_bottom = 1.0
		half.add_child(flat)
	else:
		var tiles: TextureRect = TextureRect.new()
		tiles.name = "Ground"
		tiles.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tiles.texture = _block_texture(
			TILE_ART["g0" if is_grass else "s0"], TILE_ART["g1" if is_grass else "s1"]
		)
		tiles.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tiles.stretch_mode = TextureRect.STRETCH_TILE
		tiles.anchor_right = 1.0
		tiles.anchor_bottom = 1.0
		half.add_child(tiles)
	var row: Control = Control.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.anchor_left = 0.5
	row.anchor_right = 0.5
	half.add_child(row)
	return half


## Two tiles of one ground, side by side and then swapped below, as one texture that repeats.
static func _block_texture(first_path: String, second_path: String) -> ImageTexture:
	var first: Image = (load(first_path) as Texture2D).get_image()
	var second: Image = (load(second_path) as Texture2D).get_image()
	first.convert(Image.FORMAT_RGBA8)
	second.convert(Image.FORMAT_RGBA8)
	var size: Vector2i = first.get_size()
	var block: Image = Image.create(size.x * 2, size.y * 2, false, Image.FORMAT_RGBA8)
	var whole: Rect2i = Rect2i(Vector2i.ZERO, size)
	block.blit_rect(first, whole, Vector2i(0, 0))
	block.blit_rect(second, whole, Vector2i(size.x, 0))
	block.blit_rect(second, whole, Vector2i(0, size.y))
	block.blit_rect(first, whole, size)
	return ImageTexture.create_from_image(block)


## The refinery of the column on the middle of the half, standing on its footprint frame.
static func _add_refinery(half: Control, id: StringName, is_team_a: bool) -> void:
	var row: Control = half.get_node("Row")
	var rig: Node2D = _rig("Refinery", is_team_a, REFINERY_ART[id], ["hull", "team"])
	var height: float = (rig.get_node("Hull") as Sprite2D).texture.get_size().y
	rig.position = Vector2(0.0, FOOT_BOTTOM - height / 2.0)
	row.add_child(rig)
	var footprint: Control = Control.new()
	footprint.name = "Footprint"
	footprint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footprint.position = Vector2(-FOOTPRINT_PX / 2.0, FOOT_BOTTOM - FOOTPRINT_PX)
	footprint.size = Vector2.ONE * FOOTPRINT_PX
	var frame: ReferenceRect = ReferenceRect.new()
	frame.name = "Frame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.editor_only = false
	frame.border_color = FOOTPRINT_COLOR
	frame.border_width = 2.0
	frame.size = footprint.size
	footprint.add_child(frame)
	for step: int in [1, 2]:
		for vertical: bool in [true, false]:
			var line: ColorRect = ColorRect.new()
			line.name = "%s%d" % ["V" if vertical else "H", step]
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.color = Color(FOOTPRINT_COLOR, 0.3)
			line.position = (
				Vector2(step * TILE_PX, 0.0) if vertical else Vector2(0.0, step * TILE_PX)
			)
			line.size = Vector2(1.0, FOOTPRINT_PX) if vertical else Vector2(FOOTPRINT_PX, 1.0)
			footprint.add_child(line)
	row.add_child(footprint)
	var caption: Label = Label.new()
	caption.name = "Caption"
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.text = CAPTIONS[id]
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override(&"font_size", 14)
	caption.add_theme_color_override(&"font_color", FRAME_COLOR)
	caption.position = Vector2(-CAPTION_WIDTH_PX / 2.0, CAPTION_TOP)
	caption.size = Vector2(CAPTION_WIDTH_PX, 36.0)
	row.add_child(caption)


## The heavy tank, team A at heading 0 and team B turned, each on a faint tile square.
static func _add_tanks(half: Control, id: StringName) -> void:
	var row: Control = half.get_node("Row")
	for index: int in 2:
		var is_team_a: bool = index == 0
		var centre: Vector2 = Vector2(
			(-1.0 if is_team_a else 1.0) * TANK_DX, TANK_TOP + TILE_PX / 2.0
		)
		var marker: ColorRect = ColorRect.new()
		marker.name = "Tile" + ("A" if is_team_a else "B")
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.color = MARKER_COLOR
		marker.position = centre - Vector2.ONE * TILE_PX / 2.0
		marker.size = Vector2.ONE * TILE_PX
		row.add_child(marker)
		var rig: Node2D = _rig(
			"HeavyTank" + ("A" if is_team_a else "B"),
			is_team_a,
			TANK_ART[id],
			["hull", "team", "turret"]
		)
		rig.position = centre
		rig.rotation = deg_to_rad(HEADINGS[index])
		row.add_child(rig)


## The ground patch across the middle of the column, in a dark frame so every tile edge shows.
static func _add_patch(column: Control, id: StringName) -> void:
	var rows: Array[PackedStringArray] = patch_tokens()
	var extent: Vector2 = Vector2(rows[0].size(), rows.size()) * TILE_PX
	var patch: Control = Control.new()
	patch.name = "Patch"
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	patch.anchor_left = 0.5
	patch.anchor_right = 0.5
	patch.offset_top = PATCH_TOP
	patch.offset_bottom = PATCH_TOP
	column.add_child(patch)
	var origin: Vector2 = Vector2(-extent.x / 2.0, 0.0)
	var frame: ColorRect = ColorRect.new()
	frame.name = "Frame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.color = FRAME_COLOR
	frame.position = origin - Vector2.ONE * FRAME_PX
	frame.size = extent + Vector2.ONE * 2.0 * FRAME_PX
	patch.add_child(frame)
	for y: int in rows.size():
		for x: int in rows[y].size():
			var token: String = rows[y][x]
			var at: Vector2 = origin + Vector2(x, y) * TILE_PX
			patch.add_child(_tile(id, token, "Tile%d_%d" % [x, y], at))


## One patch cell: a flat colour for the current map's grass and sand, a texture for the rest.
static func _tile(id: StringName, token: String, tile_name: String, at: Vector2) -> Control:
	if id == &"c" and CURRENT_TILE_COLORS.has(token):
		var flat: ColorRect = ColorRect.new()
		flat.name = tile_name
		flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flat.color = CURRENT_TILE_COLORS[token]
		flat.position = at
		flat.size = Vector2.ONE * TILE_PX
		return flat
	var tile: TextureRect = TextureRect.new()
	tile.name = tile_name
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.texture = load(CURRENT_ORE_ART if id == &"c" else TILE_ART[token])
	tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tile.stretch_mode = TextureRect.STRETCH_SCALE
	tile.position = at
	tile.size = Vector2.ONE * TILE_PX
	return tile


## The title band across the top of a column; the outer columns keep clear of the corner buttons.
static func _add_title(column: Control, id: StringName, index: int) -> void:
	var band: ColorRect = ColorRect.new()
	band.name = "Band"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.color = BAND_COLOR
	band.anchor_right = 1.0
	band.offset_bottom = BAND_PX
	column.add_child(band)
	var title: Label = Label.new()
	title.name = "Title"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = TITLES[id]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", TITLE_PX)
	title.add_theme_color_override(&"font_color", Color.WHITE)
	title.anchor_right = 1.0
	title.offset_left = BUTTON_CLEAR_PX if index == 0 else 0.0
	title.offset_right = -BUTTON_CLEAR_PX if index == DIRECTIONS.size() - 1 else 0.0
	title.offset_bottom = BAND_PX
	column.add_child(title)


## A rig: the layers of `art` (a path with one `%s` for the layer) that exist, in the team group.
static func _rig(rig_name: String, is_team_a: bool, art: String, layers: Array[String]) -> Node2D:
	var rig: Node2D = Node2D.new()
	rig.name = rig_name
	rig.add_to_group(TEAM_A_GROUP if is_team_a else TEAM_B_GROUP)
	for layer: String in layers:
		var path: String = art % layer
		if ResourceLoader.exists(path):
			var sprite: Sprite2D = Sprite2D.new()
			sprite.name = layer.capitalize()
			sprite.texture = load(path)
			rig.add_child(sprite)
	return rig
