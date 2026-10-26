class_name ItemTile
extends HoldButton
## One build item of the sidebar (plan P85b, ADR 0019 section 1): the icon of a type on a 64 dp
## plate, its cost at the foot, a badge for the items of the type queued, a fill that rises over the
## icon with the head's progress, and a state shown by a shape and not by colour alone: a padlock
## (LOCKED), stripes (UNAFFORDABLE, FULL; the cost amber for money), a "Ready" banner (READY).
## The cost's plate takes the foot of the tile, and the shapes of a state (the fill, the stripes,
## the padlock, the banner) fill the area above it, so none of them is ever drawn under the plate:
## the fill's share is a share of that area.
## `BuildSidebar` tells it what to show (`show_state`); it tells the sidebar what the finger did:
## `chose` for a tap, `cancelled` for a hold of `hold_ms`, `dragged` for a drag beyond `slop_dp`,
## which scrolls the row and is then neither. The tile is a Button, so a touch on it never reaches
## the map. The look is the theme's (`ItemTile`, `ItemCost`, `ItemCostLow`, `ItemBanner`), in dp.

signal chose  ## A tap: released before `hold_ms`, within `slop_dp`.
signal cancelled  ## A hold of `hold_ms`, within `slop_dp`.
signal dragged(relative: Vector2)  ## The finger moved beyond `slop_dp`: the row follows it.

enum State { AVAILABLE, LOCKED, UNAFFORDABLE, FULL, READY }

const SIZE_DP: float = 64.0
const ICON_INSET_DP: float = 3.0
const LOCK_DP: float = 32.0
const STRIPE_DP: Vector2 = Vector2(14.0, 5.0)  ## The step between stripes and their width.
const VARIATION: StringName = &"ItemTile"
const COST_VARIATION: StringName = &"ItemCost"
const COST_LOW_VARIATION: StringName = &"ItemCostLow"
const BANNER_VARIATION: StringName = &"ItemBanner"
const LOCK_ART: String = "res://assets/art/svg/icons/glyph_lock.svg"
const SHAKE_RAD: float = 0.08
const SHAKE_S: float = 0.05

var type_index: int = -1
var tab: int = -1  ## The `World.Tab` whose queue builds the type.
var state: State = State.AVAILABLE
var queued: int = 0  ## The items of the type in the queue.
var progress: float = 0.0  ## The head's progress when it is of the type (0 to 1).
var slop_dp: float = 12.0  ## `InputSettings.tap_slop_dp`.
var shakes: int = 0  ## How many times the tile has shaken, for the tests.

var _icon: TextureRect = TextureRect.new()
var _column: VBoxContainer = VBoxContainer.new()  ## The area above the cost, and the cost.
var _stage: Control = Control.new()  ## The area above the cost's plate: the state's shapes.
var _fill: ColorRect = ColorRect.new()
var _stripes: Stripes = Stripes.new()
var _lock: TextureRect = TextureRect.new()
var _banner: Label = Label.new()
var _cost: Label = Label.new()
var _badge: Label = Label.new()
var _offset: Vector2 = Vector2.ZERO  ## The finger's move since the press.
var _scrolling: bool = false
var _shake: Tween = null
var _shown: bool = false  ## `show_state` has been called once.


## The diagonal stripes of a tile that cannot take an item now.
class Stripes:
	extends Control
	var color: Color
	var step: float = 24.0
	var width: float = 6.0

	func _draw() -> void:
		var at: float = -size.y
		while at < size.x:
			draw_line(Vector2(at, size.y), Vector2(at + size.y, 0.0), color, width)
			at += step


func _init() -> void:
	super()  # HoldButton wires its press, hold and release here.
	theme_type_variation = VARIATION
	focus_mode = Control.FOCUS_NONE  # No focus ring left behind after a tap.
	clip_contents = true
	tapped.connect(_on_tapped)
	held.connect(_on_held)
	var min_size: DpMinSize = DpMinSize.new()
	min_size.min_dp = Vector2(SIZE_DP, SIZE_DP)
	add_child(min_size)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lock.texture = load(LOCK_ART)
	_lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lock.set_anchors_preset(Control.PRESET_CENTER)
	_lock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lock.grow_vertical = Control.GROW_DIRECTION_BOTH
	var lock_size: DpMinSize = DpMinSize.new()
	lock_size.min_dp = Vector2(LOCK_DP, LOCK_DP)
	_lock.add_child(lock_size)
	_banner.text = "Ready"
	_banner.theme_type_variation = BANNER_VARIATION
	_banner.set_anchors_preset(Control.PRESET_HCENTER_WIDE)
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost.theme_type_variation = COST_VARIATION
	_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.theme_type_variation = COST_VARIATION
	_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stripes.set_anchors_preset(Control.PRESET_FULL_RECT)
	_column.set_anchors_preset(Control.PRESET_FULL_RECT)
	_column.add_theme_constant_override(&"separation", 0)  # The plate sits right under the stage.
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL  # The cost keeps its height, this the rest.
	_add(_icon, "Icon")
	_add(_column, "Column")
	_add(_stage, "Stage", _column)
	_add(_cost, "Cost", _column)
	_add(_fill, "Fill", _stage)
	_add(_stripes, "Stripes", _stage)
	_add(_lock, "Lock", _stage)
	_add(_banner, "Banner", _stage)
	_add(_badge, "Badge")
	show_state(State.AVAILABLE, 0, 0.0)


func _ready() -> void:
	super()
	_look()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_look()


## What the tile is: the type's index and tab, its icon and its cost.
func setup(index: int, queue_tab: int, art: Texture2D, cost: int) -> void:
	type_index = index
	tab = queue_tab
	_icon.texture = art
	_cost.text = str(cost)


## Shows the state, the queued count and the head's progress (a share, 0 to 1).
func show_state(new_state: State, count: int, share: float) -> void:
	if _shown and new_state == state and count == queued and is_equal_approx(share, progress):
		return  # Most tiles do not change from one tick to the next.
	_shown = true
	state = new_state
	queued = count
	progress = share
	var ready: bool = new_state == State.READY
	_tint_icon()
	_lock.visible = new_state == State.LOCKED
	_stripes.visible = new_state == State.UNAFFORDABLE or new_state == State.FULL
	_banner.visible = ready
	_fill.visible = share > 0.0 and not ready
	_fill.anchor_top = 1.0 - share
	_badge.visible = count > 0
	_badge.text = str(count)
	_cost.theme_type_variation = (
		COST_LOW_VARIATION if new_state == State.UNAFFORDABLE else COST_VARIATION
	)


## A short wiggle: a tap on a tile that cannot take an item.
func shake() -> void:
	shakes += 1
	pivot_offset = size / 2.0
	if _shake != null:
		_shake.kill()
	_shake = create_tween()
	for angle: float in [SHAKE_RAD, -SHAKE_RAD, 0.0]:
		_shake.tween_property(self, "rotation", angle, SHAKE_S)


## A move beyond the slop is a scroll (the first hands over all the finger has moved since the
## press), and then the touch is neither a tap nor a hold.
func _gui_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if touch != null and touch.pressed:
		_offset = Vector2.ZERO
		_scrolling = false
	elif drag != null and _scrolling:
		dragged.emit(drag.relative)
	elif drag != null:
		_offset += drag.relative
		if _offset.length() > UiScale.dp(slop_dp):
			_scrolling = true
			dragged.emit(_offset)


func _on_tapped() -> void:
	if not _scrolling:
		chose.emit()


func _on_held() -> void:
	if not _scrolling:
		cancelled.emit()


## A part of the tile that the finger never finds: the tile is what it finds.
func _add(part: Control, part_name: String, parent: Control = self) -> void:
	part.name = part_name
	part.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(part)


## The tints, the fill, the stripes and the inset of the icon, from the theme and the dp scale.
func _look() -> void:
	_tint_icon()
	_fill.color = get_theme_color(&"fill", VARIATION)
	_lock.modulate = get_theme_color(&"lock", VARIATION)
	_stripes.color = get_theme_color(&"stripe", VARIATION)
	_stripes.step = UiScale.dp(STRIPE_DP.x)
	_stripes.width = UiScale.dp(STRIPE_DP.y)
	_stripes.queue_redraw()
	_icon.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, roundi(UiScale.dp(ICON_INSET_DP))
	)


## The icon is dimmed behind the padlock of a locked tile.
func _tint_icon() -> void:
	_icon.modulate = get_theme_color(
		&"icon_locked" if state == State.LOCKED else &"icon", VARIATION
	)
