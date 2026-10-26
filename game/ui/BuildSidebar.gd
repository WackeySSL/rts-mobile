class_name BuildSidebar
extends PanelContainer
## The build sidebar, part 1 (ADR 0019 section 1, plan P85): the zone at the end of the long axis
## (ADR 0015 section 5) with the credits and the power bar on one line, the three tabs and, below,
## the slot `Items` that part 2 (P85b) fills with the item tiles. It sends nothing to the sim: a tab
## is local state and the part that queues items will send its Commands through
## `PlayerController.command_sink`. It reads the published snapshot only, the local player's
## credits, `power_made` and `power_used`, and never keeps one.
## Landscape: the right zone, 20% of the width and at least 200 dp, the full height of the safe
## area's inner rect. Portrait: the bottom band, the full inner width, `HudLayout.band_dp` high.
## The band's height goes to `HudLayout.bottom_zone_dp`, the one place the ArmyBar reads, from
## `_ready` and on every resize: this node is the first of the HUD's siblings in the scene, so its
## `size_changed` handler runs before the ArmyBar's and the bar finds the new height.
## Tabs: Structures, Infantry and Vehicles, each an icon (`tab_<name>`, grey at rest and white when
## open, from the theme) and in landscape also its name where the three fit the zone with it. The
## open tab is the lighter plate with the thick bar at its foot (theme `SidebarTab`).
## Power: the bar is the share of the power made that is in use. On low power (`power_used` above
## `power_made`) it is full and amber and the glyph is the warning triangle: a shape and a colour.
## Its numbers are centred in the bar, white with a dark edge across the green fill and the dark
## track, and dark on the amber (`PowerNumber`, `PowerNumberLow`).
## The credits keep the width of `CREDITS_DIGITS` digits, so the bar does not move when they gain or
## lose a digit.
## The look is the inherited theme's (`game/ui/theme.tres`: `BuildSidebar`, `SidebarTab`,
## `PowerBar`, `PowerBarLow`, `PowerNumber`, `PowerNumberLow`, `NumberLabel`), the sizes are dp.

## Emitted when another tab opens, by a tap or by `select_tab`.
signal tab_selected(tab: int)

const ICON_ART: String = "res://assets/art/svg/icons/%s.svg"
const THEME_TYPE: StringName = &"BuildSidebar"
const TAB_VARIATION: StringName = &"SidebarTab"
const BAR_VARIATION: StringName = &"PowerBar"
const BAR_LOW_VARIATION: StringName = &"PowerBarLow"
const NUMBER_VARIATION: StringName = &"NumberLabel"
const BAR_NUMBER_VARIATION: StringName = &"PowerNumber"
const BAR_NUMBER_LOW_VARIATION: StringName = &"PowerNumberLow"
## The tab names by `World.Tab`; the icon of a tab is `tab_<name in lower case>`.
const TAB_NAMES: PackedStringArray = ["Structures", "Infantry", "Vehicles"]
const STATUS_DP: float = 32.0  ## The credits and power line.
const GLYPH_DP: float = 24.0
## The bar's least size; it takes the rest of the line. It is taller than a line of its numbers
## (18 dp text is about 25 dp), which are centred in it.
const BAR_DP: Vector2 = Vector2(24.0, 28.0)
const TAB_DP: float = 48.0
const TAB_ICON_DP: float = 32.0
const ITEMS_DP: float = 64.0  ## The height of the slot for one row of item tiles.
const GAP_DP: float = 8.0
const TEXT_PAD_DP: float = 4.0  ## Each side of the numbers in the bar.
const TEXT_EDGE_DP: float = 2.0  ## The dark edge of the numbers on the green bar.
## The credits' slot: 99 999. The rules set no ceiling (a snapshot holds an int32); a bigger bank
## widens the line by a digit once.
const CREDITS_DIGITS: int = 5

@export var runner: MatchRunner

## The open tab, a `World.Tab`.
var tab: int = World.Tab.STRUCTURES

var _stack: VBoxContainer = VBoxContainer.new()
var _status: HBoxContainer = HBoxContainer.new()
var _credits_glyph: TextureRect
var _credits: Label = Label.new()
var _power_glyph: TextureRect
var _bar: ProgressBar = ProgressBar.new()
var _bar_text: Label = Label.new()
var _tab_row: HBoxContainer = HBoxContainer.new()
var _tabs: Array[Button] = []
var _items: Control = Control.new()
var _low: bool = false
var _shown: Vector3i = Vector3i(-1, -1, -1)  ## Credits, power made and power used on screen.
var _seen: Vector2i = Vector2i(-1, -1)  ## Serial and tick of the snapshot last read.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP  # A touch on the sidebar never reaches the map.
	theme_type_variation = THEME_TYPE
	_stack.name = "Stack"
	add_child(_stack)
	_build_status()
	_build_tabs()
	_items.name = "Items"
	_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_min_dp(_items, Vector2(0.0, ITEMS_DP))
	_stack.add_child(_items)
	select_tab(tab)
	_tint()
	_apply_dp()  # Sets the zone before the ArmyBar's _ready lifts the bar.
	get_viewport().size_changed.connect(_apply_dp)  # After the DpMinSize nodes' own handlers.


func _exit_tree() -> void:
	HudLayout.bottom_zone_dp = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _credits_glyph != null and _power_glyph != null:
		_tint()
		_fit_credits()


## The published snapshot is read when it is a new one (a tick, or a new match): a frame has at
## most one publish to see, and the numbers change only a few times a second.
func _process(_delta: float) -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap != null and Vector2i(snap.match_serial, snap.tick) != _seen:
		refresh()


## Shows the local player's credits and power from the published snapshot.
func refresh() -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null or runner.scenario == null:
		return
	_seen = Vector2i(snap.match_serial, snap.tick)
	var player: int = runner.scenario.local_player
	var numbers: Vector3i = Vector3i(
		_entry(snap.credits, player),
		_entry(snap.power_made, player),
		_entry(snap.power_used, player)
	)
	if numbers != _shown:
		_shown = numbers
		_show(numbers.x, numbers.y, numbers.z)


## Opens tab `index` (a `World.Tab`; another value is ignored). A building selection will call it.
func select_tab(index: int) -> void:
	if index < 0 or index >= _tabs.size():
		return
	for at: int in _tabs.size():
		_tabs[at].set_pressed_no_signal(at == index)  # A tap on the open tab keeps it open.
	if index != tab:
		tab = index
		tab_selected.emit(index)


static func _entry(values: PackedInt32Array, player: int) -> int:
	return values[player] if player >= 0 and player < values.size() else 0


static func _min_dp(control: Control, size_dp: Vector2) -> void:
	var min_size: DpMinSize = DpMinSize.new()
	min_size.min_dp = size_dp
	control.add_child(min_size)


func _glyph(node_name: String, icon: String) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.name = node_name
	rect.texture = load(ICON_ART % icon)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_min_dp(rect, Vector2(GLYPH_DP, GLYPH_DP))
	return rect


func _build_status() -> void:
	_status.name = "Status"
	_min_dp(_status, Vector2(0.0, STATUS_DP))
	_stack.add_child(_status)
	_credits_glyph = _glyph("CreditsGlyph", "glyph_credits")
	_status.add_child(_credits_glyph)
	_credits.name = "Credits"
	_credits.theme_type_variation = NUMBER_VARIATION
	_credits.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_credits.text = "0"
	_status.add_child(_credits)
	_power_glyph = _glyph("PowerGlyph", "glyph_power")
	_status.add_child(_power_glyph)
	_bar.name = "PowerBar"
	_bar.theme_type_variation = BAR_VARIATION
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.max_value = 1.0
	_bar.value = 0.0
	_min_dp(_bar, BAR_DP)
	_status.add_child(_bar)
	_bar_text.name = "PowerText"
	_bar_text.theme_type_variation = BAR_NUMBER_VARIATION
	# The full width and the middle of the bar. A line of text can be taller than the bar at some
	# size: it then grows up and down alike, never down alone.
	_bar_text.set_anchors_preset(Control.PRESET_HCENTER_WIDE)
	_bar_text.grow_vertical = Control.GROW_DIRECTION_BOTH
	_bar_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar_text.clip_text = true  # It adds nothing to the line's width: it is shown where it fits.
	_bar_text.text = "0/0"
	_bar.add_child(_bar_text)
	_bar.resized.connect(_fit_bar_text)


func _build_tabs() -> void:
	_tab_row.name = "Tabs"
	_stack.add_child(_tab_row)
	for index: int in TAB_NAMES.size():
		var button: Button = Button.new()
		button.name = "Tab%s" % TAB_NAMES[index]
		button.theme_type_variation = TAB_VARIATION
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE  # No focus ring left behind after a tap.
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.icon = load(ICON_ART % ("tab_" + TAB_NAMES[index].to_lower()))
		button.pressed.connect(select_tab.bind(index))
		_min_dp(button, Vector2(TAB_DP, TAB_DP))
		_tab_row.add_child(button)
		_tabs.append(button)


## The numbers of the line. The look changes only when the low state does.
func _show(credits: int, made: int, used: int) -> void:
	var low: bool = used > made
	_credits.text = str(credits)
	_bar.max_value = maxi(made, 1)
	_bar.value = _bar.max_value if low else used
	_bar_text.text = "%d/%d" % [used, made]
	if low != _low:
		_low = low
		_bar.theme_type_variation = BAR_LOW_VARIATION if low else BAR_VARIATION
		_bar_text.theme_type_variation = BAR_NUMBER_LOW_VARIATION if low else BAR_NUMBER_VARIATION
		_power_glyph.texture = load(ICON_ART % ("glyph_low_power" if low else "glyph_power"))
		_tint()
	_fit_bar_text()


## The glyphs' tints come from the theme: credits, power, or the warning on low power.
func _tint() -> void:
	_credits_glyph.modulate = get_theme_color(&"credits", THEME_TYPE)
	_power_glyph.modulate = get_theme_color(&"warning" if _low else &"power", THEME_TYPE)


## The credits' least width is that of the widest `CREDITS_DIGITS` digits at the theme's font and
## size, so the line (and the bar, which takes the rest) keeps still as the credits change length.
func _fit_credits() -> void:
	var font: Font = _credits.get_theme_font(&"font")
	var font_px: int = _credits.get_theme_font_size(&"font_size")
	var widest: float = 0.0
	for digit: String in "0123456789":
		var slot: String = digit.repeat(CREDITS_DIGITS)
		widest = maxf(
			widest, font.get_string_size(slot, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px).x
		)
	_credits.custom_minimum_size = Vector2(ceilf(widest), 0.0)


## The numbers show in the bar where the bar is wider than they are; else the bar speaks alone.
func _fit_bar_text() -> void:
	var font: Font = _bar_text.get_theme_font(&"font")
	var font_px: int = _bar_text.get_theme_font_size(&"font_size")
	var text_px: float = (
		font.get_string_size(_bar_text.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px).x
	)
	_bar_text.visible = text_px + 2.0 * UiScale.dp(TEXT_PAD_DP) <= _bar.size.x


## Sizes are dp, so they follow a resize like DpMinSize does.
func _apply_dp() -> void:
	var gap: int = roundi(UiScale.dp(GAP_DP))
	for row: BoxContainer in [_stack, _tab_row]:
		row.add_theme_constant_override("separation", gap)
	_status.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP / 2.0)))
	for button: Button in _tabs:
		button.add_theme_constant_override("icon_max_width", roundi(UiScale.dp(TAB_ICON_DP)))
	_bar_text.add_theme_constant_override("outline_size", roundi(UiScale.dp(TEXT_EDGE_DP)))
	_place()
	_fit_names(gap)
	_fit_credits()
	_fit_bar_text()


## Puts the sidebar in its zone and, in portrait, hands the band's height to the HUD.
func _place() -> void:
	if HudLayout.is_portrait():
		var safe: SafeAreaMargin = get_parent() as SafeAreaMargin
		var edge_dp: float = 0.0 if safe == null else safe.margin_dp
		var reserved_dp: float = edge_dp + ArmyBar.GAP_DP + ArmyBar.ALL_ARMY_DP.y
		var safe_dp: float = UiScale.safe_rect_base().size.y / UiScale.base_px_per_dp()
		HudLayout.bottom_zone_dp = HudLayout.band_dp(safe_dp, reserved_dp)
		size_flags_horizontal = Control.SIZE_FILL
		size_flags_vertical = Control.SIZE_SHRINK_END
		custom_minimum_size = Vector2(0.0, HudLayout.bottom_zone_px())
	else:
		HudLayout.bottom_zone_dp = 0.0  # The zone is the right fifth, which the SelectionPanel reads.
		size_flags_horizontal = Control.SIZE_SHRINK_END
		size_flags_vertical = Control.SIZE_FILL
		custom_minimum_size = Vector2(
			HudLayout.right_zone_px(get_viewport().get_visible_rect().size.x), 0.0
		)


## The names go with the icons in landscape where all three tabs fit the zone with them; in the
## portrait band the tabs are icons only, each centred in its tab.
func _fit_names(gap: int) -> void:
	var named: bool = not HudLayout.is_portrait()
	if named:
		_set_names(true)
		var room: float = custom_minimum_size.x - get_theme_stylebox(&"panel").get_minimum_size().x
		var need: float = gap * (_tabs.size() - 1)
		for button: Button in _tabs:
			need += button.get_combined_minimum_size().x
		named = need <= room
	_set_names(named)


## Shows the names beside the icons, or the icons alone in the middle of their tabs.
func _set_names(named: bool) -> void:
	for index: int in _tabs.size():
		_tabs[index].text = TAB_NAMES[index] if named else ""
		_tabs[index].icon_alignment = (
			HORIZONTAL_ALIGNMENT_LEFT if named else HORIZONTAL_ALIGNMENT_CENTER
		)
