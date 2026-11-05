class_name CommandBar
extends Control
## The command bar (ADR 0025 section 9, plan P122): bottom left (upright too) while something is
## selected. From its start: Deselect (48 x 64 dp, `glyph_deselect` over "CLEAR"), the selection
## chips (one per selected type while they fit in the bar's room: the type's item card, "xN" or a
## building's name, its health; then a "+N" chip for the types left out; an enemy building's chip
## wears P115b's look: amber corner brackets round its picture and an amber health bar with a notch
## in its top edge) and the orders the game has, from `ORDERS` (Stop, for units; a building has
## none). Orders that do not fit scroll sideways inside the bar, a button never shrinks below 56 dp.
## A row that adds an order adds an `ORDERS` entry, its glyph and its HOW_TO_PLAY line. There is no
## Attack button (ADR 0025 answer 4).
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
const ENEMY_BAR: StringName = &"EnemyHealth"  ## The amber health bar of an enemy building.
const FRAME: StringName = &"SelectionFrame"  ## The theme type of the brackets' and notch colours.
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
var _chips: Array[Chip] = []  ## One per selected type; the first from the start.
var _types: int = 0  ## The selected types, the first `_types` of `_chips` hold one.
var _more_chip: PanelContainer = PanelContainer.new()  ## "+N": the types the bar has no room for.
var _more: Label = Label.new()
var _scroll: ScrollContainer = ScrollContainer.new()
var _orders: HBoxContainer = HBoxContainer.new()
var _buttons: Dictionary[StringName, Button] = {}
var _has: bool = false  ## Something is selected.
var _frozen: bool = false  ## A mode runs: the slot is `_held`.
var _held: bool = false
var _held_px: float = 0.0  ## The bar's width as the mode began: the room while it runs.
var _slot: bool = false  ## The bar holds its place (shown or an empty plate).
var _publish_queued: bool = false
var _published: float = 0.0  ## The content width last told to the state, dp.


## One selected type: its item card, "xN" (a building: its name) and the health of its rows.
class Chip:
	extends PanelContainer

	var card: TextureRect = TextureRect.new()
	var label: Label = Label.new()  ## "xN" for units, the name of a building.
	var health: HealthBar = HealthBar.new()
	var type: StringName = &""  ## The card's type, to load it once.
	var enemy: bool = false

	func _init() -> void:
		theme_type_variation = CHIP
		mouse_filter = Control.MOUSE_FILTER_STOP  # A touch on the read-only chip is no order.
		var line: HBoxContainer = HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.name = "Card"
		card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # The picture's square, not the slot.
		card.draw.connect(_paint_frame)  # Over the picture: the card draws it before this signal.
		line.add_child(card)
		var text: VBoxContainer = VBoxContainer.new()
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.name = "Count"
		label.theme_type_variation = NUMBER
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_child(label)
		health.name = "Health"
		health.show_percentage = false
		health.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_child(health)
		line.add_child(text)
		add_child(line)

	## Writes the chip for one type; an enemy building wears P115b's look (brackets, amber bar).
	func show_type(snap: MatchSnapshot, group: Group, as_enemy: bool) -> void:
		var units: bool = not group.building
		var text: String = "×%d" % group.count if units else snap.type_names[group.type]
		if label.text != text:
			label.text = text
			fit_label()
		if type != snap.type_ids[group.type]:
			type = snap.type_ids[group.type]
			var art: String = ICON_ART % type
			card.texture = load(art) if ResourceLoader.exists(art) else null
		if enemy != as_enemy:
			enemy = as_enemy
			health.set_enemy(enemy)
			card.queue_redraw()
		health.max_value = maxf(group.max_hp, 1.0)
		health.value = group.hp
		health.visible = not group.fogged

	## The label asks for its text's width, at most `LABEL_MAX_DP` (a longer name is cut), so the
	## chip and the bar grow to it instead of cutting every building name to the health bar's width.
	func fit_label() -> void:
		var font: Font = label.get_theme_font(&"font")
		var font_px: int = label.get_theme_font_size(&"font_size")
		var text_px: float = (
			font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px).x
		)
		label.custom_minimum_size.x = minf(ceilf(text_px), UiScale.dp(LABEL_MAX_DP))

	func apply_dp() -> void:
		custom_minimum_size = UiScale.dp_vec(0.0, CLEAR_DP.y)
		card.custom_minimum_size = UiScale.dp_vec(CARD_DP, CARD_DP)
		health.custom_minimum_size = UiScale.dp_vec(HEALTH_DP.x, HEALTH_DP.y)
		fit_label()

	## The brackets of an enemy building's chip (none for any other), as `HealthBarLayer` frames a
	## selected building: four corners round the picture, each an arm `FRAME_ARM_DP` long at the
	## most and `FRAME_THICK_DP` thick, the dark outline of every arm first (8 rects), then the 8
	## arms, in the card's coordinates. They are drawn over the picture and take no room.
	func frame_rects() -> Array[Rect2]:
		var out: Array[Rect2] = []
		if not enemy:
			return out
		var box: Rect2 = Rect2(Vector2.ZERO, card.size)  # In the card's own coordinates.
		var dp: float = UiScale.base_px_per_dp()
		var arm: float = minf(HealthBarLayer.FRAME_ARM_DP * dp, 0.4 * minf(box.size.x, box.size.y))
		var thick: float = HealthBarLayer.FRAME_THICK_DP * dp
		for outline: int in 2:
			for arm_at: int in 8:
				var corner: int = arm_at >> 1
				var way: Vector2 = Vector2(-1.0 if corner & 1 else 1.0, -1.0 if corner & 2 else 1.0)
				var from: Vector2 = Vector2(
					box.end.x if corner & 1 else box.position.x,
					box.end.y if corner & 2 else box.position.y
				)
				var along: Vector2 = Vector2(arm, thick) if arm_at & 1 == 0 else Vector2(thick, arm)
				var rect: Rect2 = Rect2(from, along * way).abs()
				out.append(rect.grow(HealthBarLayer.EDGE_DP * dp) if outline == 0 else rect)
		return out

	## Paints the brackets on the card, after its picture (the card's `draw` signal).
	func _paint_frame() -> void:
		var rects: Array[Rect2] = frame_rects()
		for index: int in rects.size():
			var tone: StringName = &"edge" if index < 8 else &"enemy"
			card.draw_rect(rects[index], get_theme_color(tone, FRAME))


## A chip's health bar. An enemy building's is amber (the theme's `EnemyHealth`) with a notch in
## its top edge, the cue that does not rest on colour alone: `HealthBarLayer`'s enemy bar.
class HealthBar:
	extends ProgressBar

	var enemy: bool = false

	func set_enemy(on: bool) -> void:
		enemy = on
		theme_type_variation = ENEMY_BAR if on else &""
		queue_redraw()

	## The notch, `NOTCH_WIDTH_DP` by `NOTCH_DEPTH_DP` at the middle of the top edge (empty for an
	## own bar).
	func notch_rect() -> Rect2:
		if not enemy:
			return Rect2()
		var dp: float = UiScale.base_px_per_dp()
		var width: float = HealthBarLayer.NOTCH_WIDTH_DP * dp
		return Rect2(roundf((size.x - width) / 2.0), 0.0, width, HealthBarLayer.NOTCH_DEPTH_DP * dp)

	func _draw() -> void:
		var notch: Rect2 = notch_rect()
		if notch.size != Vector2.ZERO:
			draw_rect(notch, get_theme_color(&"edge", FRAME))


## What the selection holds of one type, for `_fill`.
class Group:
	extends RefCounted

	var type: int = 0
	var count: int = 0
	var hp: int = 0
	var max_hp: int = 0
	var row: int = 0  ## The first row of the type.
	var building: bool = false
	var fogged: bool = false  ## A building the fog hides: its health is not told.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # The gaps belong to the map; the parts below stop.
	visible = false
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	_build_clear()
	_build_more()
	_chip_for(0)  # The first chip stands from the start, the others when a selection needs them.
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


## The "+N" plate (the type chips are made when a selection first needs them, `_chip_for`).
func _build_more() -> void:
	_more_chip.name = "More"
	_more_chip.theme_type_variation = CHIP
	_more_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	_more_chip.visible = false
	_more.name = "Number"
	_more.theme_type_variation = NUMBER
	_more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_more.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_more_chip.add_child(_more)
	_row.add_child(_more_chip)
	_more_chip.minimum_size_changed.connect(_queue_publish)


## Chip `index`, made (after the chips before it, before "+N") when the selection first has that
## many types. The first is named "Chip", the others "Chip1", "Chip2" and so on.
func _chip_for(index: int) -> Chip:
	while _chips.size() <= index:
		var chip: Chip = Chip.new()
		chip.name = "Chip" if _chips.is_empty() else "Chip%d" % _chips.size()
		chip.visible = false
		chip.minimum_size_changed.connect(_queue_publish)
		_row.add_child(chip)
		chip.apply_dp()
		_row.move_child(chip, 1 + _chips.size())  # After Deselect and the chips before it.
		_chips.append(chip)
	return _chips[index]


## Sizes are dp, so they follow a resize.
func _apply_dp() -> void:
	_row.add_theme_constant_override("separation", roundi(UiScale.dp(HudCorners.GAP_DP)))
	_orders.add_theme_constant_override("separation", roundi(UiScale.dp(HudCorners.GAP_DP)))
	_clear.custom_minimum_size = UiScale.dp_vec(CLEAR_DP.x, CLEAR_DP.y)
	_more_chip.custom_minimum_size = UiScale.dp_vec(0.0, CLEAR_DP.y)
	for chip: Chip in _chips:
		chip.apply_dp()
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


## Writes the chips and the order list for `ids` (texts only when they change).
func _fill(ids: PackedInt32Array) -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	var units: bool = controller.units_selected()
	var groups: Dictionary[int, Group] = {}  # Type index -> what is selected of it, first seen first.
	if snap != null:
		for id: int in ids:
			var row: int = snap.index_of(id)
			if row < 0:
				continue
			var type: int = snap.type_index[row]
			var group: Group = groups.get(type)
			if group == null:
				group = Group.new()
				group.type = type
				group.row = row
				group.building = WorldSort.is_building(snap, type)
				groups[type] = group
			group.count += 1
			group.hp += snap.hp[row]
			group.max_hp += snap.type_max_hp[type]
			if group.building and building_layer != null and not building_layer.is_shown(row):
				group.fogged = true
	for order: Dictionary in ORDERS:
		_buttons[order["id"]].visible = units and not groups.is_empty()
	var local: int = 1 if runner == null else FogLayer.local_player_of(runner)
	var fit: bool = groups.size() != _types
	_types = groups.size()
	var index: int = 0
	for group: Group in groups.values():
		var chip: Chip = _chip_for(index)
		var before: String = chip.label.text
		chip.show_type(snap, group, group.building and snap.owner[group.row] != local)
		fit = fit or before != chip.label.text
		index += 1
	if fit:
		_fit_chips()


## Shows the chips that fit in the bar's room (while placement or the strike aim run: in the width
## the bar had as the mode began), one per type while they do, then a "+N" chip for the types left
## out (the old `SelectionPanel`'s rule: "+N" replaces the last chip that does not fit). Deselect
## and the orders come first, so Stop is never pushed out of the bar by a chip; the chips take what
## is left. The first chip always shows. The room is what the bar may be at the most
## (`HudCorners.place` with a content that asks for more than any screen has), less Deselect, the
## orders and the gaps, so the fit never depends on the width it gave.
func _fit_chips() -> void:
	var shown: int = _types
	if _types > 1:  # One type always shows its chip.
		var gap: float = roundf(UiScale.dp(HudCorners.GAP_DP))
		var rects: Dictionary[StringName, Rect2] = _rects(true)
		var room: float = rects[HudCorners.BAR].size.x if rects.has(HudCorners.BAR) else INF
		if _frozen:
			room = minf(room, _held_px)  # The bar never grows under the thumb.
		room -= _clear.get_combined_minimum_size().x + _orders.get_combined_minimum_size().x
		# A mode runs: even the first chip may give way, so "+N" alone counts the types.
		for count: int in range(_types, -1 if _frozen else 0, -1):
			shown = count
			var need: float = gap * (count + 1)  # Between Deselect, the chips, "+N" and the orders.
			for index: int in count:
				need += _chips[index].get_combined_minimum_size().x
			if count < _types:
				_more.text = "+%d" % (_types - count)
				need += gap + _more_chip.get_combined_minimum_size().x
			if need <= room:
				break
	for index: int in _chips.size():
		_chips[index].visible = index < shown
	_more_chip.visible = shown < _types
	if shown < _types:
		_more.text = "+%d" % (_types - shown)


## Every chip's label asks for its own text again (the text or the dp changed).
func _fit_label() -> void:
	for chip: Chip in _chips:
		chip.fit_label()


## The slot follows the selection, or what it was when a mode began (the freeze).
func _update_slot() -> void:
	var moded: bool = (
		(placement != null and placement.active) or (strike_aim != null and strike_aim.active)
	)
	if moded and not _frozen:
		_held = _slot  # The slot the bar has as the mode begins, not what the selection says now.
		_held_px = size.x  # And its width: no selection widens the bar under the thumb.
	var changed: bool = moded != _frozen
	_frozen = moded
	_slot = _held if _frozen else _has
	if changed:
		_fit_chips()  # The room is the held width while the mode runs, the bar's own after it.
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


## The layout's rects: with the width the content asks for now, or (`widest`) with a content that
## asks for more than any screen has, which gives the room the bar may take at the most.
func _rects(widest: bool) -> Dictionary[StringName, Rect2]:
	var dp: float = UiScale.base_px_per_dp()
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	feed.state.fill(shown)
	feed.state.fill_bar(shown)
	shown.bar = true  # Its own rect is asked for whether it holds the slot or not.
	if widest:
		shown.bar_width = INF
	shown.ready = build_button != null and build_button.ready_type >= 0
	var margin_dp: float = (
		SafeAreaMargin.DEFAULT_MARGIN_DP if safe_area == null else safe_area.margin_dp
	)
	var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), margin_dp)
	return HudCorners.place(safe, HudLayout.is_portrait(), dp, mirror, shown)


## Takes the rect `HudCorners.place` gives the bar; hidden without a slot, under the upright sheet
## and in the pause menu.
func place() -> void:
	if _types > 1:
		_fit_chips()  # The room changes with the Ready chip, the drawer and the window.
	var rects: Dictionary[StringName, Rect2] = _rects(false)
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
