extends Control
## The Life page of the art gallery (plan row P135, ADR 0027, STYLE.md "Life effects"): the two
## life atlases whole at scale 1, then every sprite of both, a row for each kind, each frame at the
## three camera zoom levels (0.75, 1.0 and 1.5, the levels of `data/input_settings.tres`) on grass
## (left half) and on sand (right half). A frame is a region of the imported atlas, drawn with its
## own colours (life effects carry no team colour) and sized in world px times the zoom, so what
## the page shows is what a life layer draws before its own scale and fade. The kind row is named
## on the grass half. The page scrolls (drag it) and is built on first show; view-only.

const LIFE_ART: String = "res://assets/art/svg/fx/life_atlas.svg"
const STRIKE_ART: String = "res://assets/art/svg/fx/strike_atlas.svg"
## The kinds of each atlas as "x,y,w,h,frames,step" in imported px, in the order the page shows them
## (frame k is at x + k * step). STYLE.md "Life effects" holds the same table, and
## tests/art/test_life_atlases.gd holds the two equal and the atlases clear outside them.
const LIFE_KINDS: Dictionary[String, String] = {
	"dust": "0,130,50,26,3,54",
	"smoke": "0,0,42,38,3,46",
	"soot": "0,42,42,38,2,46",
	"steam": "140,0,42,38,2,46",
	"puff": "140,42,22,20,2,26",
	"exhaust": "192,42,22,20,2,26",
	"flare": "0,84,26,42,4,30",
	"fire": "124,84,26,34,3,30",
	"spark": "218,84,16,16,3,20",
}
const STRIKE_KINDS: Dictionary[String, String] = {
	"lance_down": "0,0,34,164,1,0",
	"lance_up": "38,0,34,164,1,0",
	"trail": "76,0,16,64,1,0",
	"shadow": "76,68,50,26,1,0",
	"seed": "96,0,18,34,1,0",
	"seed_trail": "118,0,12,64,1,0",
	"glint": "134,0,14,14,1,0",
	"hex": "134,18,36,18,1,0",
	"hex_lit": "134,40,36,18,1,0",
	"launch_flash": "0,168,66,66,1,0",
	"core_flash": "70,168,66,66,1,0",
	"launch_ring": "140,168,98,50,1,0",
}
const ZOOMS: Array[float] = [0.75, 1.0, 1.5]
const FIRST_TOP_PX: float = 160.0  ## Clear of the corner buttons, which cover 24 to 144 px.
const GAP_PX: float = 16.0  ## Left margin of a half.
const FRAME_GAP_PX: float = 6.0  ## Between two frames of a kind, at every zoom.
const MAX_ZOOM: float = 1.5
const GROUP_GAP_PX: float = 24.0  ## Between the three zoom groups of a row.
const LABEL_PX: float = 36.0
const LABEL_FONT_PX: int = 20
const LABEL_COLOR: Color = Color("1C2127")
const ROW_GAP_PX: float = 10.0
const MIN_HALF_PX: float = 600.0  ## The widest row (dust at three zooms) needs 588 px.

var grass_color: Color = Color("6F8F57")
var sand_color: Color = Color("CDB98F")
var _built: bool = false


func _init() -> void:
	name = "LifePage"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0
	visible = false


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)


## The region of frame `frame` of the kind `spec` ("x,y,w,h,frames,step"), in imported px.
static func region(spec: String, frame: int = 0) -> Rect2i:
	var parts: PackedStringArray = spec.split(",")
	return Rect2i(
		int(parts[0]) + frame * int(parts[5]), int(parts[1]), int(parts[2]), int(parts[3])
	)


## How many frames the kind `spec` has.
static func frame_count(spec: String) -> int:
	return int(spec.split(",")[4])


func _on_visibility_changed() -> void:
	if visible and not _built:
		_built = true
		_build()


func _build() -> void:
	_ground("Grass", 0.0, grass_color)
	_ground("Sand", 0.5, sand_color)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override(&"separation", int(ROW_GAP_PX))
	scroll.add_child(rows)
	var spacer: Control = Control.new()
	spacer.name = "Spacer"
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size = Vector2(0.0, FIRST_TOP_PX - ROW_GAP_PX)
	rows.add_child(spacer)
	_add_atlas_row(rows)
	var life: Texture2D = load(LIFE_ART) as Texture2D
	for kind: String in LIFE_KINDS:
		_add_kind_row(rows, kind, life, LIFE_KINDS[kind])
	var strike: Texture2D = load(STRIKE_ART) as Texture2D
	for kind: String in STRIKE_KINDS:
		_add_kind_row(rows, kind, strike, STRIKE_KINDS[kind])


func _ground(ground_name: String, left: float, colour: Color) -> void:
	var ground: ColorRect = ColorRect.new()
	ground.name = ground_name
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ground.color = colour
	ground.anchor_left = left
	ground.anchor_right = left + 0.5
	ground.anchor_bottom = 1.0
	add_child(ground)


## A row of two equal halves, the grass one first, each at least `min_height` high.
func _row(rows: VBoxContainer, row_name: String, min_height: float) -> Array[Control]:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override(&"separation", 0)
	rows.add_child(row)
	var halves: Array[Control] = []
	for half_name: String in ["Grass", "Sand"]:
		var half: Control = Control.new()
		half.name = half_name
		half.mouse_filter = Control.MOUSE_FILTER_IGNORE
		half.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		half.custom_minimum_size = Vector2(MIN_HALF_PX, min_height)
		row.add_child(half)
		halves.append(half)
	return halves


## Both atlases whole at scale 1 on each ground, side by side.
func _add_atlas_row(rows: VBoxContainer) -> void:
	var life: Texture2D = load(LIFE_ART) as Texture2D
	var strike: Texture2D = load(STRIKE_ART) as Texture2D
	var tallest: float = maxf(life.get_height(), strike.get_height())
	var halves: Array[Control] = _row(rows, "RowAtlases", LABEL_PX + tallest)
	_label(halves[0], "Atlases at scale 1: life, strike", Vector2(GAP_PX, 0.0))
	for half: Control in halves:
		var life_rect: TextureRect = _rect(life, Vector2(life.get_size()), 1.0)
		life_rect.name = "LifeAtlas"
		life_rect.position = Vector2(GAP_PX, LABEL_PX)
		half.add_child(life_rect)
		var strike_rect: TextureRect = _rect(strike, Vector2(strike.get_size()), 1.0)
		strike_rect.name = "StrikeAtlas"
		strike_rect.position = Vector2(GAP_PX + life.get_width() + GROUP_GAP_PX, LABEL_PX)
		half.add_child(strike_rect)


## One kind: its frames in a line at each zoom, standing on one ground line.
func _add_kind_row(rows: VBoxContainer, kind: String, atlas: Texture2D, spec: String) -> void:
	var first: Rect2i = region(spec)
	var frames: int = frame_count(spec)
	var tallest: float = first.size.y * MAX_ZOOM
	var halves: Array[Control] = _row(rows, "Row" + kind.to_pascal_case(), LABEL_PX + tallest)
	_label(halves[0], "%s (%d)" % [kind, frames], Vector2(GAP_PX, 0.0))
	for half: Control in halves:
		var left: float = GAP_PX
		for zoom: float in ZOOMS:
			var group: Control = Control.new()
			group.name = "Z%03d" % roundi(zoom * 100.0)
			group.mouse_filter = Control.MOUSE_FILTER_IGNORE
			group.position = Vector2(left, LABEL_PX)
			half.add_child(group)
			var at: float = 0.0
			for frame: int in frames:
				var rect: TextureRect = _frame_rect(atlas, region(spec, frame), zoom)
				rect.name = "F%d" % frame
				rect.position = Vector2(at, tallest - rect.size.y)
				group.add_child(rect)
				at += rect.size.x + FRAME_GAP_PX
			left += at - FRAME_GAP_PX + GROUP_GAP_PX


func _frame_rect(atlas: Texture2D, box: Rect2i, zoom: float) -> TextureRect:
	var part: AtlasTexture = AtlasTexture.new()
	part.atlas = atlas
	part.region = Rect2(box)
	return _rect(part, Vector2(box.size), zoom)


func _rect(texture: Texture2D, size_px: Vector2, zoom: float) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.size = size_px * zoom
	return rect


func _label(parent: Control, text: String, at: Vector2) -> void:
	var label: Label = Label.new()
	label.name = "Label"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.add_theme_font_size_override(&"font_size", LABEL_FONT_PX)
	label.add_theme_color_override(&"font_color", LABEL_COLOR)
	label.position = at
	parent.add_child(label)
