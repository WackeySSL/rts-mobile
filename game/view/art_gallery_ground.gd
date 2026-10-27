extends Control
## The Terrain page of the art gallery (plan row P105, ADR 0023 sections 5, 6 and 11): the iso
## ground on the off-map colour, as it will be drawn. A patch of the six terrain diamonds in both
## variants, a small map that mixes them with an oil and a gas field (the stages as stripes across
## each) with a wellhead on every field and a crater on grass and on sand, the six field stages as
## blocks of 3 x 3 cells, and the wellhead and the crater at the camera zoom levels on grass and on
## sand. Tiles are the imported textures (half the 2x art), so a tile is 64 x 32 px at zoom 1.
## Built on first show; view-only.

const GROUND_ART: String = "res://assets/art/svg/ground/%s_%s.svg"
const FIELD_ART: String = "res://assets/art/svg/fields/%s.svg"
const CRATER_ART: String = "res://assets/art/svg/decals/crater.svg"
## The colour the clear colour shows outside the map's diamond (STYLE.md, "Fog and terrain").
const OFF_MAP_COLOR: Color = Color("16191D")
const TERRAIN_IDS: Array[String] = ["grass", "sand", "scrub", "rock", "water", "ore"]
const FIELDS: Array[String] = ["oil_full", "oil_half", "oil_dry", "gas_full", "gas_half", "gas_dry"]
const STAGE_BY_COLUMN: Array[String] = ["full", "half", "dry"]
## The small map, one string per row of 12 cells: `.` grass, `:` sand, `^` scrub, `#` rock, `~`
## water and `o` a field cell (oil left of column 6, gas right of it).
const MAP_ROWS: Array[String] = [
	"..::::....##",
	".:::::...###",
	"...::.....#.",
	".ooo....ooo.",
	".oooo...ooo.",
	".ooo....oo..",
	"..........^^",
	"~~~.......^^",
	"~~~~~.....^.",
	"~~~~~~......",
]
const MAP_IDS: Dictionary[String, String] = {
	".": "grass", ":": "sand", "^": "scrub", "#": "rock", "~": "water", "o": "ore"
}
const WELLHEAD_CELLS: Array[Vector2i] = [Vector2i(3, 4), Vector2i(9, 4)]
const WELLHEAD_ANCHOR: Vector2 = Vector2(28.0, 44.0)  ## Imported px; STYLE.md, "Fields".
const SHADOW_ANCHOR: Vector2 = Vector2(28.0, 15.5)
const CRATER_CELLS: Dictionary[Vector2i, float] = {Vector2i(6, 6): 1.0, Vector2i(3, 1): 0.5}
const ZOOMS: Array[float] = [0.75, 1.0, 1.5]
const TILE_PX: Vector2 = Vector2(64.0, 32.0)
const FIRST_TOP_PX: float = 160.0  ## Clear of the corner buttons, which cover 24 to 144 px.
const GAP_PX: float = 24.0
const LABEL_PX: float = 26.0
const LABEL_FONT_PX: int = 20
const LABEL_COLOR: Color = Color("D5DBDC")
const SWATCH_SIZE: Vector2 = Vector2(600.0, 170.0)
const SWATCH_GROUND_Y: float = 110.0
const CRATER_X_PX: float = 470.0  ## Right of the wellheads, clear of the 1.5 zoom one's shadow.

var grass_color: Color = Color("6F8F57")
var sand_color: Color = Color("CDB98F")
var _built: bool = false


func _init() -> void:
	name = "TerrainPage"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0
	visible = false


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)


## The centre of cell (column, row) of a diamond grid whose top corner is at `origin`.
static func cell_centre(origin: Vector2, column: int, row: int) -> Vector2:
	return (
		origin + Vector2((column - row) * TILE_PX.x / 2.0, (column + row) * TILE_PX.y / 2.0 + 16.0)
	)


func _on_visibility_changed() -> void:
	if visible and not _built:
		_built = true
		_build()


func _build() -> void:
	var back: ColorRect = ColorRect.new()
	back.name = "OffMap"
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.color = OFF_MAP_COLOR
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var content: Control = Control.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.custom_minimum_size = Vector2(1232.0 + 2.0 * GAP_PX, 1000.0)
	scroll.add_child(content)
	var top: float = FIRST_TOP_PX
	_label(content, "Ground: grass sand scrub rock water ore", GAP_PX, top)
	_label(content, "Map: oil, gas, wellheads, craters", 470.0, top)
	_add_patch(content, Vector2(GAP_PX + 192.0, top + LABEL_PX))
	_add_map(content, Vector2(470.0 + 352.0, top + LABEL_PX))
	top += 420.0
	_label(content, "Field stages: oil full, half, dry; gas full, half, dry", GAP_PX, top)
	_add_blocks(content, top + LABEL_PX)
	top += 150.0
	_add_props(content, top)


func _add_patch(parent: Control, origin: Vector2) -> void:
	var patch: Node2D = Node2D.new()
	patch.name = "Patch"
	parent.add_child(patch)
	for row: int in TERRAIN_IDS.size():
		for column: int in 6:
			var tile: String = GROUND_ART % [TERRAIN_IDS[row], "ab"[(column + row) % 2]]
			patch.add_child(_sprite(tile, cell_centre(origin, column, row)))


func _add_map(parent: Control, origin: Vector2) -> void:
	var map: Node2D = Node2D.new()
	map.name = "Map"
	parent.add_child(map)
	for row: int in MAP_ROWS.size():
		for column: int in MAP_ROWS[row].length():
			var id: String = MAP_IDS[MAP_ROWS[row][column]]
			map.add_child(
				_sprite(
					GROUND_ART % [id, "ab"[(column + row) % 2]], cell_centre(origin, column, row)
				)
			)
	for row: int in MAP_ROWS.size():
		for column: int in MAP_ROWS[row].length():
			if MAP_ROWS[row][column] == "o":
				var kind: String = "oil" if column < 6 else "gas"
				var stage: String = STAGE_BY_COLUMN[(2 * column) % 3]
				var field: Sprite2D = _sprite(
					FIELD_ART % ("%s_%s" % [kind, stage]), cell_centre(origin, column, row)
				)
				field.name = "%s_%s_%d_%d" % [kind, stage, column, row]
				map.add_child(field)
	for cell: Vector2i in CRATER_CELLS:
		var crater: Sprite2D = _sprite(CRATER_ART, cell_centre(origin, cell.x, cell.y))
		crater.name = "Crater%d_%d" % [cell.x, cell.y]
		crater.scale = Vector2.ONE * CRATER_CELLS[cell]
		map.add_child(crater)
	for cell: Vector2i in WELLHEAD_CELLS:
		map.add_child(
			_wellhead("Wellhead%d_%d" % [cell.x, cell.y], cell_centre(origin, cell.x, cell.y), 1.0)
		)


func _add_blocks(parent: Control, top: float) -> void:
	var blocks: Node2D = Node2D.new()
	blocks.name = "Fields"
	parent.add_child(blocks)
	for index: int in FIELDS.size():
		var block: Node2D = Node2D.new()
		block.name = FIELDS[index].to_pascal_case()
		blocks.add_child(block)
		var origin: Vector2 = Vector2(GAP_PX + 96.0 + index * (192.0 + 16.0), top)
		var grass: ColorRect = ColorRect.new()
		grass.name = "Grass"
		grass.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grass.color = grass_color
		grass.position = origin - Vector2(104.0, 8.0)
		grass.size = Vector2(208.0, 112.0)
		block.add_child(grass)
		for row: int in 3:
			for column: int in 3:
				var centre: Vector2 = cell_centre(origin, column, row)
				block.add_child(_sprite(GROUND_ART % ["ore", "ab"[(column + row) % 2]], centre))
		for row: int in 3:
			for column: int in 3:
				block.add_child(
					_sprite(FIELD_ART % FIELDS[index], cell_centre(origin, column, row))
				)


func _add_props(parent: Control, top: float) -> void:
	var props: Control = Control.new()
	props.name = "Props"
	props.mouse_filter = Control.MOUSE_FILTER_IGNORE
	props.position = Vector2(0.0, top)
	parent.add_child(props)
	for index: int in 2:
		var swatch: ColorRect = ColorRect.new()
		swatch.name = "GrassSwatch" if index == 0 else "SandSwatch"
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch.color = grass_color if index == 0 else sand_color
		swatch.position = Vector2(GAP_PX + index * (SWATCH_SIZE.x + GAP_PX), 0.0)
		swatch.size = SWATCH_SIZE
		props.add_child(swatch)
		var x: float = 60.0
		for zoom: float in ZOOMS:
			swatch.add_child(
				_wellhead("Wellhead%d" % roundi(zoom * 100.0), Vector2(x, SWATCH_GROUND_Y), zoom)
			)
			x += 100.0 + 40.0 * zoom
		swatch.add_child(_sprite(CRATER_ART, Vector2(CRATER_X_PX, SWATCH_GROUND_Y)))


## The wellhead with its cast shadow under it, standing on `at`, at a zoom of the camera.
func _wellhead(rig_name: String, at: Vector2, zoom: float) -> Node2D:
	var rig: Node2D = Node2D.new()
	rig.name = rig_name
	rig.position = at
	rig.scale = Vector2.ONE * zoom
	for art: String in ["wellhead_shadow", "wellhead"]:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.name = art.to_pascal_case()
		sprite.texture = load(FIELD_ART % art) as Texture2D
		sprite.centered = false
		sprite.offset = -(SHADOW_ANCHOR if art == "wellhead_shadow" else WELLHEAD_ANCHOR)
		rig.add_child(sprite)
	return rig


func _sprite(path: String, centre: Vector2) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = load(path) as Texture2D
	sprite.position = centre
	return sprite


func _label(parent: Control, text: String, left: float, top: float) -> void:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.add_theme_font_size_override(&"font_size", LABEL_FONT_PX)
	label.add_theme_color_override(&"font_color", LABEL_COLOR)
	label.position = Vector2(left, top)
	parent.add_child(label)
