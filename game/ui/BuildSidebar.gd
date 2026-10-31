class_name BuildSidebar
extends Control
## The build menu (ADR 0019 section 1, ADR 0023 section 12, ADR 0024; plans P85, P85c, P85b, P85d
## and P85f): the credits and the power bar on one line (`Status`), the three tabs and, below, the
## slot `Items` with the open tab's item tiles. It sends nothing to the sim but Commands through
## `PlayerController.command_sink`: a tap on an available tile is one QUEUE, a hold on a tile with
## items queued is one CANCEL of the last of them. It reads the published snapshot only (the local
## player's credits, power, queue and rows, and the type tables) and never keeps one.
## OPEN or COLLAPSED (ADR 0024 sections 1 to 6), view state only: no Command, nothing in the sim.
## A match starts open. A gesture on the map (`TouchInput.map_gesture`) and the start of placement
## collapse it; the Build button, the Ready badge, a tap that selects an own producer and the end of
## placement (a build or the X; not a strike aim's) open it. A touch on a HUD control is never a map
## gesture, so working in the menu keeps it open. Requests apply in order and the last one wins.
## This node is the clipping holder (a plain `Control` with `clip_contents`; a container cannot be
## smaller than its children): `Backdrop`, the panel that holds the menu's parts, is placed at the
## size of the target state at once and the holder's height slides to it over `menu_slide_ms` (ADR
## 0024 section 8). Input never waits: the parts outside the holder are neither drawn nor picked.
## Landscape (P85d): the floating build panel at the bottom right, `HudLayout.panel_px` wide and as
## high as its tabs and one row of cards, or the plate (`HudLayout.PLATE_DP`: the Ready badge and
## the Build button); the status line moves into `pill`, the floating pill at the top left after
## `top_left`, and `minimap_slot`, the floating panel at the top right that P88 fills, shows.
## Portrait: the bottom band, the full inner width, `HudLayout.band_dp` high, with the status line
## as its first line, or the strip (`HudLayout.STRIP_DP`: the status line over the Build button and
## the Ready badge, the minimap at its right end), and the pill and the slot hidden. A turn only
## moves things: the layout is what `_place` makes of the orientation and the state, and a turn ends
## a slide at its target.
## The minimap (plan P88) is one node that lives in `minimap_slot` sideways and, upright, in the
## `Body` row at its right end, beside the tabs and the item row, or beside the strip's left column
## (the status line above them stays the band's full width): `HudLayout.minimap_box_px` sizes its
## 2:1 box, in a room taken from the target state so the box keeps its size through a slide.
## The menu's height goes to `HudLayout.bottom_zone_dp` and its real top on the screen to
## `HudLayout.menu_top_px` (ADR 0024 section 4) each time they change, and `zone_changed` tells
## whoever lifts something by them (the ArmyBar, the strike row); the first is the one place the
## ArmyBar reads at start-up: this node is the first of the HUD's siblings in the scene, so its
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
## Items: one `ItemTile` per buildable type (icon: its P99b item card), made per match from the
## snapshot's type tables, those of the open tab and of the local player's faction shown, in one row
## that scrolls sideways (the cards of the floating panel carry their names, the band's tiles do
## not). The faction is that of the player's own rows (`type_faction`, the producer-faction rule of
## `Production.apply_queue`): a type of another faction is never shown, one with none is shown to
## all. A tile is READY (a finished structure at the head of its queue: a tap enters placement mode,
## plan P86, which collapses the menu; the check mark and the X stand beside the ghost,
## `GhostControls`), LOCKED (the type's requirement or the tab's producer is not among the player's
## rows), UNAFFORDABLE, FULL (no room in the queue) or AVAILABLE, in that order. A tap on one that
## cannot take an item shakes it.
## Collapsed, the READY state shows as the Ready badge (the card's picture and the word) beside the
## Build button; hidden while the menu is open or placement runs. A tap on it opens the menu on the
## Structures tab with the READY card in view and starts nothing else.
## Selecting an own production building opens its tab, and the menu: `set_selected` is the hook,
## wired to `PlayerController.selection_changed` when `controller` is set.
## The look is the inherited theme's (`game/ui/theme.tres`: `BuildSidebar`, `SidebarTab`,
## `BuildButton`, `ReadyBadge`, `PowerBar`, `PowerBarLow`, `PowerNumber`, `PowerNumberLow`,
## `NumberLabel` and the `ItemTile` family), the sizes are dp.

## Emitted when another tab opens, by a tap or by `select_tab`.
signal tab_selected(tab: int)
## The menu was asked to open or to collapse (at the request, not at the end of the slide).
signal state_changed
## The menu's top on the screen and its height changed, both base px: a request, a frame of the
## slide, a resize. What rides on the menu (the ArmyBar, the strike row) lifts by these.
signal zone_changed(top_px: float, height_px: float)

const ICON_ART: String = "res://assets/art/svg/icons/%s.svg"
const THEME_TYPE: StringName = &"BuildSidebar"
const TAB_VARIATION: StringName = &"SidebarTab"
const BAR_VARIATION: StringName = &"PowerBar"
const BAR_LOW_VARIATION: StringName = &"PowerBarLow"
const NUMBER_VARIATION: StringName = &"NumberLabel"
const BAR_NUMBER_VARIATION: StringName = &"PowerNumber"
const BAR_NUMBER_LOW_VARIATION: StringName = &"PowerNumberLow"
const BUILD_VARIATION: StringName = &"BuildButton"
const BADGE_VARIATION: StringName = &"ReadyBadge"
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
## What the content's least height may pass the band's by (the gaps round to whole px) before the
## band grows to it instead of the content being cut.
const ROUNDING_PX: float = 1.0
const BUILD_DP: Vector2 = Vector2(64.0, 48.0)  ## The Build button.
const BUTTONS_DP: float = 48.0  ## The button row's height. The Ready badge is 112 dp wide at most.
const BADGE_ICON_DP: float = 32.0  ## The card's picture on the Ready badge.
const TEXT_PAD_DP: float = 4.0  ## Each side of the numbers in the bar.
const TEXT_EDGE_DP: float = 2.0  ## The dark edge of the numbers on the green bar.
## The credits' slot: 99 999. The rules set no ceiling (a snapshot holds an int32); a bigger bank
## widens the line by a digit once.
const CREDITS_DIGITS: int = 5

## Tests only, like `UiScale`'s override: the slide's duration in ms, or -1 for the settings'. A
## test that sets one clears it in `after_test`, and never writes `menu_slide_ms` into the resource.
static var _slide_override: int = -1

@export var runner: MatchRunner
@export var controller: PlayerController  ## The Commands' sink, the haptic, the selection.
@export var pill: Control  ## The landscape home of `Status` (a panel in a band at the top left).
@export var minimap_slot: Control  ## The landscape panel at the top right: the minimap's home.
@export var minimap: Control  ## The minimap: in `minimap_slot` sideways, in the band upright.
@export var top_left: Control  ## The pill starts after it (the Dev button).
@export var placement: PlacementController  ## A tap on a READY tile begins it. None: no placement.

## The open tab, a `World.Tab`.
var tab: int = World.Tab.STRUCTURES

var _backdrop: PanelContainer = PanelContainer.new()  ## The menu's panel, at the target's size.
var _stack: VBoxContainer = VBoxContainer.new()
var _body: HBoxContainer = HBoxContainer.new()  ## Below the status line: `_left`, then the minimap.
var _left: VBoxContainer = VBoxContainer.new()  ## The tabs and the item row.
var _strip: VBoxContainer = VBoxContainer.new()  ## Collapsed upright: the status line, the buttons.
var _buttons: HBoxContainer = HBoxContainer.new()  ## The Build button and the Ready badge.
var _build: Button = Button.new()
var _badge: Button = Button.new()
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
var _tiles: Array[ItemTile] = []
var _low: bool = false
var _faction: int = -1  ## The local player's faction (`type_faction`); -1 until a row shows it.
var _shown: Vector3i = Vector3i(-1, -1, -1)  ## Credits, power made and power used on screen.
var _seen: Vector2i = Vector2i(-1, -1)  ## Serial and tick of the snapshot last read.
var _built: Vector2i = Vector2i(-1, -1)  ## Match serial and type count the tiles are made for.
var _owned: PackedInt32Array = PackedInt32Array()  ## Scratch of a refresh: own rows per type.
var _producers: PackedInt32Array = PackedInt32Array()  ## And own producers per tab.
var _ready_tile: ItemTile = null  ## The tile of the finished structure at the head, if any.
var _open: bool = true
var _placing: bool = false  ## Placement mode was on at the last `placement.changed`.
var _before: bool = true  ## The state when placement began: what the end of it returns to.
var _sliding: bool = false
var _height: float = 0.0  ## The visible height now, base px (the holder's).
var _target: float = 0.0  ## And where the slide goes.
var _from: float = 0.0
var _elapsed: float = 0.0  ## Ms into the slide.
var _duration: float = 0.0  ## Ms the slide takes: the share of `menu_slide_ms` its distance needs.
var _open_px: float = 0.0  ## The open menu's height and the collapsed one's, base px.
var _closed_px: float = 0.0
var _wide: float = 0.0  ## The holder's width while open, and (landscape) once the plate is in.
var _narrow: float = 0.0
var _dp_px: float = 1.0  ## `UiScale.base_px_per_dp()` and the orientation, read by `_place`: the
var _portrait: bool = false  ## frames of a slide ask `UiScale` for nothing.
var _inner: float = 0.0  ## The safe area's inner width, base px.
var _bottom_edge: float = 0.0  ## Where the safe area's inner rect ends (portrait): the menu's foot.
var _safe_end: float = 0.0  ## Where the safe rect ends: the "top" of a landscape panel that floats.
var _placed: bool = false  ## The first layout is in: a later change may slide.
var _told: Vector2 = Vector2(NAN, NAN)  ## The top and the height `zone_changed` last said.
var _default_settings: InputSettings = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # Only the backdrop takes touches.
	clip_contents = true  # What the slide has not uncovered is neither drawn nor picked.
	_backdrop.name = "Backdrop"
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP  # A touch on the menu never reaches the map.
	_backdrop.theme_type_variation = THEME_TYPE
	add_child(_backdrop)
	_stack.name = "Stack"
	_backdrop.add_child(_stack)
	_build_status()
	_body.name = "Body"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.add_child(_body)
	_left.name = "Left"
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_left)
	_strip.name = "Strip"
	_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_strip)
	_build_buttons()
	_build_tabs()
	_items.name = "Items"
	_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_items.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER  # One row, sideways.
	_items.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_items_fit.min_dp = Vector2(0.0, ITEMS_DP)
	_items.add_child(_items_fit)
	_items.add_child(_grid)
	_left.add_child(_items)
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
	if placement != null:
		placement.changed.connect(_on_placement_changed)


func _exit_tree() -> void:
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _credits_glyph != null and _power_glyph != null:
		_tint()
		_fit_credits()


## Tests only: the slide takes `ms` (0: the state's layout shows at once) whatever the settings say.
static func set_slide_ms_override(ms: int) -> void:
	_slide_override = ms


static func clear_slide_ms_override() -> void:
	_slide_override = -1


func is_open() -> bool:
	return _open


## Opens the menu: the open layout is placed at once and its height slides up (ADR 0024 section 6).
func open() -> void:
	_set_open(true)


## Collapses the menu to the strip or the plate (section 5). A touch on a HUD control never asks.
func collapse() -> void:
	_set_open(false)


## Moves the slide on by `seconds`: the frame's work, and what a test steps by hand. The height
## eases out (cubic); the end is the target exactly.
func advance(seconds: float) -> void:
	if not _sliding:
		return
	_elapsed += seconds * 1000.0
	var share: float = clampf(_elapsed / _duration, 0.0, 1.0)
	_sliding = share < 1.0
	_apply_height(lerpf(_from, _target, 1.0 - pow(1.0 - share, 3.0)))


func _set_open(on: bool) -> void:
	if on == _open:
		return
	_open = on
	_sync_badge()  # Before the layout: the plate is as wide as its row.
	_place(false)
	state_changed.emit()


## The tap on the Ready badge: the Structures tab with the READY card in view; nothing else.
func _on_badge() -> void:
	select_tab(World.Tab.STRUCTURES)
	open()
	await get_tree().process_frame  # The open layout is sorted at the end of this frame.
	if _ready_tile != null and _open:
		_items.ensure_control_visible(_ready_tile)


## Placement begins: the menu goes down, remembering its state. It ends with a build or the X: the
## menu returns to that state, but not after a strike aim (which would move its row under the thumb)
## and not at the match's end.
func _on_placement_changed() -> void:
	if placement == null or placement.active == _placing:
		return
	_placing = placement.active
	if _placing:
		_before = _open
		collapse()
	else:
		var aimed: bool = placement.strike_aim != null and placement.strike_aim.active
		var snap: MatchSnapshot = null if runner == null else runner.snapshot
		var ended: bool = snap != null and snap.match_end_tick > 0
		if _before and not aimed and not ended:
			open()
	_show_badge()


## A frame moves the slide on, and reads the published snapshot when it is a new one (a tick, or a
## new match): a frame has at most one publish to see, and the numbers change only a few times a
## second.
func _process(delta: float) -> void:
	advance(delta)
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap != null and Vector2i(snap.match_serial, snap.tick) != _seen:
		refresh()


## Shows the local player's credits and power from the published snapshot.
func refresh() -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null or runner.scenario == null:
		return
	var player: int = runner.scenario.local_player
	if _seen.x >= 0 and _seen.x != snap.match_serial:
		open()  # A new match starts with the menu open (ADR 0024 section 1).
	_seen = Vector2i(snap.match_serial, snap.tick)
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


## The selection hook (ADR 0019 section 1, ADR 0024 section 6): a lone own building that produces a
## tab opens it, and opens the menu (the tap's own map gesture collapsed it a moment ago in the same
## frame, and the last request wins). The building selection (plan P84d) needs only to put the
## building's id in the selection; units and anything else leave the open tab and the state as they
## are.
func set_selected(ids: PackedInt32Array) -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null or ids.size() != 1:
		return
	var row: int = snap.index_of(ids[0])
	if row >= 0 and snap.owner[row] == _local_player():
		var produces: int = snap.type_produces[snap.type_index[row]]
		if produces >= 0 and produces < _tabs.size():
			select_tab(produces)
			open()


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
	_left.add_child(_tab_row)
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


## The collapsed menu's row: the Build button, and the Ready badge when a structure is ready.
func _build_buttons() -> void:
	_buttons.name = "Buttons"
	_buttons.visible = false
	_stack.add_child(_buttons)
	_build.name = "Build"
	_build.theme_type_variation = BUILD_VARIATION
	_build.icon = load(ICON_ART % "glyph_menu_open")
	_build.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER  # The icon alone, in the plate.
	_build.focus_mode = Control.FOCUS_NONE
	_build.pressed.connect(open)
	_min_dp(_build, BUILD_DP)
	_buttons.add_child(_build)
	_badge.name = "Ready"
	_badge.theme_type_variation = BADGE_VARIATION
	_badge.text = "Ready"
	_badge.focus_mode = Control.FOCUS_NONE
	_badge.visible = false
	_badge.pressed.connect(_on_badge)
	_min_dp(_badge, Vector2(0.0, BUTTONS_DP))
	_buttons.add_child(_badge)


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
	_ready_tile = null
	for tile: ItemTile in _tiles:
		_show_tile(tile, snap, player, slots)
		if tile.state == ItemTile.State.READY:
			_ready_tile = tile
	_show_badge()


## The Ready badge: the finished structure's card and the word, only while the menu is collapsed
## and no placement runs (the ready structure is then the one on the map).
func _badge_wanted() -> bool:
	return _ready_tile != null and not _open and not _placing


## Shows or hides the badge as `_badge_wanted` says and gives it the card's picture. True when it
## came or went.
func _sync_badge() -> bool:
	var shown: bool = _badge_wanted()
	if shown and _badge.icon != _ready_tile.art():
		_badge.icon = _ready_tile.art()
	var changed: bool = shown != _badge.visible
	_badge.visible = shown
	return changed


## The badge came or went: the sideways plate is as wide as its row, so it is laid out again.
func _show_badge() -> void:
	if _sync_badge() and not _open and not _portrait:
		_place(false)


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
	_ready_tile = null
	var settings: InputSettings = _input_settings()
	for type: int in snap.type_tab.size():
		var type_tab: int = snap.type_tab[type]
		if type_tab < 0 or type_tab >= World.TABS:
			continue
		var art: String = SelectionPanel.ICON_ART % snap.type_ids[type]  # The generated card (P99b).
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


## The thresholds and timings: the controller's, or the ADR table as PlayerController has it.
func _input_settings() -> InputSettings:
	if controller != null and controller.settings != null:
		return controller.settings
	if _default_settings == null:
		_default_settings = InputSettings.new()
	return _default_settings


## Sizes are dp, so they follow a resize like DpMinSize does. A resize settles the layout: a turn
## during a slide ends it at its target.
func _apply_dp() -> void:
	var gap: int = roundi(UiScale.dp(GAP_DP))
	for row: BoxContainer in [_stack, _body, _left, _tab_row, _strip, _buttons]:
		row.add_theme_constant_override("separation", gap)
	_status.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP / 2.0)))
	for button: Button in _tabs:
		button.add_theme_constant_override("icon_max_width", roundi(UiScale.dp(TAB_ICON_DP)))
	_build.add_theme_constant_override("icon_max_width", roundi(UiScale.dp(TAB_ICON_DP)))
	_badge.add_theme_constant_override("icon_max_width", roundi(UiScale.dp(BADGE_ICON_DP)))
	_badge.add_theme_constant_override("h_separation", roundi(UiScale.dp(GAP_DP / 2.0)))
	_bar_text.add_theme_constant_override("outline_size", roundi(UiScale.dp(TEXT_EDGE_DP)))
	_grid.add_theme_constant_override("h_separation", gap)
	_show_tab()
	_measure()
	_place(true)
	_fit_credits()
	_fit_bar_text()


## Reads what the window decides, once per resize: the orientation and the dp, the safe area's inner
## rect, the open and the collapsed heights and the panel's width. A slide frame and a change of
## state use these and ask `UiScale` for nothing.
func _measure() -> void:
	_portrait = HudLayout.is_portrait()
	_dp_px = UiScale.base_px_per_dp()
	if minimap_slot != null:
		minimap_slot.visible = not _portrait
	if pill != null:
		pill.visible = not _portrait
		var band: MarginContainer = pill.get_parent() as MarginContainer
		if band != null:  # The pill starts after the Dev button.
			var after: float = 0.0 if top_left == null else top_left.get_combined_minimum_size().x
			band.add_theme_constant_override("margin_left", ceili(after + UiScale.dp(GAP_DP)))
	var safe: SafeAreaMargin = get_parent() as SafeAreaMargin
	var inset: Vector2i = Vector2i.ZERO
	if safe != null:
		inset = safe.apply()  # It runs before the safe area's own handler.
	var screen: Vector2 = get_viewport().get_visible_rect().size
	_inner = screen.x - 2.0 * inset.x
	var safe_rect: Rect2 = UiScale.safe_rect_base()
	size_flags_vertical = Control.SIZE_SHRINK_END
	if _portrait:
		# The band stands on the safe area's inner bottom, which is the margin above the screen's.
		var edge_dp: float = 0.0 if safe == null else safe.margin_dp
		var reserved_dp: float = edge_dp + ArmyBar.GAP_DP + ArmyBar.ALL_ARMY_DP.y
		_open_px = HudLayout.band_dp(safe_rect.size.y / _dp_px, reserved_dp) * _dp_px
		_closed_px = HudLayout.STRIP_DP * _dp_px
		_bottom_edge = screen.y - inset.y
		_wide = _inner
		size_flags_horizontal = Control.SIZE_FILL
	else:
		_closed_px = HudLayout.PLATE_DP * _dp_px
		_safe_end = safe_rect.end.y  # The panel floats: nothing covers the map's bottom edge.
		_wide = HudLayout.panel_px(_inner)
		size_flags_horizontal = Control.SIZE_SHRINK_END


## Lays the menu out for the orientation and the state: the open band or the strip in portrait, the
## floating panel or the plate in landscape. The parts are placed at the target's size at once, in
## the backdrop, and the holder goes to the target's height: at once when `settle` (a resize), the
## first time, with no slide in the settings or when it is there already, else over the slide. The
## layout is the orientation's and the state's alone, so a turn and back changes nothing.
func _place(settle: bool) -> void:
	_house(_portrait)
	_place_minimap()
	var least: Vector2 = _backdrop.get_combined_minimum_size()
	var width: float = _wide
	if not _portrait:
		if _open:
			_open_px = least.y  # The panel is as high as its tabs and one row of cards.
		else:
			width = least.x  # The plate is as wide as its row.
			_narrow = width
	var to: float = _open_px if _open else _closed_px
	if _portrait and least.y > to + ROUNDING_PX:
		to = least.y  # A band whose content needs more is that high (P86c), not clipped.
		if _open:
			_open_px = to
		else:
			_closed_px = to
	_backdrop.size = Vector2(width, to)
	_retarget(to, settle)


## The holder goes to `to` base px: at once, or by a slide of the share of `menu_slide_ms` that the
## distance needs (the whole of it for the distance between the states); a request mid-slide starts
## from the height the menu has.
func _retarget(to: float, settle: bool) -> void:
	_target = to
	var distance: float = absf(to - _height)
	var ms: float = float(_slide_ms())
	if settle or not _placed or ms <= 0.0 or distance < 0.5:
		_sliding = false
		_apply_height(to)
	else:
		_sliding = true
		_from = _height
		_elapsed = 0.0
		_duration = ms * distance / maxf(absf(_open_px - _closed_px), distance)
		_apply_height(_height)  # A landscape panel widens now; its height follows.
	_placed = true


func _slide_ms() -> int:
	return _slide_override if _slide_override >= 0 else _input_settings().menu_slide_ms


## Sets the holder's height and publishes the menu's height and top (ADR 0024 section 4). A frame of
## the slide is this alone: the parts are laid out and the metrics cached, so it asks `UiScale`
## nothing and allocates nothing but the signal's.
func _apply_height(height: float) -> void:
	_height = height
	# The landscape panel narrows to the plate at the end of a collapse, and widens at the start of
	# an opening: the holder keeps the panel's width while the plate slides down.
	var width: float = _wide if _portrait or _open or _sliding else _narrow
	custom_minimum_size = Vector2(0.0 if _portrait else width, height)
	_backdrop.position = Vector2(width - _backdrop.size.x, 0.0)
	var zone: float = height if _portrait else 0.0  # The landscape panel floats: no zone.
	HudLayout.bottom_zone_dp = zone / _dp_px
	_publish_top()
	var top: float = HudLayout.menu_top_px
	if top != _told.x or zone != _told.y:
		_told = Vector2(top, zone)
		zone_changed.emit(top, zone)


## Writes `HudLayout.menu_top_px`: the menu's drawn top (ADR 0024 section 4). Portrait: the band
## stands on the safe area's inner bottom, which is the margin above the screen's, and is as high as
## it is drawn (the holder's height, or more where its content needs more), so the top is read from
## the cached foot and that height. Landscape: nothing covers the map's bottom edge, the panel
## floats.
func _publish_top() -> void:
	if _portrait:
		HudLayout.menu_top_px = _bottom_edge - maxf(_height, get_combined_minimum_size().y)
	else:
		HudLayout.menu_top_px = _safe_end


## Which parts show, and where the status line, the buttons and the minimap are housed: the
## status line is the pill's in landscape; upright, the band's first line or the strip's; the
## button row is the strip's second line or, sideways, the plate itself.
func _house(portrait: bool) -> void:
	var line: bool = portrait or pill == null
	var strip: bool = line and not _open
	var home: Control = _strip if strip else _stack if line else pill
	if _status.get_parent() != home:
		_status.reparent(home, false)
	if home != pill:
		home.move_child(_status, 0)
	var row: Control = _strip if strip else _stack
	if _buttons.get_parent() != row:
		_buttons.reparent(row, false)
	row.move_child(_buttons, row.get_child_count() - 1)
	_buttons.move_child(_badge, 1 if portrait else 0)  # The Build button is the right thumb's.
	_buttons.visible = not _open
	_strip.visible = strip
	_left.visible = _open
	_body.visible = line or _open


## The minimap goes to the floating panel sideways, where it fills the slot, and to the `Body` row
## upright: a 2:1 box of at most 40 % of the row and no higher than the menu leaves beside its
## tabs and item row (the band's) or beside the strip's two lines (the backdrop and the band's
## status line are not its). The room is the target state's, so the box is one size through a slide;
## on a phone the width rule binds, and it is the same in both states. It takes its width by the
## row's stretch (the box's share against the left column's) and asks for its height only, so the
## band's least width grows by the row's 8 dp gap and no more. That matters: the SafeArea grows
## while a wide SelectionPanel line is being fitted and comes back only when its least width
## changes, so a band whose least width is above the line's final one (tabs plus box) would leave
## it stuck wide.
func _place_minimap() -> void:
	if minimap == null:
		return
	var home: Control = _body if _portrait or minimap_slot == null else minimap_slot
	if minimap.get_parent() != home:
		minimap.reparent(home, false)
	minimap.custom_minimum_size = Vector2.ZERO
	minimap.size_flags_stretch_ratio = 1.0
	_left.size_flags_stretch_ratio = 1.0
	_strip.size_flags_stretch_ratio = 1.0
	if not _portrait:
		minimap.size_flags_horizontal = Control.SIZE_FILL
		minimap.size_flags_vertical = Control.SIZE_FILL
		return
	var chrome: Vector2 = _backdrop.get_theme_stylebox(&"panel").get_minimum_size()
	var row: float = _inner - chrome.x
	var gap: float = roundi(UiScale.dp(GAP_DP))
	var room: float = (_open_px if _open else _closed_px) - chrome.y
	if _open:
		room -= UiScale.dp(STATUS_DP + GAP_DP)
	var box: Vector2 = HudLayout.minimap_box_px(row - gap, room)
	minimap.custom_minimum_size = Vector2(0.0, box.y)
	minimap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	minimap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	minimap.size_flags_stretch_ratio = box.x
	_left.size_flags_stretch_ratio = maxf(row - gap - box.x, 1.0)
	_strip.size_flags_stretch_ratio = _left.size_flags_stretch_ratio
