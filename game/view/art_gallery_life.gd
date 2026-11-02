extends Control
## The Life page of the art gallery (plan row P135, ADR 0027, STYLE.md "Life effects"): the two
## life atlases whole at scale 1, then every sprite of both, a row for each kind of `LifeRegions`,
## each frame at the three camera zoom levels (0.75, 1.0 and 1.5, the levels of
## `data/input_settings.tres`) on grass (left half) and on sand (right half). A frame is a region
## of the imported atlas, drawn with its own colours (life effects carry no team colour) and sized
## in world px times the zoom, so what the page shows is what a life layer draws before its own
## scale and fade. Each half of a row is its own ground, at least `MIN_HALF_PX` wide, so on a
## narrow screen the page scrolls sideways to the sand. The kind is named on the grass half. The
## page scrolls (drag it) and is built on first show; view-only.

const ZOOMS: Array[float] = [0.75, 1.0, 1.5]
const FIRST_TOP_PX: float = 160.0  ## Clear of the corner buttons, which cover 24 to 144 px.
const GAP_PX: float = 16.0  ## Left margin of a half.
const FRAME_GAP_PX: float = 6.0  ## Between two frames of a kind, at every zoom.
const GROUP_GAP_PX: float = 24.0  ## Between the three zoom groups of a row.
const LABEL_PX: float = 36.0
const LABEL_FONT_PX: int = 20
const LABEL_COLOR: Color = Color("1C2127")
const ROW_GAP_PX: float = 10.0  ## Ground under the sprites of a row, so the rows do not touch.
const MIN_HALF_PX: float = 600.0  ## The widest row (dust at three zooms) needs 588 px.

var grass_color: Color = Color("6F8F57")
var sand_color: Color = Color("CDB98F")
var _built: bool = false
var _atlases: Dictionary[int, Texture2D] = {}
var _frame_textures: Dictionary[String, AtlasTexture] = {}  ## "<kind> <frame>": one per frame.


func _init() -> void:
	name = "LifePage"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0
	visible = false


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if visible and not _built:
		_built = true
		_build()


func _build() -> void:
	_atlases[LifeRegions.Atlas.LIFE] = load(LifeRegions.LIFE_ART) as Texture2D
	_atlases[LifeRegions.Atlas.STRIKE] = load(LifeRegions.STRIKE_ART) as Texture2D
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override(&"separation", 0)
	scroll.add_child(rows)
	_row(rows, "Spacer", FIRST_TOP_PX)
	_add_atlas_row(rows)
	for kind: StringName in LifeRegions.ATLAS:
		_add_kind_row(rows, kind)


## A row of two equal halves, the grass one first and the sand one second, each its ground and at
## least `min_height` high.
func _row(rows: VBoxContainer, row_name: String, min_height: float) -> Array[ColorRect]:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override(&"separation", 0)
	rows.add_child(row)
	var halves: Array[ColorRect] = []
	for half_name: String in ["Grass", "Sand"]:
		var half: ColorRect = ColorRect.new()
		half.name = half_name
		half.color = grass_color if half_name == "Grass" else sand_color
		half.mouse_filter = Control.MOUSE_FILTER_IGNORE
		half.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		half.custom_minimum_size = Vector2(MIN_HALF_PX, min_height)
		row.add_child(half)
		halves.append(half)
	return halves


## Both atlases whole at scale 1 on each ground, side by side.
func _add_atlas_row(rows: VBoxContainer) -> void:
	var life: Texture2D = _atlases[LifeRegions.Atlas.LIFE]
	var strike: Texture2D = _atlases[LifeRegions.Atlas.STRIKE]
	var tallest: float = maxf(life.get_height(), strike.get_height())
	var halves: Array[ColorRect] = _row(rows, "RowAtlases", LABEL_PX + tallest + ROW_GAP_PX)
	_label(halves[0], "Atlases at scale 1: life, strike", Vector2(GAP_PX, 0.0))
	for half: ColorRect in halves:
		var life_rect: TextureRect = _rect(life, Vector2(life.get_size()), 1.0)
		life_rect.name = "LifeAtlas"
		life_rect.position = Vector2(GAP_PX, LABEL_PX)
		half.add_child(life_rect)
		var strike_rect: TextureRect = _rect(strike, Vector2(strike.get_size()), 1.0)
		strike_rect.name = "StrikeAtlas"
		strike_rect.position = Vector2(GAP_PX + life.get_width() + GROUP_GAP_PX, LABEL_PX)
		half.add_child(strike_rect)


## One kind: its frames in a line at each zoom, standing on one ground line.
func _add_kind_row(rows: VBoxContainer, kind: StringName) -> void:
	var frames: int = LifeRegions.FRAMES[kind]
	var tallest: float = LifeRegions.FIRST[kind].size.y * _top_zoom()
	var halves: Array[ColorRect] = _row(
		rows, "Row" + String(kind).to_pascal_case(), LABEL_PX + tallest + ROW_GAP_PX
	)
	_label(halves[0], "%s (%d)" % [kind, frames], Vector2(GAP_PX, 0.0))
	for half: ColorRect in halves:
		var left: float = GAP_PX
		for zoom: float in ZOOMS:
			var group: Control = Control.new()
			group.name = "Z%03d" % roundi(zoom * 100.0)
			group.mouse_filter = Control.MOUSE_FILTER_IGNORE
			group.position = Vector2(left, LABEL_PX)
			half.add_child(group)
			var at: float = 0.0
			for frame: int in frames:
				var box: Rect2i = LifeRegions.region(kind, frame)
				var rect: TextureRect = _rect(_frame_texture(kind, frame), Vector2(box.size), zoom)
				rect.name = "F%d" % frame
				rect.position = Vector2(at, tallest - rect.size.y)
				group.add_child(rect)
				at += rect.size.x + FRAME_GAP_PX
			left += at - FRAME_GAP_PX + GROUP_GAP_PX


## The biggest of the camera zoom levels.
func _top_zoom() -> float:
	var top: float = 0.0
	for zoom: float in ZOOMS:
		top = maxf(top, zoom)
	return top


## The texture of frame `frame` of `kind`: one for each frame, shared by the three zooms and both
## grounds.
func _frame_texture(kind: StringName, frame: int) -> AtlasTexture:
	var key: String = "%s %d" % [kind, frame]
	if not _frame_textures.has(key):
		var part: AtlasTexture = AtlasTexture.new()
		part.atlas = _atlases[LifeRegions.ATLAS[kind]]
		part.region = Rect2(LifeRegions.region(kind, frame))
		_frame_textures[key] = part
	return _frame_textures[key]


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
