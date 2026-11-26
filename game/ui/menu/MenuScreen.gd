class_name MenuScreen
extends Control
## One screen of the menu stack (ADR 0043 section 3): an opaque backdrop, the safe area, one column
## the width of the short side of the safe rect inside a scroll (a window too short for it
## scrolls), and the foot `AdBannerSlot`. Subclasses add their rows to `column` in `_ready` after
## `super()`; the buttons they add through `add_button` are at least 48 dp. The look is the theme's
## (the stack carries `theme.tres`, `HudTheme` scales it to dp). A touch goes no further.
## The frame is the safe rect exactly: the slot's bottom edge is the safe rect's bottom (the real
## banner is drawn there), and the gap round the column is inside the scroll.

const GAP_DP: float = 12.0
const BUTTON_DP: Vector2 = Vector2(0.0, 48.0)

## The opaque colour behind the column; the stack gives it (from the scene).
var backdrop_color: Color
var column: VBoxContainer
var scroll: ScrollContainer
var slot: AdBannerSlot

var _frame: MarginContainer
var _gap: MarginContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop: ColorRect = ColorRect.new()
	backdrop.name = &"Backdrop"
	backdrop.color = backdrop_color
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame = MarginContainer.new()
	_frame.name = &"Frame"
	add_child(_frame)
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	_frame.add_child(rows)
	scroll = ScrollContainer.new()
	scroll.name = &"Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(scroll)
	_gap = MarginContainer.new()
	_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_gap)
	var centre: CenterContainer = CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gap.add_child(centre)
	column = VBoxContainer.new()
	column.name = &"Column"
	centre.add_child(column)
	slot = AdBannerSlot.new()
	slot.name = &"AdBannerSlot"
	rows.add_child(slot)  # Last: nothing is below it.
	get_viewport().size_changed.connect(_apply)
	_apply()


## The widest the column can be: the safe width inside the gaps, less the scroll bar's width.
func column_room_px() -> float:
	var inside: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), GAP_DP)
	return maxf(inside.size.x - scroll.get_v_scroll_bar().get_combined_minimum_size().x, 0.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		_apply()  # A screen back from under another one lays itself out for the screen it is on.


## Virtual. Back (the Android button, ADR 0043 section 4) asks the screen first: true means the
## screen used it (it closed a sub-state), false lets the stack pop.
func on_back() -> bool:
	return false


## A MenuItem (P662) of at least 48 dp calling `action`; `text` is upper case (no case property).
func add_button(text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.theme_type_variation = &"MenuItem"
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var floor_dp: DpMinSize = DpMinSize.new()
	floor_dp.min_dp = BUTTON_DP
	button.add_child(floor_dp)
	button.pressed.connect(action)
	column.add_child(button)
	return button


## The margins follow `SafeAreaMargin`'s rule (each axis takes the larger inset of its two sides,
## recomputed on a resize; the gap round the column is inside the scroll, so its own margin is 0).
## One exception: the bottom is the safe rect's own bottom, so the slot's bottom edge lies on it
## (the real banner is drawn there, ADR 0043 section 8). The column is as wide as the short side of
## the safe rect inside the gaps, so a phone held either way gets one column. The column gives the
## vertical scroll bar's width back, so a long column that scrolls stays inside the safe rect in
## portrait too (a short one that needs no bar is a few px narrower).
func _apply() -> void:
	if _frame == null or not is_inside_tree():
		return
	var full: Rect2 = get_viewport().get_visible_rect()
	var inset: Vector2i = SafeAreaMargin.inset_px(full, 0.0)
	var safe: Rect2 = UiScale.safe_rect_base().intersection(full)
	_frame.add_theme_constant_override("margin_left", inset.x)
	_frame.add_theme_constant_override("margin_right", inset.x)
	_frame.add_theme_constant_override("margin_top", inset.y)
	_frame.add_theme_constant_override("margin_bottom", ceili(maxf(full.end.y - safe.end.y, 0.0)))
	var gap: int = roundi(UiScale.dp(GAP_DP))
	for side: String in ["left", "top", "right", "bottom"]:
		_gap.add_theme_constant_override("margin_" + side, gap)
	column.add_theme_constant_override("separation", gap)
	var inside: Rect2 = SafeAreaMargin.rect_inside(full, GAP_DP)
	var bar_px: float = scroll.get_v_scroll_bar().get_combined_minimum_size().x
	column.custom_minimum_size.x = maxf(minf(inside.size.x, inside.size.y) - bar_px, 0.0)
