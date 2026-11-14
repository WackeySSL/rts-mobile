class_name CommandBar
extends Control
## The command bar (ADR 0025 section 9, plan P122): bottom left (upright too) while something is
## selected. From its start: Deselect (48 x 64 dp, `glyph_deselect` over "CLEAR"), the selection
## chips (one per selected type while they fit in the bar's room: the type's item card, "xN" or a
## building's name, its health; then a "+N" chip for the types left out; an enemy building's chip
## wears P115b's look: amber corner brackets round its picture and an amber health bar with a notch
## in its top edge) and the orders the game has, from `ORDERS`: each is `for` units (Stop) or for
## one own complete building (Mend, Sell). Orders that do not fit scroll sideways inside the bar, a
## button never shrinks below 56 dp. Board (squads selected, an own carrier on the map with a free
## seat) and Unload (a loaded carrier selected) are order aims (`CarryAim`, P265): a tap starts the
## aim, a second tap on the lit button ends it, and the slot stays frozen while it runs.
## A row that adds an order adds an `ORDERS` entry with its `for`, its glyph and its HOW_TO_PLAY
## line, and one arm of `_order` (the tap) and, for a building order, one of `_building_order`
## (whether it shows, and its state); `_sync_toggle` and `_fix_width(id)` serve a lit order and a
## button with a changing word. There is no Attack button (ADR 0025 answer 4).
## The bar is view and input state: Deselect sends no Command (`PlayerController.deselect`), Stop
## sends one STOP (`PlayerController.stop`). Mend (a toggle, lit while the building mends, one MEND)
## and Sell show for one own complete building (`BuildingOrders.target`; Sell only for one with a
## price); Mend is dimmed and does nothing at full health with the switch off. Sell is a two-tap
## order (`SellArm`, P272): the first tap arms it (amber, "+N", the refund now,
## `Production.sale_refund`), the second one, pressed from `sell_arm_min_ms` after the first's
## release and before `sell_confirm_ms`, sends one SELL. A contact of `long_press_ms` or more is a
## hold, no tap: it disarms and sends nothing. Any other touch, a turn of the phone or the window
## running out disarms it. The player's last production building asks first on the question card
## ("Selling it loses the match", Keep or Sell), which closes with its building, the match end,
## a tap outside or a turn. The Sell button keeps a fixed width sized for the widest "+N".
## Its slot (shown or not) follows the selection, except while placement or the strike aim run: it
## keeps the slot it had when the mode began, as an empty plate when the selection empties, and its
## width, so nothing beside it moves under the thumb (ADR 0025 section 1). The slot and the bar's
## content width go to `HudState.set_bar`; the parts that stand by the bar (the group column's
## foot, the full map) read them through the state. BUILD and the strike button do not.
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
const SHAKE_DP: float = 6.0  ## How far a refused Board shakes its face, and for how long a step.
const SHAKE_S: float = 0.05
const LABEL_MAX_DP: float = 140.0  ## The most a building's name or a count may ask of the bar.
const CAPTION: StringName = &"ItemCaption"
const NUMBER: StringName = &"NumberLabel"
const CHIP: StringName = &"SelectionPanel"  ## The backdrop variation of the theme.
const ENEMY_BAR: StringName = &"EnemyHealth"  ## The amber health bar of an enemy building.
const FRAME: StringName = &"SelectionFrame"  ## The theme type of the brackets' and notch colours.
## The orders, in the bar's order: id, glyph, word, and what it is `for`: &"units", &"building",
## &"squads" (Board) or &"carrier" (Unload).
const ORDERS: Array[Dictionary] = [
	{"id": &"stop", "glyph": "stop", "label": "STOP", "for": &"units"},
	{"id": &"board", "glyph": "board", "label": "BOARD", "for": &"squads"},
	{"id": &"unload", "glyph": "unload", "label": "UNLOAD", "for": &"carrier"},
	{"id": &"mend", "glyph": "repair", "label": "MEND", "for": &"building"},
	{"id": &"sell", "glyph": "sell", "label": "SELL", "for": &"building"},
]
const WARN_CAPTION: StringName = &"ItemCaptionWarn"  ## The armed Sell's amber "+N" (18 sp).
const LIT_CAPTION: StringName = &"ItemCaptionOn"  ## A lit order's green word and glyph.
const DIM_CAPTION: StringName = &"ItemCaptionDim"  ## A disabled order's grey word and glyph.
const LIT_PLATE: StringName = &"OrderLit"  ## A lit toggle's plate: filled, with a thick edge.
const SELL_PAD_DP: float = 8.0  ## Either side of a button's widest word.

@export var runner: MatchRunner
@export var controller: PlayerController
@export var feed: HudStateFeed
@export var safe_area: SafeAreaMargin
@export var placement: PlacementController
@export var strike_aim: StrikeAim
@export var carry_aim: CarryAim  ## The Board and Unload aims; without one the two never show.
@export var build_button: BuildButton  ## Its Ready chip narrows the landscape room.
@export var building_layer: BuildingLayer  ## An enemy building the fog hides shows no health.
## The question for selling the player's last producer (the pause menu's confirm look, P272).
@export var sell_card: ConfirmDialog
var mirror: bool = false
var shakes: int = 0  ## Refused Board taps shown, for the tests.
## Returns the time in ms. Tests replace it.
var clock: Callable = Time.get_ticks_msec

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
var _arm: SellArm = SellArm.new()
var _wide: Dictionary[StringName, Array] = {}  ## Order id -> [caption, widest word].
var _widest_serial: int = -1  ## match_serial the Sell width was worked out for.
var _refund_shown: int = -1  ## The refund the armed Sell shows, -1 when it shows "SELL".
var _down_ms: int = 0  ## When the finger last went down on Sell.
var _sell_down_now: bool = false  ## A finger is down on Sell: its arm does not lapse under it.
var _card_id: int = -1  ## The building the question card asked about, -1 for none.
var _portrait: bool = false  ## The window's orientation at the last resize.


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
	_buttons[&"mend"].toggle_mode = true  # Lit (pressed) while the building mends.
	_buttons[&"board"].toggle_mode = true  # Lit while its aim is open.
	_buttons[&"unload"].toggle_mode = true
	_buttons[&"sell"].button_down.connect(_sell_down)
	_buttons[&"sell"].button_up.connect(func() -> void: _sell_down_now = false)
	if sell_card != null:
		sell_card.confirmed.connect(_sell_confirmed)
		runner.match_ended.connect(func(_winner: int) -> void: sell_card.close())
	set_process(false)  # Only while an order runs a timer (`_needs_process`).
	_clear.pressed.connect(func() -> void: controller.deselect())
	controller.selection_changed.connect(_on_selection)
	runner.ticked.connect(_on_ticked)
	if placement != null:
		placement.changed.connect(_update_slot)
	if strike_aim != null:
		strike_aim.changed.connect(_update_slot)
	if carry_aim != null:
		carry_aim.changed.connect(_on_carry_changed)
		carry_aim.refused.connect(_shake_board)
	if build_button != null:
		build_button.ready_changed.connect(place)
	feed.state.changed.connect(_on_state_changed)
	_row.minimum_size_changed.connect(_queue_publish)
	_orders.minimum_size_changed.connect(_queue_publish)
	get_viewport().size_changed.connect(_apply_dp)
	get_viewport().size_changed.connect(_on_turn)
	_portrait = HudLayout.is_portrait()
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
			_order(id)
	)
	_orders.add_child(button)
	_buttons[id] = button


## What a tap on order `id` does.
func _order(id: StringName) -> void:
	match id:
		&"stop":
			controller.stop()
		&"board":
			if carry_aim != null and not carry_aim.toggle(CarryAim.Mode.BOARD):
				_on_carry_changed()  # A refused start must not leave the toggle lit.
		&"unload":
			if carry_aim != null and not carry_aim.toggle(CarryAim.Mode.UNLOAD):
				_on_carry_changed()
		&"mend":
			var snap: MatchSnapshot = runner.snapshot
			var row: int = BuildingOrders.target(snap, controller.selection.selected, _local())
			var on: bool = row >= 0 and BuildingOrders.mending(snap, row)
			if row >= 0 and (on or BuildingOrders.can_mend(snap, row)):
				controller.mend(not on)
		&"sell":
			_sell_pressed()


func _sell_down() -> void:
	_down_ms = int(clock.call())
	_sell_down_now = true


## The Sell button, on release: a contact of `long_press_ms` or more is a hold and disarms; a tap
## arms, or sends (or asks first, for the last producer).
func _sell_pressed() -> void:
	var snap: MatchSnapshot = runner.snapshot
	var row: int = BuildingOrders.target(snap, controller.selection.selected, _local())
	if row < 0 or not BuildingOrders.can_sell(snap, row):
		return
	var now: int = int(clock.call())
	var settings: InputSettings = controller.settings
	if now - _down_ms >= settings.long_press_ms:
		_disarm()  # A resting thumb is no tap: it never arms and never sells.
		return
	var id: int = snap.unit_id[row]
	var result: SellArm.Result = _arm.press(
		id, _down_ms, now, settings.sell_arm_min_ms, settings.sell_confirm_ms
	)
	if result == SellArm.Result.SEND:
		if sell_card != null and BuildingOrders.is_last_producer(snap, row, _local()):
			_card_id = id
			sell_card.open()  # Only its Sell sends; Keep, a tap outside or a turn closes it.
		else:
			controller.sell()
	_sync_sell(snap, row)
	set_process(_needs_process())


## The card's Sell: only for the building it asked about.
func _sell_confirmed() -> void:
	var row: int = BuildingOrders.target(runner.snapshot, controller.selection.selected, _local())
	if row >= 0 and runner.snapshot.unit_id[row] == _card_id:
		controller.sell()
	_card_id = -1


## Any other touch disarms Sell: a press that is not on the Sell button. The event goes on.
func _input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch == null or not touch.pressed or not _arm.is_armed():
		return
	var sell: Button = _buttons[&"sell"]
	if not (sell.is_visible_in_tree() and sell.get_global_rect().has_point(touch.position)):
		_disarm()


func _process(_delta: float) -> void:
	if not _sell_down_now and _arm.expired(int(clock.call()), controller.settings.sell_confirm_ms):
		_disarm()


## A turn of the phone disarms Sell and closes its question with nothing sent.
func _on_turn() -> void:
	var portrait: bool = HudLayout.is_portrait()
	if portrait == _portrait:
		return
	_portrait = portrait
	_disarm()
	if sell_card != null:
		sell_card.close()
		_card_id = -1


func _disarm() -> void:
	_arm.disarm()
	_fill(controller.selection.selected)


func _local() -> int:
	return 1 if runner == null else FogLayer.local_player_of(runner)


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
	for id: StringName in _buttons:
		_fix_width(id)
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
	var local: int = _local()
	var row: int = BuildingOrders.target(snap, ids, local)
	_sync_orders(snap, units and not groups.is_empty(), row, ids)
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


## Shows each order that acts on the selection (`units_ok` for a unit order, `row` the one own
## complete building for a building order) and brings its state up to date.
func _sync_orders(snap: MatchSnapshot, units_ok: bool, row: int, ids: PackedInt32Array) -> void:
	for order: Dictionary in ORDERS:
		var id: StringName = order["id"]
		var shown: bool = units_ok
		if order["for"] == &"building":
			shown = row >= 0 and _building_order(id, snap, row)
		elif order["for"] != &"units":
			shown = units_ok and _carry_order(id, snap, ids)
		_buttons[id].visible = shown
	if not _buttons[&"sell"].visible:
		_arm.disarm()  # The selection moved off the building: nothing is armed any more.
		_refund_shown = -1
		(_buttons[&"sell"].get_node("Face/Word") as Label).text = "SELL"
	var card_stale: bool = row < 0 or snap == null or snap.unit_id[row] != _card_id
	if sell_card != null and sell_card.visible and card_stale:
		sell_card.close()  # Its building left the selection: the question is void.
	set_process(_needs_process())


## Whether Board or Unload shows for the selection `ids` (a carrier order needs an aim to run), and
## its state: lit while its aim is open. Board shows for squads while the player has a carrier that
## takes them, Unload for a loaded carrier; a lit one shows as long as its aim runs.
func _carry_order(id: StringName, snap: MatchSnapshot, ids: PackedInt32Array) -> bool:
	if carry_aim == null or snap == null:
		return false
	var mode: CarryAim.Mode = CarryAim.Mode.BOARD if id == &"board" else CarryAim.Mode.UNLOAD
	var on: bool = carry_aim.mode == mode
	var player: int = _local()
	var shown: bool = on
	if not shown and mode == CarryAim.Mode.BOARD:
		shown = (
			not CarryRules.squads_in(snap, ids, player).is_empty()
			and CarryRules.has_carrier(snap, player)
		)
	elif not shown:
		shown = not CarryRules.loaded_in(snap, ids, player).is_empty()
	_sync_toggle(_buttons[id], on, true)
	return shown


## A refused Board tap: the button's face shakes sideways (the plate stays in its row).
func _shake_board() -> void:
	shakes += 1
	var face: Control = _buttons[&"board"].get_node("Face")
	var reach: float = UiScale.dp(SHAKE_DP)
	var tween: Tween = create_tween()
	for offset: float in [reach, -reach, 0.0]:
		tween.tween_property(face, "position:x", offset, SHAKE_S)


## An aim opened or closed, or a ring or point moved: the lit buttons and the frozen slot follow.
func _on_carry_changed() -> void:
	_fill(controller.selection.selected)
	_update_slot()


## Whether building order `id` shows for the building in `row`, and its button's state.
func _building_order(id: StringName, snap: MatchSnapshot, row: int) -> bool:
	match id:
		&"mend":
			var on: bool = BuildingOrders.mending(snap, row)
			_sync_toggle(_buttons[id], on, on or BuildingOrders.can_mend(snap, row))
			return true
		&"sell":
			if not BuildingOrders.can_sell(snap, row):
				return false
			_sync_sell(snap, row)
			return true
	return false


## Whether a frame has work: the armed Sell's window runs out.
func _needs_process() -> bool:
	return _arm.is_armed()


## A toggle order: lit (pressed, the green plate) when `on`, dimmed and not tappable when not
## `enabled`; the word and glyph take the theme's colour for the state.
func _sync_toggle(button: Button, on: bool, enabled: bool) -> void:
	button.set_pressed_no_signal(on)
	button.disabled = not enabled
	var plate: StringName = LIT_PLATE if on else &""
	if button.theme_type_variation != plate:
		button.theme_type_variation = plate
	_paint(button, LIT_CAPTION if on else (CAPTION if enabled else DIM_CAPTION))


## Sell shows "SELL", or while armed for this building amber "+N", the refund now (formatted when
## it changes). Its width is worked out once per match, for the widest "+N".
func _sync_sell(snap: MatchSnapshot, row: int) -> void:
	var sell: Button = _buttons[&"sell"]
	var armed: bool = _arm.target == snap.unit_id[row]
	if not armed:
		_arm.disarm()
	var word: Label = sell.get_node("Face/Word")
	var refund: int = BuildingOrders.refund(snap, row) if armed else -1
	if refund != _refund_shown:
		_refund_shown = refund
		word.text = "+%d" % refund if armed else "SELL"
	_paint(sell, WARN_CAPTION if armed else CAPTION)
	if snap.match_serial != _widest_serial:
		_widest_serial = snap.match_serial
		var digits: int = str(BuildingOrders.widest_refund(snap)).length()
		_wide[&"sell"] = [WARN_CAPTION, "+" + "8".repeat(digits)]  # 8 is the widest digit.
		_fix_width(&"sell")


## Gives the button's word the caption variation `variation` and its glyph the word's colour, so
## the look comes from the theme alone.
func _paint(button: Button, variation: StringName) -> void:
	var word: Label = button.get_node("Face/Word")
	if word.theme_type_variation != variation:
		word.theme_type_variation = variation
	(button.get_node("Face/Glyph") as TextureRect).modulate = word.get_theme_color(&"font_color")


## The button is as wide as its widest word needs (`_wide`: the caption it is set in and the word),
## never under the order least, so a changing word never shifts it or its neighbours.
func _fix_width(id: StringName) -> void:
	var button: Button = _buttons[id]
	var width: float = UiScale.dp(ORDER_DP.x)
	var wide: Array = _wide.get(id, [])
	if not wide.is_empty():
		var word: Label = button.get_node("Face/Word")
		var font: Font = word.get_theme_font(&"font", wide[0])
		var px: int = word.get_theme_font_size(&"font_size", wide[0])
		var text_px: float = font.get_string_size(wide[1], HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
		width = maxf(width, ceilf(text_px) + 2.0 * UiScale.dp(SELL_PAD_DP))
	button.custom_minimum_size.x = width


## Shows the chips that fit in the bar's room (while placement or the strike aim run: in the width
## the bar had as the mode began), one per type while they do, then a "+N" chip for the types left
## out (the old `SelectionPanel`'s rule: "+N" replaces the last chip that does not fit, and where
## not even one chip and "+N" fit, "+N" counts all the types). Deselect and the orders come first,
## so Stop never scrolls out; the chips take what is left. One type always shows its chip. The room
## is what the bar may be at the most (`HudCorners.place` with a content that asks for more than any
## screen has), less Deselect, the orders and the gaps, so the fit never depends on the width it
## gave.
func _fit_chips() -> void:
	var shown: int = _types
	if _types > 1:  # One type always shows its chip.
		var gap: float = roundf(UiScale.dp(HudCorners.GAP_DP))
		var rects: Dictionary[StringName, Rect2] = _rects(true)
		var room: float = rects[HudCorners.BAR].size.x if rects.has(HudCorners.BAR) else INF
		if _frozen:
			room = minf(room, _held_px)  # The bar never grows under the thumb.
		room -= _clear.get_combined_minimum_size().x + _orders.get_combined_minimum_size().x
		# Even the first chip may give way (more than one type), so "+N" alone counts the types
		# and Stop never scrolls out; one type always shows its chip.
		for count: int in range(_types, -1, -1):
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
		(placement != null and placement.active)
		or (strike_aim != null and strike_aim.active)
		or (carry_aim != null and carry_aim.is_active())
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
