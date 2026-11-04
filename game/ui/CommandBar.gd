class_name CommandBar
extends Control
## The command bar (ADR 0025 section 9, plan P122): bottom left (upright: the full width at the
## bottom, BUILD lifted above it) while something is selected. From its start: Deselect (48 x 64
## dp, `glyph_deselect` over "CLEAR"), the selection chip (the first type's item card, "xN" or a
## building's name, the summed health, "+N" for further types) and the orders the game has, from
## `ORDERS` (Stop, for units; a building has none). Orders that do not fit scroll sideways inside
## the bar, a button never shrinks below 56 dp. A row that adds an order adds an `ORDERS` entry, its
## glyph and its HOW_TO_PLAY line. There is no Attack button (ADR 0025 answer 4).
## The bar is view and input state: Deselect sends no Command (`PlayerController.deselect`), Stop
## sends one STOP (`PlayerController.stop`).
## Its slot (shown or not) follows the selection, except while placement or the strike aim run: it
## keeps the slot it had when the mode began, as an empty plate when the selection empties, so
## BUILD, the strike button and its check mark and X do not move under the thumb (ADR 0025 section
## 1). The
## slot and the bar's content width go to `HudState.set_bar`; every part that stands by the bar
## (BUILD, the strike button, the group column, the full map) reads them through the state.
## Its rect is `HudCorners.BAR`, taken on every change and every resize. `mirror` flips it and its
## content (left-handed mode, Phase 5).

signal order_pressed(id: StringName)

const ICON_ART: String = "res://assets/art/iso/icons/item_%s.svg"  ## The generated item cards.
const GLYPH_ART: String = "res://assets/art/svg/icons/glyph_%s.svg"
const CARD_DP: float = 40.0
const CLEAR_DP: Vector2 = Vector2(48.0, 64.0)
const ORDER_DP: Vector2 = Vector2(56.0, 64.0)  ## An order button's least size.
const GLYPH_DP: float = 28.0
const HEALTH_DP: Vector2 = Vector2(40.0, 6.0)
const LABEL_MAX_DP: float = 140.0  ## The most a building's name or a count may ask of the bar.
const CAPTION: StringName = &"ItemCaption"
const NUMBER: StringName = &"NumberLabel"
const CHIP: StringName = &"SelectionPanel"  ## The backdrop variation of the theme.
## The orders, in the bar's order: id, glyph, word, and whether it is for units.
const ORDERS: Array[Dictionary] = [
	{"id": &"stop", "glyph": "stop", "label": "STOP", "units": true},
]

@export var runner: MatchRunner
@export var controller: PlayerController
@export var feed: HudStateFeed
@export var safe_area: SafeAreaMargin
@export var placement: PlacementController
@export var strike_aim: StrikeAim
@export var build_button: BuildButton  ## Its Ready chip narrows the landscape room.
@export var building_layer: BuildingLayer  ## An enemy building the fog hides shows no health.
var mirror: bool = false

var _row: HBoxContainer = HBoxContainer.new()
var _clear: Button = Button.new()
var _chip: PanelContainer = PanelContainer.new()
var _card: TextureRect = TextureRect.new()
var _label: Label = Label.new()  ## "xN" for units, the name of a building.
var _health: ProgressBar = ProgressBar.new()
var _more: Label = Label.new()
var _scroll: ScrollContainer = ScrollContainer.new()
var _orders: HBoxContainer = HBoxContainer.new()
var _buttons: Dictionary[StringName, Button] = {}
var _has: bool = false  ## Something is selected.
var _frozen: bool = false  ## A mode runs: the slot is `_held`.
var _held: bool = false
var _slot: bool = false  ## The bar holds its place (shown or an empty plate).
var _type: StringName = &""  ## The chip's card, to load it once.
var _publish_queued: bool = false
var _published: float = 0.0  ## The content width last told to the state, dp.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # The gaps belong to the map; the parts below stop.
	visible = false
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	_build_clear()
	_build_chip()
	_scroll.name = "Orders"
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER  # Touch scrolls, no bar.
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_orders.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_orders)
	_row.add_child(_scroll)
	for order: Dictionary in ORDERS:
		_add_order(order)
	_clear.pressed.connect(func() -> void: controller.deselect())
	controller.selection_changed.connect(_on_selection)
	runner.ticked.connect(_on_ticked)
	if placement != null:
		placement.changed.connect(_update_slot)
	if strike_aim != null:
		strike_aim.changed.connect(_update_slot)
	if build_button != null:
		build_button.ready_changed.connect(place)
	feed.state.changed.connect(_on_state_changed)
	_row.minimum_size_changed.connect(_queue_publish)
	_orders.minimum_size_changed.connect(_queue_publish)
	_chip.minimum_size_changed.connect(_queue_publish)
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()
	_on_selection(controller.selection.selected)


## Whether the bar holds its place now: shown, or an empty plate kept by a mode.
func has_slot() -> bool:
	return _slot


## The order button `id`, or null.
func order_button(id: StringName) -> Button:
	return _buttons.get(id)


func _build_clear() -> void:
	_clear.name = "Deselect"
	_clear.focus_mode = Control.FOCUS_NONE
	_face(_clear, "deselect", "CLEAR")
	_row.add_child(_clear)


func _add_order(order: Dictionary) -> void:
	var button: Button = Button.new()
	var id: StringName = order["id"]
	button.name = str(id).capitalize()
	button.focus_mode = Control.FOCUS_NONE
	_face(button, order["glyph"], order["label"])
	button.pressed.connect(
		func() -> void:
			order_pressed.emit(id)
			if id == &"stop":
				controller.stop()
	)
	_orders.add_child(button)
	_buttons[id] = button


## A glyph over a word on a button; the faces ignore touches, the button takes them.
func _face(button: Button, glyph: String, word: String) -> void:
	var face: VBoxContainer = VBoxContainer.new()
	face.name = "Face"
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.alignment = BoxContainer.ALIGNMENT_CENTER
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon: TextureRect = TextureRect.new()
	icon.name = "Glyph"
	icon.texture = load(GLYPH_ART % glyph)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(icon)
	var text: Label = Label.new()
	text.name = "Word"
	text.text = word
	text.theme_type_variation = CAPTION
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(text)
	button.add_child(face)


func _build_chip() -> void:
	_chip.name = "Chip"
	_chip.theme_type_variation = CHIP
	_chip.mouse_filter = Control.MOUSE_FILTER_STOP  # A touch on the read-only chip is no order.
	var line: HBoxContainer = HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.name = "Card"
	_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(_card)
	var text: VBoxContainer = VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.name = "Count"
	_label.theme_type_variation = NUMBER
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(_label)
	_health.name = "Health"
	_health.show_percentage = false
	_health.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(_health)
	line.add_child(text)
	_more.name = "More"
	_more.theme_type_variation = NUMBER
	_more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(_more)
	_chip.add_child(line)
	_row.add_child(_chip)


## Sizes are dp, so they follow a resize.
func _apply_dp() -> void:
	_row.add_theme_constant_override("separation", roundi(UiScale.dp(HudCorners.GAP_DP)))
	_orders.add_theme_constant_override("separation", roundi(UiScale.dp(HudCorners.GAP_DP)))
	_clear.custom_minimum_size = UiScale.dp_vec(CLEAR_DP.x, CLEAR_DP.y)
	_chip.custom_minimum_size = UiScale.dp_vec(0.0, CLEAR_DP.y)
	_card.custom_minimum_size = UiScale.dp_vec(CARD_DP, CARD_DP)
	_fit_label()
	_health.custom_minimum_size = UiScale.dp_vec(HEALTH_DP.x, HEALTH_DP.y)
	for button: Button in _buttons.values():
		button.custom_minimum_size = UiScale.dp_vec(ORDER_DP.x, ORDER_DP.y)
	for button: Button in [_clear] + _buttons.values():
		var icon: Control = button.get_node("Face/Glyph")
		icon.custom_minimum_size = UiScale.dp_vec(GLYPH_DP, GLYPH_DP)
	place()


func _on_selection(ids: PackedInt32Array) -> void:
	_has = not ids.is_empty()
	_fill(ids)
	_update_slot()


func _on_ticked(_tick: int) -> void:
	if visible and _has:
		_fill(controller.selection.selected)


## Writes the chip and the order list for `ids` (texts only when they change).
func _fill(ids: PackedInt32Array) -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	var units: bool = controller.units_selected()
	var types: Dictionary[int, int] = {}  # Type index -> how many, in first-seen order.
	var hp: int = 0
	var max_hp: int = 0
	if snap != null:
		for id: int in ids:
			var row: int = snap.index_of(id)
			if row < 0:
				continue
			var type: int = snap.type_index[row]
			types[type] = types.get(type, 0) + 1
			hp += snap.hp[row]
			max_hp += snap.type_max_hp[type]
	_chip.visible = not types.is_empty()
	for order: Dictionary in ORDERS:
		_buttons[order["id"]].visible = units and not types.is_empty()
	if types.is_empty():
		return
	var first: int = types.keys()[0]
	var text: String = "×%d" % types[first] if units else snap.type_names[first]
	if _label.text != text:
		_label.text = text
		_fit_label()
	if _type != snap.type_ids[first]:
		_type = snap.type_ids[first]
		var art: String = ICON_ART % _type
		_card.texture = load(art) if ResourceLoader.exists(art) else null
	var more: String = "+%d" % (types.size() - 1) if types.size() > 1 else ""
	if _more.text != more:
		_more.text = more
	_more.visible = more != ""
	_health.max_value = maxf(max_hp, 1.0)
	_health.value = hp
	_health.visible = not (not units and building_layer != null and _hidden(snap, ids))


## Whether a selected building stands in the fog (an enemy one the player does not see): its
## health is not told then, as `HealthBarLayer` does not draw it.
func _hidden(snap: MatchSnapshot, ids: PackedInt32Array) -> bool:
	for id: int in ids:
		var row: int = snap.index_of(id)
		if row >= 0 and not building_layer.is_shown(row):
			return true
	return false


## The label asks for its text's width, at most `LABEL_MAX_DP` (a longer name is cut), so the
## chip and the bar grow to it instead of cutting every building name to the health bar's width.
func _fit_label() -> void:
	var font: Font = _label.get_theme_font(&"font")
	var font_px: int = _label.get_theme_font_size(&"font_size")
	var text_px: float = (
		font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px).x
	)
	_label.custom_minimum_size.x = minf(ceilf(text_px), UiScale.dp(LABEL_MAX_DP))


## The slot follows the selection, or what it was when a mode began (the freeze).
func _update_slot() -> void:
	var moded: bool = (
		(placement != null and placement.active) or (strike_aim != null and strike_aim.active)
	)
	if moded and not _frozen:
		_held = _slot  # The slot the bar has as the mode begins, not what the selection says now.
	_frozen = moded
	_slot = _held if _frozen else _has
	_publish()


func _queue_publish() -> void:
	if not _publish_queued:
		_publish_queued = true
		_publish.call_deferred()


## Tells the state the slot and the content width (dp); it tells the parts that stand by the bar.
func _publish() -> void:
	_publish_queued = false
	_published = _content_dp()
	feed.state.set_bar(_slot, _published)
	place()


## The width the content asks for, in dp: the row, and the orders the scroll does not count.
func _content_dp() -> float:
	var asks: float = _row.get_combined_minimum_size().x + _orders.get_combined_minimum_size().x
	return ceilf(asks) / UiScale.base_px_per_dp()  # Whole px, so the row never asks for more.


func _on_state_changed(_previous: HudState.Unfold) -> void:
	place()


## Takes the rect `HudCorners.place` gives the bar; hidden without a slot, under the upright sheet
## and in the pause menu.
func place() -> void:
	var dp: float = UiScale.base_px_per_dp()
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	feed.state.fill(shown)
	feed.state.fill_bar(shown)
	shown.bar = true  # Its own rect is asked for whether it holds the slot or not.
	shown.ready = build_button != null and build_button.ready_type >= 0
	var margin_dp: float = (
		SafeAreaMargin.DEFAULT_MARGIN_DP if safe_area == null else safe_area.margin_dp
	)
	var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), margin_dp)
	var rects: Dictionary[StringName, Rect2] = HudCorners.place(
		safe, HudLayout.is_portrait(), dp, mirror, shown
	)
	_row.layout_direction = (
		Control.LAYOUT_DIRECTION_RTL if mirror else Control.LAYOUT_DIRECTION_LTR
	)
	visible = _slot and rects.has(HudCorners.BAR) and not feed.state.is_open(HudState.Unfold.PAUSE)
	if rects.has(HudCorners.BAR):
		position = rects[HudCorners.BAR].position
		size = rects[HudCorners.BAR].size
		_row.size = size  # The row is the bar's size now; a row that grew once must not stay grown.
	if not is_equal_approx(_content_dp(), _published):  # The sizes settled after the last tell.
		_queue_publish()
	# The scroll takes touches only while the orders overflow it: else its empty part is the map's.
	var overflow: bool = _orders.get_combined_minimum_size().x > _scroll.size.x + 0.5
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS if overflow else Control.MOUSE_FILTER_IGNORE
