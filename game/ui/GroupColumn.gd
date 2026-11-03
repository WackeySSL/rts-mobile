class_name GroupColumn
extends Control
## The group column at the left edge (ADR 0025 sections 2 and 9, plan P122b; it replaces the
## ArmyBar): "All army" on top, then each saved group with its number and count, then "+" while
## units are selected and a group is free. An empty group is not shown. It reports presses and
## shows what `show_groups` is given; PlayerController decides what a press does: a tap on a group
## asks to recall it, a hold of `settings.group_assign_ms` asks to overwrite it with the selection,
## "+" asks to save the selection in the lowest free group. Groups are view and input state: no
## Command, nothing in the sim.
## The buttons stand where `HudCorners.place` puts the group keys (56 dp each, as many to a column
## as
## the room holds, more columns to the right), taken on a change of the groups, the unfolds and
## every resize. The node's own rect is the buttons' bounding box (so `GhostControls` keeps clear of
## it) and it is hidden while the portrait sheet covers the place. Texts are written when a count
## changes, never per frame.

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
## Upright during its aim the column holds three items and scrolls.
@export var strike_aim: StrikeAim
## The Dev over Surrender stack (until P124): the column stands under it.
@export var top_left: Control

var _all: Button = Button.new()
var _groups: Array[HoldButton] = []  ## Group `slot` is at `slot - 1`.
var _add: Button = Button.new()
var _icon: TextureRect = TextureRect.new()  ## All army's glyph.
var _items: Array[Button] = [_all]  ## What shows now, top to bottom.
var _counts: PackedInt32Array = PackedInt32Array([0, 0, 0])  ## Per slot, the last counts shown.
var _can_save: bool = false
## Scrolls only while the aim limits the column.
var _scroll: ScrollContainer = ScrollContainer.new()
var _content: Control = Control.new()  ## The buttons' parent.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # The gaps between buttons belong to the map.
	if settings == null:
		settings = InputSettings.new()  # The script defaults are the ADR table.
	_make(_all, "AllArmy", "", "")
	_stack_icon_over_word(_all)
	_all.pressed.connect(func() -> void: all_army_pressed.emit())
	for slot: int in range(1, SelectionModel.GROUP_COUNT + 1):
		var group: HoldButton = HoldButton.new()
		_make(group, "Group%d" % slot, str(slot), "")
		group.hold_ms = settings.group_assign_ms
		group.tapped.connect(func() -> void: group_tapped.emit(slot))
		group.held.connect(func() -> void: group_assign_requested.emit(slot))
		group.visible = false
		_groups.append(group)
	_make(_add, "AddGroup", "", "plus")
	_add.pressed.connect(func() -> void: save_requested.emit())
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
	if feed != null:
		feed.state.changed.connect(_on_unfold_changed)
	if strike_aim != null:
		strike_aim.changed.connect(place)
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
			_groups[slot - 1].text = "%d\n%d" % [slot, count] if count > 0 else str(slot)
	if changed:
		_refill()
		place()


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
	shown.groups = _items.size()
	if strike_aim != null and strike_aim.owned:  # The aim's check mark and X stand left of it.
		shown.strike = true
		shown.aim = strike_aim.active
	if top_left != null and top_left.visible:
		shown.left_taken = HudLayout.first_visible_width(top_left) / dp
		shown.left_height = top_left.get_combined_minimum_size().y / dp
	var margin_dp: float = (
		SafeAreaMargin.DEFAULT_MARGIN_DP if safe_area == null else safe_area.margin_dp
	)
	var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), margin_dp)
	var rects: Dictionary[StringName, Rect2] = HudCorners.place(
		safe, HudLayout.is_portrait(), dp, false, shown
	)
	visible = rects.has(HudCorners.group_key(0))  # The portrait sheet covers the place.
	if not visible:
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
	laid_out.emit()


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
