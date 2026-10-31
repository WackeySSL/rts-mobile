class_name BuildSidebar
extends PanelContainer
## The build menu (ADR 0019 section 1, ADR 0023 section 12, plans P85, P85c, P85b and P85d): the
## credits and the power bar on one line (`Status`), the three tabs and, below, the slot `Items`
## with the open tab's item tiles. It sends nothing to the sim but Commands through
## `PlayerController.command_sink`: a tap on an available tile is one QUEUE, a hold on a tile with
## items queued is one CANCEL of the last of them. It reads the published snapshot only (the local
## player's credits, power, queue and rows, and the type tables) and never keeps one.
## Landscape (P85d): the floating build panel at the bottom right, `HudLayout.panel_px` wide and as
## high as its tabs and one row of cards; the status line moves into `pill`, the floating pill at
## the top left after `top_left`, and `minimap_slot`, the floating panel at the top right that P88
## fills, shows. Portrait: the bottom band, the full inner width, `HudLayout.band_dp` high, with the
## status line as its first line, and the pill and the slot hidden. A turn only moves things: the
## state is what `_place` makes of the orientation.
## The band's height goes to `HudLayout.bottom_zone_dp`, the one place the ArmyBar reads, from
## `_ready` and on every resize: this node is the first of the HUD's siblings in the scene, so its
## `size_changed` handler runs before the ArmyBar's and the bar finds the new height.
## Tabs: Structures, Infantry and Vehicles, each an icon alone (`tab_<name>`, grey at rest and white
## when open, from the theme). The open tab is the lighter plate with the thick bar at its foot
## (theme `SidebarTab`).
## Power: the bar is the share of the power made that is in use. On low power (`power_used` above
## `power_made`) it is full and amber and the glyph is the warning triangle: a shape and a colour.
## Its numbers are centred in the bar, white with a dark edge across the green fill and the dark
## track, and dark on the amber (`PowerNumber`, `PowerNumberLow`).
## The credits keep the width of `CREDITS_DIGITS` digits, so the bar does not move when they gain or
## lose a digit.
## Items: one `ItemTile` per buildable type (icon `item_<type id>`), made per match from the
## snapshot's type tables, those of the open tab and of the local player's faction shown, in one row
## that scrolls sideways (the cards of the floating panel carry their names, the band's tiles do
## not). The faction is that of the player's own rows (`type_faction`, the producer-faction rule of
## `Production.apply_queue`): a type of another faction is never shown, one with none is shown to
## all. A tile is READY (a finished structure at the head of its queue: a tap enters placement mode,
## plan P86, and the check mark and the X take the card row's place until it ends), LOCKED (the
## type's requirement or the tab's producer is not among the player's rows), UNAFFORDABLE, FULL (no
## room in the queue) or AVAILABLE, in that order. A tap on one that cannot take an item shakes it.
## Selecting an own production building opens its tab: `set_selected` is the hook, wired to
## `PlayerController.selection_changed` when `controller` is set.
## The look is the inherited theme's (`game/ui/theme.tres`: `BuildSidebar`, `SidebarTab`,
## `PowerBar`, `PowerBarLow`, `PowerNumber`, `PowerNumberLow`, `NumberLabel` and the `ItemTile`
## family), the sizes are dp.

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
## The slot of the named cards is their height and this, because a box container sorts in whole px
## and would otherwise leave a card a fraction of a px taller than the slot that holds it.
const ROW_SLACK_DP: float = 2.0
const GAP_DP: float = 8.0
const TEXT_PAD_DP: float = 4.0  ## Each side of the numbers in the bar.
const TEXT_EDGE_DP: float = 2.0  ## The dark edge of the numbers on the green bar.
## The credits' slot: 99 999. The rules set no ceiling (a snapshot holds an int32); a bigger bank
## widens the line by a digit once.
const CREDITS_DIGITS: int = 5

@export var runner: MatchRunner
@export var controller: PlayerController  ## The Commands' sink, the haptic, the selection.
@export var pill: Control  ## The landscape home of `Status` (a panel in a band at the top left).
@export var minimap_slot: Control  ## The landscape panel at the top right, empty until P88.
@export var top_left: Control  ## The pill starts after it (the Dev button).
@export var placement: PlacementController  ## A tap on a READY tile begins it. None: no placement.

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
var _items: ScrollContainer = ScrollContainer.new()
var _items_fit: DpMinSize = DpMinSize.new()  ## The least height of `_items`, by the tile in use.
var _grid: GridContainer = GridContainer.new()
var _actions: PlacementControls = null  ## Check mark and X, the row's stand-in; with `placement`.
var _tiles: Array[ItemTile] = []
var _low: bool = false
var _faction: int = -1  ## The local player's faction (`type_faction`); -1 until a row shows it.
var _shown: Vector3i = Vector3i(-1, -1, -1)  ## Credits, power made and power used on screen.
var _seen: Vector2i = Vector2i(-1, -1)  ## Serial and tick of the snapshot last read.
var _built: Vector2i = Vector2i(-1, -1)  ## Match serial and type count the tiles are made for.
var _owned: PackedInt32Array = PackedInt32Array()  ## Scratch of a refresh: own rows per type.
var _producers: PackedInt32Array = PackedInt32Array()  ## And own producers per tab.


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
	_items.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER  # One row, sideways.
	_items.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_items_fit.min_dp = Vector2(0.0, ITEMS_DP)
	_items.add_child(_items_fit)
	_items.add_child(_grid)
	_stack.add_child(_items)
	if placement != null:
		_actions = PlacementControls.new()
		_actions.name = "Placement"
		_actions.placement = placement
		_stack.add_child(_actions)
		placement.changed.connect(_on_placement_changed)
	select_tab(tab)
	_tint()
	if pill != null:
		_min_dp(pill, Vector2(HudLayout.PILL_DP, HudLayout.PILL_HEIGHT_DP))
	if minimap_slot != null:
		_min_dp(minimap_slot, HudLayout.SLOT_DP)
	_apply_dp()  # Sets the zone before the ArmyBar's _ready lifts the bar.
	get_viewport().size_changed.connect(_apply_dp)  # After the DpMinSize nodes' own handlers.
	if controller != null:
		controller.selection_changed.connect(set_selected)


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
	_refresh_items(snap, player)


## Opens tab `index` (a `World.Tab`; another value is ignored).
func select_tab(index: int) -> void:
	if index < 0 or index >= _tabs.size():
		return
	for at: int in _tabs.size():
		_tabs[at].set_pressed_no_signal(at == index)  # A tap on the open tab keeps it open.
	if index != tab:
		tab = index
		_items.scroll_horizontal = 0
		_items.scroll_vertical = 0
		_show_tab()
		tab_selected.emit(index)


## The selection hook (ADR 0019 section 1): a lone own building that produces a tab opens it. The
## building selection (plan P84d) needs only to put the building's id in the selection; units and
## anything else leave the open tab as it is.
func set_selected(ids: PackedInt32Array) -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null or ids.size() != 1:
		return
	var row: int = snap.index_of(ids[0])
	if row >= 0 and snap.owner[row] == _local_player():
		select_tab(snap.type_produces[snap.type_index[row]])


static func _entry(values: PackedInt32Array, player: int) -> int:
	return values[player] if player >= 0 and player < values.size() else 0


## The slots of a queue. The snapshot has no `queue_slots` yet (a P81 follow-up: one line in
## `COPIED_SCALARS`), but `queue_type` holds them per player and tab, `credits` has one entry per
## player, so the quotient is the slots; 0 for a snapshot with no players.
@warning_ignore("integer_division")
static func _queue_slots(snap: MatchSnapshot) -> int:
	var queues: int = snap.credits.size() * World.TABS
	return snap.queue_type.size() / queues if queues > 0 else 0


func _local_player() -> int:
	return -1 if runner == null or runner.scenario == null else runner.scenario.local_player


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
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER  # The icon alone, in the tab's middle.
		button.pressed.connect(select_tab.bind(index))
		_min_dp(button, Vector2(TAB_DP, TAB_DP))
		_tab_row.add_child(button)
		_tabs.append(button)


## Makes the tiles again when the match or the type tables changed, then shows each one's state.
func _refresh_items(snap: MatchSnapshot, player: int) -> void:
	var key: Vector2i = Vector2i(snap.match_serial, snap.type_tab.size())
	if key != _built:
		_built = key
		_build_tiles(snap)
	if _tiles.is_empty():
		return
	_owned.resize(snap.type_tab.size())
	_owned.fill(0)
	var faction: int = -1
	for row: int in snap.unit_id.size():
		if snap.owner[row] == player:
			_owned[snap.type_index[row]] += 1
			if faction < 0:
				faction = snap.type_faction[snap.type_index[row]]
	if faction >= 0 and faction != _faction:  # Kept when the last row of it is gone.
		_faction = faction
		_show_tab()
	_producers.resize(World.TABS)
	_producers.fill(0)
	for type: int in _owned.size():
		if _owned[type] > 0 and snap.type_produces[type] >= 0:
			_producers[snap.type_produces[type]] += 1
	var slots: int = _queue_slots(snap)
	for tile: ItemTile in _tiles:
		_show_tile(tile, snap, player, slots)


## One tile's state, queued count and progress from the player's queue of its tab.
func _show_tile(tile: ItemTile, snap: MatchSnapshot, player: int, slots: int) -> void:
	var type: int = tile.type_index
	var queue: int = player * World.TABS + tile.tab
	var count: int = _entry(snap.queue_count, queue)
	var queued: int = 0
	for slot: int in count:
		queued += 1 if snap.queue_type[queue * slots + slot] == type else 0
	var head: bool = count > 0 and snap.queue_type[queue * slots] == type
	var goal: int = maxi(snap.type_build_ticks[type], 1) * Production.PROGRESS_PER_TICK
	var done: float = 0.0
	if head:
		done = clampf(float(_entry(snap.queue_progress, queue)) / goal, 0.0, 1.0)
	var requires: int = snap.type_requires[type]
	var state: ItemTile.State = ItemTile.State.AVAILABLE
	if head and done >= 1.0 and tile.tab == World.Tab.STRUCTURES:
		state = ItemTile.State.READY
	elif _producers[tile.tab] == 0 or (requires >= 0 and _owned[requires] == 0):
		state = ItemTile.State.LOCKED
	elif _entry(snap.credits, player) < snap.type_cost[type]:
		state = ItemTile.State.UNAFFORDABLE
	elif count >= slots:
		state = ItemTile.State.FULL
	tile.show_state(state, queued, done)


## One tile per buildable type, in the type table's order, for the snapshot's match.
func _build_tiles(snap: MatchSnapshot) -> void:
	for old: ItemTile in _tiles:
		_grid.remove_child(old)
		old.queue_free()
	_tiles.clear()
	_faction = -1  # The match's own rows tell it again (`_refresh_items`).
	var settings: InputSettings = InputSettings.new()  # The ADR table, as PlayerController does.
	if controller != null and controller.settings != null:
		settings = controller.settings
	for type: int in snap.type_tab.size():
		var type_tab: int = snap.type_tab[type]
		if type_tab < 0 or type_tab >= World.TABS:
			continue
		var art: String = ICON_ART % ("item_%s" % snap.type_ids[type])
		var tile: ItemTile = ItemTile.new()
		tile.name = "Tile_%s" % snap.type_ids[type]
		tile.setup(
			type,
			type_tab,
			load(art) if ResourceLoader.exists(art) else null,
			snap.type_cost[type],
			snap.type_names[type]
		)
		tile.faction = snap.type_faction[type]
		tile.hold_ms = settings.long_press_ms
		tile.slop_dp = settings.tap_slop_dp
		tile.chose.connect(_on_chose.bind(tile))
		tile.cancelled.connect(_on_cancelled.bind(tile))
		tile.dragged.connect(_scroll_by)
		_grid.add_child(tile)
		_tiles.append(tile)
	_show_tab()


## Shows the tiles of the open tab that the local player's faction may queue, in one row: the cards
## of the floating panel in landscape, named; the plain tiles of the portrait band.
func _show_tab() -> void:
	var named: bool = not HudLayout.is_portrait()
	var shown: int = 0
	for tile: ItemTile in _tiles:
		tile.set_named(named)
		tile.visible = tile.tab == tab and (tile.faction < 0 or tile.faction == _faction)
		shown += 1 if tile.visible else 0
	_items_fit.min_dp = Vector2(0.0, ItemTile.CARD_DP.y + ROW_SLACK_DP if named else ITEMS_DP)
	if _actions != null:
		_actions.set_row_dp(_items_fit.min_dp.y)
	_grid.columns = maxi(shown, 1)


## A tap: an available tile queues one item, a ready structure enters placement mode (plan P86),
## any other tile shakes.
func _on_chose(tile: ItemTile) -> void:
	match tile.state:
		ItemTile.State.AVAILABLE:
			_send(Command.queue(_local_player(), tile.type_index))
		ItemTile.State.READY:
			if placement != null:
				placement.begin(tile.type_index)
		_:
			tile.shake()


## The check mark and the X replace the cards while placement mode is on.
func _on_placement_changed() -> void:
	_items.visible = not placement.active


## A hold: the last queued item of the tile's type leaves its queue (and is paid back).
func _on_cancelled(tile: ItemTile) -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null:
		return
	var player: int = _local_player()
	var queue: int = player * World.TABS + tile.tab
	var base: int = queue * _queue_slots(snap)
	for slot: int in range(_entry(snap.queue_count, queue) - 1, -1, -1):
		if snap.queue_type[base + slot] == tile.type_index:
			_send(Command.cancel(player, tile.tab, slot))
			return


## The row follows a finger that went beyond the slop on a tile.
func _scroll_by(relative: Vector2) -> void:
	_items.scroll_horizontal -= roundi(relative.x)
	_items.scroll_vertical -= roundi(relative.y)


## The Command goes out through the controller's sink, with the light haptic.
func _send(command: Command) -> void:
	if controller == null:
		return
	controller.command_sink.call(command)
	if controller.settings.haptics_enabled:
		controller.vibrate.call(controller.settings.haptic_ms)


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
	_grid.add_theme_constant_override("h_separation", gap)
	_show_tab()
	_fit_credits()
	_fit_bar_text()


## Lays the three parts out for the orientation: the band in portrait, the floating panels in
## landscape. The state is the orientation's alone, so a turn and back changes nothing.
func _place() -> void:
	var portrait: bool = HudLayout.is_portrait()
	_house_status(portrait)
	if minimap_slot != null:
		minimap_slot.visible = not portrait
	if pill != null:
		pill.visible = not portrait
		var band: MarginContainer = pill.get_parent() as MarginContainer
		if band != null:  # The pill starts after the Dev button.
			var after: float = 0.0 if top_left == null else top_left.get_combined_minimum_size().x
			band.add_theme_constant_override("margin_left", ceili(after + UiScale.dp(GAP_DP)))
	if portrait:
		var safe: SafeAreaMargin = get_parent() as SafeAreaMargin
		var edge_dp: float = 0.0 if safe == null else safe.margin_dp
		var reserved_dp: float = edge_dp + ArmyBar.GAP_DP + ArmyBar.ALL_ARMY_DP.y
		var safe_dp: float = UiScale.safe_rect_base().size.y / UiScale.base_px_per_dp()
		HudLayout.bottom_zone_dp = HudLayout.band_dp(safe_dp, reserved_dp)
		size_flags_horizontal = Control.SIZE_FILL
		size_flags_vertical = Control.SIZE_SHRINK_END
		custom_minimum_size = Vector2(0.0, HudLayout.bottom_zone_px())
	else:
		HudLayout.bottom_zone_dp = 0.0  # The panel floats: the SelectionPanel reads `right_zone_px`.
		size_flags_horizontal = Control.SIZE_SHRINK_END
		size_flags_vertical = Control.SIZE_SHRINK_END
		var safe: SafeAreaMargin = get_parent() as SafeAreaMargin
		var inset: int = 0 if safe == null else safe.apply().x  # It runs before the safe area's own.
		var inner: float = get_viewport().get_visible_rect().size.x - 2.0 * inset
		custom_minimum_size = Vector2(HudLayout.panel_px(inner), 0.0)


## The status line is the pill's in landscape and the band's first line in portrait (or anywhere
## the scene has no pill).
func _house_status(portrait: bool) -> void:
	var home: Control = _stack if portrait or pill == null else pill
	if _status.get_parent() != home:
		_status.reparent(home, false)
		if home == _stack:
			_stack.move_child(_status, 0)
