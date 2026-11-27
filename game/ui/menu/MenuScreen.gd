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
## The stack draws a picture under every screen, so the screen adds no colour of its own.
var see_through: bool = false
var column: VBoxContainer
var scroll: ScrollContainer
var slot: AdBannerSlot
## The fixed footer bar (P672a): outside the scroll, hidden until a screen calls `use_footer`.
var footer: PanelContainer
var back_link: Button
var hint_label: Label

var _frame: MarginContainer
var _gap: MarginContainer
var _footer_on: bool = false
var _back_name: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not see_through:
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
	_build_footer(rows)
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
		_refresh_footer.call_deferred()  # The stack lists a pushed screen only after its _ready.


## Virtual. The name the footer's back link of the screen above shows: "‹ " and this.
func screen_name() -> String:
	return ""


## Shows the footer bar with the back link to the screen below (P672a: the web has no back event)
## and an optional hint at its right. The root screen never calls it.
func use_footer(hint: String = "") -> void:
	_footer_on = true
	hint_label.text = hint
	footer.visible = true
	_refresh_footer()


## The link reads this name instead of the screen below's (a screen that closes an inner view
## first, such as a section of How to play, names the list it returns to). "" goes back to the rule.
func set_back_name(name_text: String) -> void:
	_back_name = name_text
	_refresh_footer()


## Virtual. Back (the Android button, ADR 0043 section 4) asks the screen first: true means the
## screen used it (it closed a sub-state), false lets the stack pop.
func on_back() -> bool:
	return false


func _build_footer(rows: VBoxContainer) -> void:
	footer = PanelContainer.new()
	footer.name = &"Footer"
	footer.theme_type_variation = &"MenuFooter"
	footer.visible = false
	rows.add_child(footer)
	var row: HBoxContainer = HBoxContainer.new()
	footer.add_child(row)
	back_link = Button.new()
	back_link.name = &"BackLink"
	back_link.theme_type_variation = &"MenuFooterLink"
	back_link.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back_link.set_meta(&"ui_cue", &"ui_back")
	var floor_dp: DpMinSize = DpMinSize.new()
	floor_dp.min_dp = Vector2(48.0, 48.0)
	back_link.add_child(floor_dp)
	back_link.pressed.connect(_go_back)
	row.add_child(back_link)
	hint_label = Label.new()
	hint_label.name = &"Hint"
	hint_label.theme_type_variation = &"MenuFooterHint"
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(hint_label)


## The link's words: the override, else the screen below's `screen_name()`, else BACK (the first
## screen of a stack, such as Settings over the pause menu).
func _refresh_footer() -> void:
	if not _footer_on or back_link == null:
		return
	var name_text: String = _back_name
	if name_text.is_empty():
		var stack: MenuStack = get_parent() as MenuStack
		var below: MenuScreen = stack.screen_below(self) if stack != null else null
		name_text = below.screen_name() if below != null else ""
	if name_text.is_empty():
		name_text = tr("BACK")
	back_link.text = "\u2039 " + name_text.to_upper()


## Pressed back link: the stack's `back()`, so `on_back()` rules still hold.
func _go_back() -> void:
	var stack: MenuStack = get_parent() as MenuStack
	if stack != null:
		stack.back()


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
