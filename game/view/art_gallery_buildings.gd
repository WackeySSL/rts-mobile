extends RefCounted
## The Build and Seam pages of the art gallery (STYLE.md, "Buildings"; ADR 0022): the six
## buildings in their oblique view, drawn the way the view draws them. Build is a list to scroll, a
## section for each camera zoom level and team: the six buildings on grass (left) and sand (right).
## A building is a cell cut at its footprint's middle line (ADR 0022 section 2): the base part, then
## the roof part (and the defence turret's gun head, which turns about the roof's centre). Seam
## shows the refinery with the explored fog over the west column of its footprint beside the same
## refinery seen: the base part dimmed, the roof part not (ADR 0022 section 4). Every part is a rig
## `Node2D` in the team group with `Hull` and `Team`, so the gallery's tint and turret turn find
## them. The top-down units stood north and south of each building until plan row P101 deleted
## them; P103 deletes the oblique buildings and these pages. View-only.

const TEAM_A_GROUP: StringName = &"gallery_team_a"
const TEAM_B_GROUP: StringName = &"gallery_team_b"
const BUILDING_ART: String = "res://assets/art/svg/buildings/%s_%s.svg"
## The six buildings by file name, the 3x3 ones first. Only the defence turret has a `Turret` layer.
## A canvas is its footprint plus the rise (ADR 0022 section 1): the view reads it off the texture.
const BUILDINGS: Array[String] = [
	"headquarters",
	"refinery",
	"vehicle_factory",
	"power_plant",
	"barracks",
	"defence_turret",
]
## The camera zoom levels of `data/input_settings.tres`, the baseline first.
const ZOOMS: Array[float] = [1.0, 0.75, 1.5]
const HALF_WIDTH_PX: float = 640.0  ## One ground of a page at the 16:9 base size.
const CELL_GAP_PX: float = 12.0
const LINE_GAP_PX: float = 16.0
const SECTION_GAP_PX: float = 24.0
const LABEL_PX: float = 28.0
const LABEL_FONT_PX: int = 20
const LABEL_COLOR: Color = Color("1C2127")
const NOTE_WIDTH_PX: float = 360.0
const NOTE_TOP_PX: float = 320.0  ## Under the cells of the Seam page.
const FIRST_TOP_PX: float = 150.0  ## Clear of the two corner buttons, which cover 24 to 144 px.
const TILE_PX: float = 64.0
const SEAM_BUILDING: String = "refinery"  ## At least two tiles wide.


## Builds the Build page and the Seam page into `host` (hidden) and returns them in that order.
static func add_pages(host: Control, grass: Color, sand: Color, fog_alpha: int) -> Array[Control]:
	var pages: Array[Control] = [_page(host, "BuildingsPage"), _page(host, "SeamPage")]
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pages[0].add_child(scroll)
	var content: Control = Control.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var grounds: Array[ColorRect] = [
		_ground(content, "Grass", grass), _ground(content, "Sand", sand)
	]
	var top: float = FIRST_TOP_PX
	for zoom: float in ZOOMS:
		var lines: Array[Array] = _lines(zoom)
		for is_team_a: bool in [true, false]:
			for ground: ColorRect in grounds:
				_add_section(ground, zoom, is_team_a, lines, top, fog_alpha)
			top += _section_height(lines, zoom)
	content.custom_minimum_size = Vector2(0.0, top)
	for ground_name: String in ["Grass", "Sand"]:
		var half: ColorRect = _ground(
			pages[1], ground_name, grass if ground_name == "Grass" else sand
		)
		var row: Control = _row(half, "Row", FIRST_TOP_PX)
		for index: int in 2:
			var cell: Node2D = _cell(SEAM_BUILDING, ground_name == "Grass", index == 0, fog_alpha)
			var hull_size: Vector2 = _hull_size(SEAM_BUILDING)
			var left: float = (index - 1) * (hull_size.x + CELL_GAP_PX) + CELL_GAP_PX / 2.0
			cell.position = Vector2(left, 0.0)
			row.add_child(cell)
		var note: Label = _label("Left: fog over the west column. Right: seen.", NOTE_WIDTH_PX)
		note.position = Vector2(-NOTE_WIDTH_PX / 2.0, NOTE_TOP_PX)
		row.add_child(note)
	return pages


## The size of a building's hull texture in game px: a footprint of tiles square plus the rise.
static func _hull_size(id: String) -> Vector2:
	return (load(BUILDING_ART % [id, "hull"]) as Texture2D).get_size()


## The building ids of the page in lines no wider than a ground holds at `zoom`.
static func _lines(zoom: float) -> Array[Array]:
	var lines: Array[Array] = [[]]
	var width: float = 0.0
	for id: String in BUILDINGS:
		var wide: float = _hull_size(id).x * zoom
		if not lines[-1].is_empty() and width + CELL_GAP_PX + wide > HALF_WIDTH_PX - 16.0:
			lines.append([])
			width = 0.0
		width += wide + (CELL_GAP_PX if not lines[-1].is_empty() else 0.0)
		lines[-1].append(id)
	return lines


static func _line_height(line: Array, zoom: float) -> float:
	var tallest: float = 0.0
	for id: String in line:
		tallest = maxf(tallest, _hull_size(id).y * zoom)
	return tallest


static func _section_height(lines: Array[Array], zoom: float) -> float:
	var height: float = LABEL_PX + SECTION_GAP_PX
	for line: Array in lines:
		height += _line_height(line, zoom) + LINE_GAP_PX
	return height


## One section on one ground: a label, then the lines of cells, each line centred on the ground.
static func _add_section(
	ground: Control, zoom: float, is_team_a: bool, lines: Array[Array], top: float, fog_alpha: int
) -> void:
	var team: String = "A" if is_team_a else "B"
	var row: Control = _row(ground, "Zoom%d%s" % [roundi(zoom * 100.0), team], top)
	var label: Label = _label("Zoom %s, team %s" % [zoom, team], HALF_WIDTH_PX)
	label.position = Vector2(-HALF_WIDTH_PX / 2.0, 0.0)
	row.add_child(label)
	var y: float = LABEL_PX
	for line: Array in lines:
		var total: float = CELL_GAP_PX * (line.size() - 1)
		for id: String in line:
			total += _hull_size(id).x * zoom
		var x: float = -total / 2.0
		for id: String in line:
			var cell: Node2D = _cell(id, is_team_a, false, fog_alpha)
			cell.scale = Vector2.ONE * zoom
			cell.position = Vector2(x, y)
			row.add_child(cell)
			x += _hull_size(id).x * zoom + CELL_GAP_PX
		y += _line_height(line, zoom) + LINE_GAP_PX


## A building cell: the base part, the explored fog over the west column of the footprint if
## `fogged`, then the roof part. The origin is the sprite box's top left corner. The cut is the
## footprint's middle line (`y_mid`, ADR 0022 s. 2).
static func _cell(id: String, is_team_a: bool, fogged: bool, fog_alpha: int) -> Node2D:
	var cell: Node2D = Node2D.new()
	cell.name = id.to_pascal_case()
	var size: Vector2 = _hull_size(id)
	var rise: float = size.y - size.x
	var cut: float = size.y - size.x / 2.0
	cell.add_child(_part("Base", id, is_team_a, Rect2(0.0, cut, size.x, size.y - cut)))
	if fogged:
		var fog: ColorRect = ColorRect.new()
		fog.name = "ExploredFog"
		fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fog.color = Color(0.0, 0.0, 0.0, fog_alpha / 255.0)
		fog.position = Vector2(0.0, rise)
		fog.size = Vector2(TILE_PX, size.x)
		cell.add_child(fog)
	var roof: Node2D = _part("Roof", id, is_team_a, Rect2(0.0, 0.0, size.x, cut))
	if ResourceLoader.exists(BUILDING_ART % [id, "turret"]):
		# The head turns about the roof's centre: the footprint's centre lifted by the rise.
		var pivot: Vector2 = Vector2(size.x, size.x) / 2.0
		var head: Sprite2D = _sprite("turret", BUILDING_ART % [id, "turret"])
		head.centered = false
		head.offset = -pivot
		head.position = pivot
		roof.add_child(head)
	cell.add_child(roof)
	return cell


## One part of a building: a rig with `Hull` and `Team` sprites that show only the rows of `region`.
static func _part(part: String, id: String, is_team_a: bool, region: Rect2) -> Node2D:
	var rig: Node2D = Node2D.new()
	rig.name = part
	rig.position = region.position
	rig.add_to_group(TEAM_A_GROUP if is_team_a else TEAM_B_GROUP)
	for layer: String in ["hull", "team"]:
		var sprite: Sprite2D = _sprite(layer, BUILDING_ART % [id, layer])
		sprite.centered = false
		sprite.region_enabled = true
		sprite.region_rect = region
		rig.add_child(sprite)
	return rig


static func _sprite(layer: String, path: String) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = layer.capitalize()
	sprite.texture = load(path)
	return sprite


static func _label(text: String, width: float) -> Label:
	var label: Label = Label.new()
	label.name = "Label"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", LABEL_FONT_PX)
	label.add_theme_color_override(&"font_color", LABEL_COLOR)
	label.size = Vector2(width, LABEL_PX)
	return label


## A page: an empty full-screen Control that starts hidden, over the Units page.
static func _page(host: Control, page_name: String) -> Control:
	var page: Control = Control.new()
	page.name = page_name
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.anchor_right = 1.0
	page.anchor_bottom = 1.0
	page.visible = false
	host.add_child(page)
	return page


## The grass half (left) or the sand half (right) of `parent`.
static func _ground(parent: Control, ground_name: String, color: Color) -> ColorRect:
	var is_grass: bool = ground_name == "Grass"
	var ground: ColorRect = ColorRect.new()
	ground.name = ground_name
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ground.color = color
	ground.anchor_left = 0.0 if is_grass else 0.5
	ground.anchor_right = 0.5 if is_grass else 1.0
	ground.anchor_bottom = 1.0
	parent.add_child(ground)
	return ground


## An empty Control `top` base px down the middle of `ground`, that a row of things is added to.
static func _row(ground: Control, row_name: String, top: float) -> Control:
	var row: Control = Control.new()
	row.name = row_name
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.anchor_left = 0.5
	row.anchor_right = 0.5
	row.offset_top = top
	row.offset_bottom = top
	ground.add_child(row)
	return row
