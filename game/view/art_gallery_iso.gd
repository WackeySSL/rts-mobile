extends Control
## The Iso page of the art gallery (plan row P99, ADR 0023 section 5): the generated blockouts of
## both factions, one type at a time (the two buttons step through them), every direction of the
## type at gameplay zoom in both team colours, and its default view at the camera zoom levels 0.75,
## 1 and 1.5. The grass half shows the frames in the Signal triad, the sand half in the Arktisk
## one; the rows repeat for the second triad under the first. A frame is the SVG text with the
## faction's key triad replaced by the player's (the match-start bake does the same, ADR 0023
## section 2) and rasterised at 0.5 x zoom; until the per-match atlas exists (P113) the page
## rasterises the frames itself. A turret or head sits at its mount (`ArtGen.mount_px`). Built on
## first show; view-only.

const FACTION_NAMES: Dictionary[StringName, String] = {
	&"fossil": "Derrick League", &"renew": "Lumen Accord"
}
## The players' triads (ADR 0023 section 5): player 1 Signal, player 2 Arktisk.
const TRIADS: Array[Array] = [
	["#FF9446", "#E8681F", "#B04B12"],
	["#62D6EE", "#1FA6C8", "#137C99"],
]
const TRIAD_NAMES: Array[String] = ["Signal", "Arktisk"]
const BASE_SCALE: float = 0.5  ## 2x art at zoom 1: one tile is 64 px.
const ZOOMS: Array[float] = [0.75, 1.0, 1.5]  ## The camera zoom levels.
const HALF_WIDTH_PX: float = 640.0  ## One ground at the 16:9 base size.
const SLOT_GAP_PX: float = 8.0
const PER_LINE: int = 8  ## Directions: eight to a line, a wide frame may reach into its neighbour.
const LINE_GAP_PX: float = 12.0
const FIRST_TOP_PX: float = 160.0  ## Clear of the corner buttons, which cover 24 to 144 px.
const LABEL_PX: float = 26.0
const LABEL_FONT_PX: int = 20
const LABEL_COLOR: Color = Color("1C2127")
const BUTTON_PX: float = 120.0
const BUTTON_FONT_PX: int = 40
const TITLE_LEFT_PX: float = 432.0

var grass_color: Color = Color("6F8F57")
var sand_color: Color = Color("CDB98F")
var _paths: Array[String] = []
var _index: int = 0
var _title: Label = null
var _content: Control = null
var _textures: Dictionary[String, ImageTexture] = {}


func _init() -> void:
	name = "IsoPage"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0
	visible = false


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)


## The list, the two buttons and the title, built when the page is first shown, so that a gallery
## that never turns to this page holds none of them.
func _build_ui() -> void:
	_paths = ArtGen.model_paths()
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_content = Control.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	for step: int in [-1, 1]:
		var button: Button = Button.new()
		button.name = "Next" if step > 0 else "Previous"
		button.text = ">" if step > 0 else "<"
		button.position = Vector2(160.0 if step < 0 else 160.0 + BUTTON_PX + 16.0, 24.0)
		button.custom_minimum_size = Vector2(BUTTON_PX, BUTTON_PX)
		button.size = button.custom_minimum_size
		button.add_theme_font_size_override(&"font_size", BUTTON_FONT_PX)
		button.pressed.connect(_step.bind(step))
		add_child(button)
	_title = _label("", 560.0)
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.position = Vector2(TITLE_LEFT_PX + 24.0, 24.0 + BUTTON_PX / 2.0 - LABEL_PX / 2.0)
	add_child(_title)


func _on_visibility_changed() -> void:
	if not visible:
		return
	if _content == null:
		_build_ui()
		_fill()


func _step(step: int) -> void:
	_index = posmod(_index + step, _paths.size())
	_fill()


func _fill() -> void:
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_textures.clear()
	var model: ArtModel = load(_paths[_index]) as ArtModel
	_title.text = (
		"%d / %d  %s: %s (%s)"
		% [_index + 1, _paths.size(), FACTION_NAMES[model.faction], model.art_id, model.category]
	)
	var layouts: Dictionary[StringName, ArtGen.Layout] = ArtGen.layouts(model)
	var box: Rect2 = _box(model, layouts)
	var grounds: Array[ColorRect] = [_ground("Grass", grass_color), _ground("Sand", sand_color)]
	var top: float = FIRST_TOP_PX
	for triad: int in TRIADS.size():
		var height: float = 0.0
		for ground: ColorRect in grounds:
			height = _section(ground, model, layouts, box, triad, top)
		top += height
	_content.custom_minimum_size = Vector2(0.0, maxf(top, get_viewport_rect().size.y))


## One triad on one ground: its label, a line per 8 directions at zoom 1 and the zoom row of the
## default view. Returns the height it took.
func _section(
	ground: ColorRect,
	model: ArtModel,
	layouts: Dictionary[StringName, ArtGen.Layout],
	box: Rect2,
	triad: int,
	top: float
) -> float:
	var row: Control = Control.new()
	row.name = TRIAD_NAMES[triad]
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.anchor_left = 0.5
	row.anchor_right = 0.5
	row.offset_top = top
	ground.add_child(row)
	var title: Label = _label(
		"%s, %s" % [TRIAD_NAMES[triad], "zoom 1, then 0.75 / 1 / 1.5"], HALF_WIDTH_PX
	)
	title.position.x = -HALF_WIDTH_PX / 2.0
	row.add_child(title)
	var rigs: Array[Node2D] = []
	var zooms: Array[float] = []
	var turning: StringName = &"head" if layouts.has(&"head") else &"hull"
	if model.category != &"bld" or layouts.has(&"head"):
		for dir: int in model.directions(turning):
			rigs.append(_rig(model, layouts, dir, triad, 1.0, "Dir%02d" % dir))
			zooms.append(1.0)
	var y: float = _flow(row, rigs, zooms, box, LABEL_PX, _slot_cap(box))
	rigs.clear()
	var default_dir: int = 6 if model.faction == &"fossil" else 10
	for zoom: float in ZOOMS:
		rigs.append(_rig(model, layouts, default_dir, triad, zoom, "Zoom%d" % roundi(zoom * 100.0)))
	return _flow(row, rigs, ZOOMS, box, y, INF)


## The widest slot of a direction row that keeps eight to a line and the first and last rig, which
## reach past their slots, on the ground.
func _slot_cap(box: Rect2) -> float:
	var usable: float = (
		HALF_WIDTH_PX - 16.0 - (PER_LINE - 1) * SLOT_GAP_PX - box.size.x * BASE_SCALE
	)
	return usable / (PER_LINE - 1)


## Places the rigs left to right in lines no wider than a ground, each line centred, each rig's box
## centred in a slot of its width (at most `cap`); returns the `y` under the last line.
func _flow(
	row: Control, rigs: Array[Node2D], zooms: Array[float], box: Rect2, y: float, cap: float
) -> float:
	var lines: Array[PackedInt32Array] = []
	var widths: Array[float] = []
	var slots: Array[float] = []
	for i: int in rigs.size():
		slots.append(minf(box.size.x * BASE_SCALE * zooms[i], cap))
		var fits: bool = (
			not lines.is_empty()
			and widths[-1] + SLOT_GAP_PX + slots[i] <= HALF_WIDTH_PX - 16.0 + 0.5
		)
		if not fits:
			lines.append(PackedInt32Array())
			widths.append(-SLOT_GAP_PX)
		lines[-1].append(i)
		widths[-1] += SLOT_GAP_PX + slots[i]
	for n: int in lines.size():
		var x: float = -widths[n] / 2.0
		var up: float = 0.0
		var down: float = 0.0
		for k: int in lines[n]:
			up = maxf(up, -box.position.y * BASE_SCALE * zooms[k])
			down = maxf(down, box.end.y * BASE_SCALE * zooms[k])
		for k: int in lines[n]:
			var middle: float = x + slots[k] / 2.0 - box.get_center().x * BASE_SCALE * zooms[k]
			rigs[k].position = Vector2(middle, y + up)
			row.add_child(rigs[k])
			x += slots[k] + SLOT_GAP_PX
		y += up + down + LINE_GAP_PX
	return y


## A hull and its turret or head, facing `dir` (a building has one view and only its head turns),
## standing on the rig's origin.
func _rig(
	model: ArtModel,
	layouts: Dictionary[StringName, ArtGen.Layout],
	dir: int,
	triad: int,
	zoom: float,
	rig_name: String
) -> Node2D:
	var rig: Node2D = Node2D.new()
	rig.name = rig_name
	var hull_dir: int = -1 if model.category == &"bld" else dir
	rig.add_child(_sprite(model, &"hull", hull_dir, layouts[&"hull"], triad, zoom))
	for part: StringName in [&"turret", &"head"]:
		if layouts.has(part):
			var top: Sprite2D = _sprite(model, part, dir, layouts[part], triad, zoom)
			top.position = ArtGen.mount_px(model, 6 if model.category == &"bld" else dir)
			top.position *= BASE_SCALE * zoom
			rig.add_child(top)
	return rig


func _sprite(
	model: ArtModel, part: StringName, dir: int, layout: ArtGen.Layout, triad: int, zoom: float
) -> Sprite2D:
	var scale_px: float = BASE_SCALE * zoom
	var key: String = "%s %d %d %s" % [ArtGen.frame_path(model, part, dir), dir, triad, zoom]
	if not _textures.has(key):
		var text: String = FileAccess.get_file_as_string(ArtGen.frame_path(model, part, dir))
		for tone: int in 3:
			text = text.replace(ArtPalette.KEYS[model.faction][tone], TRIADS[triad][tone])
		var image: Image = Image.new()
		image.load_svg_from_string(text, scale_px)
		_textures[key] = ImageTexture.create_from_image(image)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = String(part).capitalize()
	sprite.texture = _textures[key]
	sprite.centered = false
	sprite.offset = -Vector2(layout.origin) * scale_px
	return sprite


## Everything a rig of the model can cover, in 2x px from its ground point.
func _box(model: ArtModel, layouts: Dictionary[StringName, ArtGen.Layout]) -> Rect2:
	var hull: ArtGen.Layout = layouts[&"hull"]
	var box: Rect2 = Rect2(-Vector2(hull.origin), Vector2(hull.size))
	for part: StringName in [&"turret", &"head"]:
		if layouts.has(part):
			for dir: int in model.directions(part):
				var layout: ArtGen.Layout = layouts[part]
				var at: Vector2 = ArtGen.mount_px(model, 6 if model.category == &"bld" else dir)
				box = box.merge(Rect2(at - Vector2(layout.origin), Vector2(layout.size)))
	return box


func _ground(ground_name: String, color: Color) -> ColorRect:
	var is_grass: bool = ground_name == "Grass"
	var ground: ColorRect = ColorRect.new()
	ground.name = ground_name
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ground.color = color
	ground.anchor_left = 0.0 if is_grass else 0.5
	ground.anchor_right = 0.5 if is_grass else 1.0
	ground.anchor_bottom = 1.0
	_content.add_child(ground)
	return ground


func _label(text: String, width: float) -> Label:
	var label: Label = Label.new()
	label.name = "Label"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", LABEL_FONT_PX)
	label.add_theme_color_override(&"font_color", LABEL_COLOR)
	label.size = Vector2(width, LABEL_PX)
	return label
