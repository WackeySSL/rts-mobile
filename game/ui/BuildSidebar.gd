class_name BuildSidebar
extends PanelContainer
## The build sidebar, part 1 (ADR 0019 section 1, plan P85): the zone at the end of the long axis
## (ADR 0015 section 5), the three tabs, and two slots that later rows fill: `Status`, the line
## for the credits and the power bar (P85c), and `Items`, the row for the item tiles (P85b). It
## sends nothing to the sim: a tab is local state, and the part that queues items will send its
## Commands through `PlayerController.command_sink`.
## Landscape: the right zone, 20% of the width and at least 200 dp, the full height of the safe
## area's inner rect. Portrait: the bottom band, the full inner width, `HudLayout.band_dp` high.
## The band's height goes to `HudLayout.bottom_zone_dp`, the one place the ArmyBar reads, from
## `_ready` and on every resize: this node is the first of the HUD's siblings in the scene, so its
## `size_changed` handler runs before the ArmyBar's and the bar finds the new height.
## Tabs: Structures, Infantry and Vehicles, each an icon (`tab_<name>`, grey at rest and white when
## open, from the theme) and in landscape also its name where the three fit the zone with it. The
## open tab is the lighter plate with the thick bar at its foot (theme `SidebarTab`).
## The look is the inherited theme's (`game/ui/theme.tres`: `BuildSidebar`, `SidebarTab`), the
## sizes are dp.

## Emitted when another tab opens, by a tap or by `select_tab`.
signal tab_selected(tab: int)

const ICON_ART: String = "res://assets/art/svg/icons/%s.svg"
const THEME_TYPE: StringName = &"BuildSidebar"
const TAB_VARIATION: StringName = &"SidebarTab"
## The tab names by `World.Tab`; the icon of a tab is `tab_<name in lower case>`.
const TAB_NAMES: PackedStringArray = ["Structures", "Infantry", "Vehicles"]
const STATUS_DP: float = 32.0  ## The height of the line for the credits and the power bar.
const TAB_DP: float = 48.0
const TAB_ICON_DP: float = 32.0
const ITEMS_DP: float = 64.0  ## The height of the slot for one row of item tiles.
const GAP_DP: float = 8.0

## The open tab, a `World.Tab`.
var tab: int = World.Tab.STRUCTURES

var _stack: VBoxContainer = VBoxContainer.new()
var _status: HBoxContainer = HBoxContainer.new()
var _tab_row: HBoxContainer = HBoxContainer.new()
var _tabs: Array[Button] = []
var _items: Control = Control.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP  # A touch on the sidebar never reaches the map.
	theme_type_variation = THEME_TYPE
	_stack.name = "Stack"
	add_child(_stack)
	_status.name = "Status"
	_min_dp(_status, Vector2(0.0, STATUS_DP))
	_stack.add_child(_status)
	_build_tabs()
	_items.name = "Items"
	_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_min_dp(_items, Vector2(0.0, ITEMS_DP))
	_stack.add_child(_items)
	select_tab(tab)
	_apply_dp()  # Sets the zone before the ArmyBar's _ready lifts the bar.
	get_viewport().size_changed.connect(_apply_dp)  # After the DpMinSize nodes' own handlers.


func _exit_tree() -> void:
	HudLayout.bottom_zone_dp = 0.0


## Opens tab `index` (a `World.Tab`; another value is ignored). A building selection will call it.
func select_tab(index: int) -> void:
	if index < 0 or index >= _tabs.size():
		return
	for at: int in _tabs.size():
		_tabs[at].set_pressed_no_signal(at == index)  # A tap on the open tab keeps it open.
	if index != tab:
		tab = index
		tab_selected.emit(index)


static func _min_dp(control: Control, size_dp: Vector2) -> void:
	var min_size: DpMinSize = DpMinSize.new()
	min_size.min_dp = size_dp
	control.add_child(min_size)


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


## Sizes are dp, so they follow a resize like DpMinSize does.
func _apply_dp() -> void:
	var gap: int = roundi(UiScale.dp(GAP_DP))
	for row: BoxContainer in [_stack, _tab_row]:
		row.add_theme_constant_override("separation", gap)
	for button: Button in _tabs:
		button.add_theme_constant_override("icon_max_width", roundi(UiScale.dp(TAB_ICON_DP)))
	_place()
	_fit_names(gap)


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
