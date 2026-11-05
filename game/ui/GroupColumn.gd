class_name GroupColumn
extends Control
## The group column at the left edge (ADR 0025 sections 2 and 9, plan P122b; it replaces the old
## army bar): "All army" on top, then each saved group with its number and count, then "+" while
## units are selected and a group is free. An empty group is not shown. It reports presses and
## shows what `show_groups` is given; PlayerController decides what a press does: a tap on a group
## asks to recall it, a hold of `settings.group_assign_ms` asks to overwrite it with the selection,
## "+" asks to save the selection in the lowest free group. Groups are view and input state: no
## Command, nothing in the sim.
## The buttons stand where `HudCorners.place` puts the group keys (56 dp each, as many to a
## column as the room holds, more columns to the right), taken on a change of the groups, the
## unfolds and every resize. The node's own rect is the buttons' bounding box (so `GhostControls`
## keeps clear of it) and it is hidden while the portrait sheet leaves no room for it. Texts are
## written when a count changes, never per frame. A number and a count are Labels in a face that
## lets every touch through, so a button's minimum height is its dp size whatever the text (ADR 0025
## section 2: 56 dp plates). A column the layout cannot hold whole scrolls: a finger that moves
## beyond `tap_slop_dp` on an item scrolls them and the press is neither a tap nor a hold.

signal all_army_pressed
signal group_tapped(slot: int)
signal group_assign_requested(slot: int)
signal save_requested  ## "+".
signal laid_out  ## The column took another rect (a change of its items, an unfold, a resize).

const ICON_ART: String = "res://assets/art/svg/icons/glyph_%s.svg"
const ICON_DP: float = 24.0

@export var settings: InputSettings
@export var feed: HudStateFeed
@export var safe_area: SafeAreaMargin
@export var strike_aim: StrikeAim
## BUILD and its Ready chip: upright the column leaves them their width (columns).
@export var build_button: BuildButton  ## Its Ready chip takes room beside BUILD upright.

var _all: Button = Button.new()
var _groups: Array[HoldButton] = []  ## Group `slot` is at `slot - 1`.
var _add: Button = Button.new()
var _icon: TextureRect = TextureRect.new()  ## All army's glyph.
var _items: Array[Button] = [_all]  ## What shows now, top to bottom.
var _counts: PackedInt32Array = PackedInt32Array([0, 0, 0])  ## Per slot, the last counts shown.
var _can_save: bool = false
## Scrolls only while the layout limits the column.
var _scroll: ScrollContainer = ScrollContainer.new()
var _content: Control = Control.new()  ## The buttons' parent.
var _numbers: Array[Label] = []  ## Group `slot`'s number, at `slot - 1`.
var _totals: Array[Label] = []  ## And its count.
var _limited: bool = false  ## The layout holds the column to fewer items.
var _offset: Vector2 = Vector2.ZERO  ## What the finger on an item has moved.
var _scrolling: bool = false  ## The finger went beyond the slop: this press scrolls.
var _aim_key: int = -1  ## (owned, active) as last placed: only a change of it places again.
var _last_box: Rect2 = Rect2()
var _last_visible: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # The gaps between buttons belong to the map.
	if settings == null:
		settings = InputSettings.new()  # The script defaults are the ADR table.
	_make(_all, "AllArmy", "", "")
	_stack_icon_over_word(_all)
	_all.pressed.connect(func() -> void: _emit_unless_scrolled(all_army_pressed))
	for slot: int in range(1, SelectionModel.GROUP_COUNT + 1):
		var group: HoldButton = HoldButton.new()
		_make(group, "Group%d" % slot, "", "")
		_face_of_group(group)
		group.hold_ms = settings.group_assign_ms
		group.tapped.connect(func() -> void: _emit_unless_scrolled(group_tapped, slot))
		group.held.connect(func() -> void: _emit_unless_scrolled(group_assign_requested, slot))
		group.visible = false
		_groups.append(group)
	_make(_add, "AddGroup", "", "plus")
	_add.pressed.connect(func() -> void: _emit_unless_scrolled(save_requested))
	_add.visible = false
	_scroll.name = "ColumnScroll"
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.name = "ColumnItems"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_content)
	add_child(_scroll)
	for button: Button in [_all, _add]:
		button.reparent(_content, false)
	for group: HoldButton in _groups:
		group.reparent(_content, false)
	for button: Button in [_all, _add] + _groups:
		button.gui_input.connect(_on_item_input)
	if feed != null:
		feed.state.changed.connect(_on_unfold_changed)
	if strike_aim != null:
		strike_aim.changed.connect(_on_aim_changed)
	if build_button != null:
		build_button.ready_changed.connect(place)
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()


## Shows the groups with units in them (`counts[slot - 1]` units, a group with none is hidden) and
## "+" while `can_save` (units are selected and a group is free).
func show_groups(counts: PackedInt32Array, can_save: bool) -> void:
	var changed: bool = can_save != _can_save
	_can_save = can_save
	for slot: int in range(1, mini(counts.size(), _groups.size()) + 1):
		var count: int = counts[slot - 1]
		if count != _counts[slot - 1]:
			changed = true
			_counts[slot - 1] = count
			_totals[slot - 1].text = str(count)
	if changed:
		_refill()
		place()


## The text of group `slot`'s button, its number over its count ("2\n30"); the number alone for an
## empty group.
func badge_text(slot: int) -> String:
	var count: String = _totals[slot - 1].text
	return "%s\n%s" % [_numbers[slot - 1].text, count] if _counts[slot - 1] > 0 else str(slot)


## How many buttons show: "All army", the saved groups and "+".
func item_count() -> int:
	return _items.size()


## The rect `HudCorners.place` gives the buttons for the screen and the unfolds in force.
func place() -> void:
	if not is_inside_tree():
		return
	var dp: float = UiScale.base_px_per_dp()
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	if feed != null:
		feed.state.fill(shown)
		feed.state.fill_bar(shown)
	shown.groups = _items.size()
	shown.ready = build_button != null and build_button.ready_type >= 0  # The chip beside BUILD.
	if strike_aim != null and strike_aim.owned:  # The aim's check mark and X stand left of it.
		shown.strike = true
		shown.aim = strike_aim.active
	var margin_dp: float = (
		SafeAreaMargin.DEFAULT_MARGIN_DP if safe_area == null else safe_area.margin_dp
	)
	var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), margin_dp)
	var rects: Dictionary[StringName, Rect2] = HudCorners.place(
		safe, HudLayout.is_portrait(), dp, false, shown
	)
	visible = rects.has(HudCorners.group_key(0))  # The portrait sheet may leave no room.
	if not visible:
		_report(false, Rect2())
		return
	var held: int = 0  # The items that have a place; the rest of a limited column scroll.
	while held < _items.size() and rects.has(HudCorners.group_key(held)):
		held += 1
	var box: Rect2 = rects[HudCorners.group_key(0)]
	for index: int in held:
		box = box.merge(rects[HudCorners.group_key(index)])
	position = box.position
	size = box.size
	_scroll.size = box.size
	var limited: bool = held < _items.size()
	_limited = limited
	var step: float = rects[HudCorners.group_key(0)].size.y
	step += HudCorners.GAP_DP * dp
	if limited:
		_content.custom_minimum_size = Vector2(
			box.size.x, step * _items.size() - HudCorners.GAP_DP * dp
		)
		_content.size = _content.custom_minimum_size
	else:
		_content.custom_minimum_size = Vector2.ZERO
		_content.size = box.size
	var mode: ScrollContainer.ScrollMode = (
		ScrollContainer.SCROLL_MODE_SHOW_NEVER if limited else ScrollContainer.SCROLL_MODE_DISABLED
	)
	_scroll.vertical_scroll_mode = mode
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS if limited else Control.MOUSE_FILTER_IGNORE
	if not limited:
		_scroll.scroll_vertical = 0
	for index: int in _items.size():
		var at: Vector2 = Vector2(0.0, index * step)
		if not limited:
			at = rects[HudCorners.group_key(index)].position - box.position
		_items[index].position = at
		_items[index].size = rects[HudCorners.group_key(0)].size
	_report(true, box)


## Tells the others only when the column took another rect (or showed or hid), not on every call.
func _report(now_visible: bool, box: Rect2) -> void:
	if now_visible == _last_visible and box == _last_box:
		return
	_last_visible = now_visible
	_last_box = box
	laid_out.emit()


## The strike building was gained or lost, or the aim began or ended: the only changes that move the
## column. (`StrikeAim.changed` also fires every tick of the charge countdown.)
func _on_aim_changed() -> void:
	var key: int = (2 if strike_aim.owned else 0) + (1 if strike_aim.active else 0)
	if key != _aim_key:
		_aim_key = key
		place()


## A finger on an item: beyond the slop it scrolls the limited column and the press is spent.
func _on_item_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if touch != null and touch.pressed:
		_offset = Vector2.ZERO
		_scrolling = false
	elif drag != null and _limited:
		if _scrolling:
			_scroll.scroll_vertical -= roundi(drag.relative.y)
		else:
			_offset += drag.relative
			if _offset.length() > UiScale.dp(settings.tap_slop_dp):
				_scrolling = true
				_scroll.scroll_vertical -= roundi(_offset.y)


func _emit_unless_scrolled(which: Signal, slot: int = 0) -> void:
	if _scrolling:
		return
	if slot > 0:
		which.emit(slot)
	else:
		which.emit()


## The face of a group button: its number over its count, in Labels that take no touch.
func _face_of_group(button: Button) -> void:
	var face: VBoxContainer = VBoxContainer.new()
	face.name = "Face"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.alignment = BoxContainer.ALIGNMENT_CENTER
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var number: Label = Label.new()
	number.name = "Number"
	number.text = str(_numbers.size() + 1)
	var total: Label = Label.new()
	total.name = "Count"
	total.theme_type_variation = &"NumberLabel"
	for label: Label in [number, total]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.add_child(label)
	_numbers.append(number)
	_totals.append(total)
	button.add_child(face)


## The button's face: the glyph over the word "ALL", sized so that both fit the 56 dp plate (a
## button's own icon and text would ask for more).
func _stack_icon_over_word(button: Button) -> void:
	var face: VBoxContainer = VBoxContainer.new()
	face.name = "Face"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.alignment = BoxContainer.ALIGNMENT_CENTER
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.name = "Icon"
	_icon.texture = load(ICON_ART % "all_army")
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(_icon)
	var word: Label = Label.new()
	word.name = "Word"
	word.text = "ALL"
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(word)
	button.add_child(face)


func _make(button: Button, node_name: String, label: String, glyph: String) -> void:
	button.name = node_name
	button.text = label
	button.focus_mode = Control.FOCUS_NONE  # No focus ring left behind after a tap.
	if glyph != "":
		button.icon = load(ICON_ART % glyph)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = (
			VERTICAL_ALIGNMENT_TOP if label != "" else VERTICAL_ALIGNMENT_CENTER
		)
	add_child(button)


## The buttons that show, in the column's order.
func _refill() -> void:
	_items.clear()
	_items.append(_all)
	for slot: int in _groups.size():
		_groups[slot].visible = _counts[slot] > 0
		if _counts[slot] > 0:
			_items.append(_groups[slot])
	_add.visible = _can_save
	if _can_save:
		_items.append(_add)


func _on_unfold_changed(_previous: HudState.Unfold) -> void:
	place()


## Sizes are dp, so they follow a resize like the rects do.
func _apply_dp() -> void:
	_icon.custom_minimum_size = UiScale.dp_vec(ICON_DP, ICON_DP)
	_add.add_theme_constant_override("icon_max_width", roundi(UiScale.dp(ICON_DP)))
	place()
