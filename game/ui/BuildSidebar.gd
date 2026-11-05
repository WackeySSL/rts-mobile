class_name BuildSidebar
extends Control
## The build drawer (ADR 0025 sections 5 and 6, plan P120; it grew out of ADR 0019 section 1, ADR
## 0023 section 12 and ADR 0024): a side panel at the right edge in landscape, a bottom sheet in
## portrait, over the map. From the top: the handle (upright), the three tabs (an icon over the
## name) with the close button and the grid of the open tab's item cards, which scrolls vertically.
## name) with the close button and the grid of the open tab's item cards, which scrolls up and down.
## The economy pill stays in its corner while the drawer is open (Michael, 2026-11-05; ADR 0025's
## "folds under the drawer" no longer holds). It sends nothing to the sim but Commands through
## `PlayerController.command_sink`: a tap on an available card is one QUEUE, a hold on any card
## cancels the last of its type queued (Michael, 2026-11-05). It reads the published snapshot only
## and never keeps one.
## Open or closed is `HudState`'s DRAWER (`feed.state`, ADR 0025 section 1), view state only: no
## Command, nothing in the sim. A match starts closed. A gesture on the map, the start of placement
## or of a strike aim, another unfold and the close button fold it (the feed and the state do the
## folding; a swipe past `drawer_swipe_dp` toward the edge it came from does too: landscape any
## horizontal drag on the panel, portrait a drag that starts
## on the handle or the tabs). BUILD, a tap that selects
## an own producer (its tab, `set_selected`) and the end of a placement that began in the drawer
## (ADR 0024 R1; not after a strike aim, not at the match's end) open it. Starting a placement from
## the drawer again (a READY card tapped while one runs) closes it, as the first start did.
## This node is the clipping holder (a plain `Control` with `clip_contents`), over the part of
## the drawer that has slid in: `Backdrop` is at the drawer's full size (`HudCorners`' DRAWER
## rect, reaching on to the screen's edge, its content inside the safe rect) and the holder's extent
## slides over `menu_slide_ms` (ADR 0024 section 8): its width in landscape, its height in portrait.
## Input never waits: what is outside the holder is neither drawn nor picked. A turn ends a slide at
## its target and lays the drawer out for the other orientation.
## The sheet's height goes to `HudLayout.bottom_zone_dp` and its real top on the screen to
## `HudLayout.menu_top_px` (ADR 0024 section 4), and `zone_changed` tells whoever lifts something by
## them (the strike row). Upright the zone is the sheet's height while the drawer is open and 0
## while it is closed; sideways it is 0.
## Cards: one `ItemTile` per buildable type (icon: its P99b item card), made per match from the
## snapshot's type tables, those of the open tab and of the local player's faction shown. The
## faction is that of the player's own rows (`type_faction`, the producer-faction rule of
## `Production.apply_queue`). A tile is READY (a finished structure at the head of its queue: a tap
## enters placement mode, plan P86; the check mark and the X stand beside the ghost,
## `GhostControls`), LOCKED, UNAFFORDABLE, FULL or AVAILABLE, in that order. A tap on one that
## cannot take an item shakes it. Until P120c the READY card is reached through BUILD and the
## Structures tab.
## The look is the inherited theme's (`HudPanel` for the backdrop, `SidebarTab`, `ItemCaption` and
## the `ItemTile` family), the sizes are dp.

## Emitted when another tab opens, by a tap or by `select_tab`.
signal tab_selected(tab: int)
## The drawer was opened or closed (at the request, not at the end of the slide), or was laid out
## anew by a resize while open.
signal state_changed
## The sheet's top on the screen and the zone's height changed, both base px: a request, a frame of
## the slide, a resize. What rides on the drawer (the strike row) lifts by these.
signal zone_changed(top_px: float, height_px: float)

const ICON_ART: String = "res://assets/art/svg/icons/%s.svg"
const THEME_TYPE: StringName = &"HudPanel"  ## ADR 0025 section 13: the panel token and its edge.
const TAB_VARIATION: StringName = &"SidebarTab"
## The tab names by `World.Tab`; the icon of a tab is `tab_<name in lower case>`.
const TAB_NAMES: PackedStringArray = ["Structures", "Infantry", "Vehicles"]
const TAB_DP: float = 56.0  ## An icon over the name needs more than the 48 dp of a bare icon.
const TAB_ICON_DP: float = 22.0
const NAME_VARIATION: StringName = &"ItemCaption"  ## 14 sp: "Structures" fits a tab.
const HANDLE_DP: Vector2 = Vector2(40.0, 4.0)  ## The sheet's handle (ADR 0025 section 5).
const CLOSE_DP: float = 48.0  ## The close button's least width; it is as high as the tabs.
const HANDLE_GAP_DP: float = 4.0  ## Above and below the handle.
const CLOSE_ICON_DP: float = 28.0
## Beside the backdrop's own 8 dp: the 16 dp each side that three 88 dp cards need 312 dp for.
const PAD_DP: float = 8.0
const GAP_DP: float = 8.0
const TAB_GAP_DP: float = 4.0  ## Between the tabs and the close button: "Structures" needs it.
## The slot of the cards is their height and this, because a box container sorts in whole px and
## would otherwise leave a card a fraction of a px taller than the slot that holds it.
const ROW_SLACK_DP: float = 2.0
## The grid's least height: the drawer's content must fit the safe height on `web_phone_small`
## (ADR 0025 section 5: the grid scrolls there), so no whole card row is asked for.
const FIT_LEAST_DP: float = 48.0

## Tests only, like `UiScale`'s override: the slide's duration in ms, or -1 for the settings'. A
## test that sets one clears it in `after_test`, and never writes `menu_slide_ms` into the resource.
static var _slide_override: int = -1

@export var runner: MatchRunner
@export var controller: PlayerController  ## The Commands' sink, the haptic, the selection.
@export var placement: PlacementController  ## A tap on a READY card begins it. None: no placement.
@export var strike_aim: StrikeAim  ## Aiming a strike takes the drawer down, as placement does.
@export var feed: HudStateFeed  ## Its `state` says whether the drawer is open.
@export var safe_area: SafeAreaMargin  ## Its gap is the safe rect's (ADR 0025 section 2).

## The open tab, a `World.Tab`.
var tab: int = World.Tab.STRUCTURES

var _backdrop: PanelContainer = PanelContainer.new()  ## The drawer, at its full size.
var _pad: MarginContainer = MarginContainer.new()  ## The padding, and the screen edge beyond.
var _stack: VBoxContainer = VBoxContainer.new()
var _grab: HBoxContainer = HBoxContainer.new()  ## The handle's row, upright only.
var _close: Button = Button.new()
var _chevron: TextureRect = TextureRect.new()  ## Faces the edge the drawer leaves by.
var _tab_row: HBoxContainer = HBoxContainer.new()
var _tabs: Array[Button] = []
var _tab_icons: Array[TextureRect] = []
var _handle: ColorRect = ColorRect.new()  ## Upright only.
var _items: ScrollContainer = ScrollContainer.new()
var _items_fit: DpMinSize = DpMinSize.new()  ## The least height of `_items`: a sliver of a row.
var _makers: PackedInt32Array = PackedInt32Array()  ## The type that produces each tab, else -1.
var _grid: GridContainer = GridContainer.new()
var _tiles: Array[ItemTile] = []
var _faction: int = -1  ## The local player's faction (`type_faction`); -1 until a row shows it.
var _seen: Vector2i = Vector2i(-1, -1)  ## Serial and tick of the snapshot last read.
var _built: Vector2i = Vector2i(-1, -1)  ## Match serial and type count the tiles are made for.
var _owned: PackedInt32Array = PackedInt32Array()  ## Scratch of a refresh: own rows per type.
var _producers: PackedInt32Array = PackedInt32Array()  ## And own producers per tab.
var _cancelling: Command = null  ## The CANCEL of a hold in flight; holds wait for a newer tick.
var _placing: bool = false  ## Placement mode was on at the last `placement.changed`.
var _before: bool = false  ## The drawer was open when placement began: what its end returns to.
var _sliding: bool = false
var _extent: float = 0.0  ## How far the drawer has slid in, base px along its axis.
var _target: float = 0.0  ## And where the slide goes: 0 or `_open_px`.
var _from: float = 0.0
var _elapsed: float = 0.0  ## Ms into the slide.
var _duration: float = 0.0  ## Ms the slide takes: the share of `menu_slide_ms` its distance needs.
var _open_px: float = 0.0  ## The open drawer's extent along its axis, base px.
var _rect: Rect2 = Rect2()  ## The drawer's rect from `HudCorners.place`, base px.
var _edge: float = 0.0  ## From the safe rect to the screen's edge the drawer leaves by, base px.
var _dp_px: float = 1.0  ## `UiScale.base_px_per_dp()` and the orientation, read by `_measure`: the
var _portrait: bool = false  ## frames of a slide ask `UiScale` for nothing.
var _placed: bool = false  ## The first layout is in: a later change may slide.
var _told: Vector2 = Vector2(NAN, NAN)  ## The top and the height `zone_changed` last said.
var _swipe: int = -1  ## The index of the finger that may swipe the drawer shut, else -1.
var _swipe_from: Vector2 = Vector2.ZERO
var _default_settings: InputSettings = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # Only the backdrop takes touches.
	clip_contents = true  # What the slide has not uncovered is neither drawn nor picked.
	visible = false
	_backdrop.name = "Backdrop"
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP  # A touch on the drawer never reaches the map.
	_backdrop.theme_type_variation = THEME_TYPE
	add_child(_backdrop)
	_pad.name = "Pad"
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.add_child(_pad)
	_stack.name = "Stack"
	_pad.add_child(_stack)
	_build_grab()
	_build_tabs()
	_items.name = "Items"
	_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_items.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_items.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER  # A finger drags it.
	_items.add_child(_items_fit)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items.add_child(_grid)
	_stack.add_child(_items)
	select_tab(tab)
	_apply_dp()  # Sets the zone before the strike row reads it.
	get_viewport().size_changed.connect(_apply_dp)
	feed.state.changed.connect(_on_hud_changed)
	if controller != null:
		controller.selection_changed.connect(set_selected)
	if placement != null:
		placement.changed.connect(_on_placement_changed)


func _exit_tree() -> void:
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF
	HudLayout.drawer_side_dp = 0.0


## Tests only: the slide takes `ms` (0: the state's layout shows at once) whatever the settings say.
static func set_slide_ms_override(ms: int) -> void:
	_slide_override = ms


static func clear_slide_ms_override() -> void:
	_slide_override = -1


func is_open() -> bool:
	return feed.state.is_open(HudState.Unfold.DRAWER)


## Opens the drawer (an unfold: it closes the radar's full map and the economy card).
func open() -> void:
	feed.state.open(HudState.Unfold.DRAWER)


## The Ready chip's tap (ADR 0025 section 4, until P130): opens the drawer on the Structures tab
## with the finished structure's card in view. The grid sorts a moment after the tab changes, so
## the scroll waits a frame.
func show_ready() -> void:
	select_tab(World.Tab.STRUCTURES)
	open()
	await get_tree().process_frame
	for tile: ItemTile in _tiles:
		if tile.tab == World.Tab.STRUCTURES and tile.state == ItemTile.State.READY:
			_items.ensure_control_visible(tile)
			if tile.size.y > _items.size.y:  # A short grid: show the card's top, not its foot.
				_items.scroll_vertical = roundi(tile.position.y)
			return


## Closes the drawer (its close button; a gesture on the map does it through the feed).
func collapse() -> void:
	feed.state.close(HudState.Unfold.DRAWER)


## Moves the slide on by `seconds`: the frame's work, and what a test steps by hand. The extent
## eases out (cubic); the end is the target exactly.
func advance(seconds: float) -> void:
	if not _sliding:
		return
	_elapsed += seconds * 1000.0
	var share: float = clampf(_elapsed / _duration, 0.0, 1.0)
	_sliding = share < 1.0
	_apply_extent(lerpf(_from, _target, 1.0 - pow(1.0 - share, 3.0)))


## The unfold changed: slide to the new state, and keep what placement or the aim folded.
func _on_hud_changed(previous: HudState.Unfold) -> void:
	_swipe = -1  # A finger still down on a folded drawer swipes nothing.
	var folded: bool = previous == HudState.Unfold.DRAWER and not is_open()
	if folded and placement != null and placement.active and not _placing:
		_before = true  # The feed folded it for the placement that is just beginning.
	if folded or is_open():
		_place(false)
		state_changed.emit()


## Placement ends with a build or the X: the drawer returns if it was open when placement began,
## but not after a strike aim (which would move its row under the thumb) and not at the match's end.
func _on_placement_changed() -> void:
	if placement == null or placement.active == _placing:
		return
	_placing = placement.active
	if _placing:
		return
	var aimed: bool = strike_aim != null and strike_aim.active
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	var ended: bool = snap != null and snap.match_end_tick > 0
	var back: bool = _before and not aimed and not ended
	_before = false
	if back:
		open()


## A frame moves the slide on, and reads the published snapshot when it is a new one (a tick, or a
## new match): a frame has at most one publish to see, and the numbers change only a few times a
## second.
func _process(delta: float) -> void:
	advance(delta)
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap != null and Vector2i(snap.match_serial, snap.tick) != _seen:
		refresh()


## A drag toward the edge the drawer came from, past `drawer_swipe_dp`, closes it (ADR 0025 section
## 5). Seen before the GUI and consumed by no one: the cards and the head still get their touches.
## Landscape: any horizontal drag that starts on the panel; upright only one that starts on the head
## (the grid's own scroll is vertical).
func _input(event: InputEvent) -> void:
	if not is_open():
		return
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if touch != null:
		var on: bool = touch.pressed and _swipe_zone(touch.position)
		if on and _swipe < 0:
			_swipe = touch.index
			_swipe_from = touch.position
		elif touch.index == _swipe:
			_swipe = -1
	elif drag != null and drag.index == _swipe:
		var moved: Vector2 = drag.position - _swipe_from
		var toward: float = moved.y if _portrait else moved.x
		var across: float = moved.x if _portrait else moved.y
		if toward >= UiScale.dp(_input_settings().drawer_swipe_dp) and toward > absf(across):
			_swipe = -1
			collapse()


## Whether a touch at `at` starts a swipe: sideways the panel, upright the handle and the tabs.
func _swipe_zone(at: Vector2) -> bool:
	if not _portrait:
		return _backdrop.get_global_rect().has_point(at)
	return _grab.get_global_rect().has_point(at) or _tab_row.get_global_rect().has_point(at)


## Reads the published snapshot: the cards' states from the local player's queues and rows.
func refresh() -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null or runner.scenario == null:
		return
	var player: int = runner.scenario.local_player
	_seen = Vector2i(snap.match_serial, snap.tick)
	_refresh_items(snap, player)


## Opens tab `index` (a `World.Tab`; another value is ignored).
func select_tab(index: int) -> void:
	if index < 0 or index >= _tabs.size():
		return
	for at: int in _tabs.size():
		_tabs[at].set_pressed_no_signal(at == index)  # A tap on the open tab keeps it open.
		_tab_icons[at].modulate = _tab_tint(at == index)
	if index != tab:
		tab = index
		_items.scroll_vertical = 0
		_show_tab()
		tab_selected.emit(index)


## The selection hook (ADR 0019 section 1, ADR 0024 section 6): a lone own building that produces a
## tab opens it, and opens the drawer (the tap's own map gesture closed it a moment ago in the same
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


## The handle's row (upright only): the sheet's grab handle, centred.
func _build_grab() -> void:
	_grab.name = "Grab"
	_grab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grab.alignment = BoxContainer.ALIGNMENT_CENTER
	_stack.add_child(_grab)
	_handle.name = "Handle"
	_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_handle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_grab.add_child(_handle)


## The close button at the tabs row's right end: a chevron toward the edge the drawer leaves by.
func _build_close() -> void:
	_close.name = "Close"
	_close.flat = true
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(collapse)
	_min_dp(_close, Vector2(CLOSE_DP, TAB_DP))
	_chevron.texture = load(ICON_ART % "glyph_chevron")
	_chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_chevron.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chevron.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chevron.resized.connect(func() -> void: _chevron.pivot_offset = _chevron.size / 2.0)
	_close.add_child(_chevron)
	_tab_row.add_child(_close)


## The tabs: an icon over the name each (`tab_<name>`, grey at rest and white when open, from the
## theme's `SidebarTab` colours). The open tab is the lighter plate with the thick bar at its foot.
## The icon and the name are the tab's own children, so the name takes the 14 sp of `ItemCaption`
## and the tab stays `TAB_DP` high (a Button's own icon over text measured 84 dp).
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
		button.pressed.connect(select_tab.bind(index))
		_min_dp(button, Vector2(TAB_DP, TAB_DP))
		var content: VBoxContainer = VBoxContainer.new()
		content.name = "Content"
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override("separation", 0)
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		button.add_child(content)
		var icon: TextureRect = TextureRect.new()
		icon.name = "Icon"
		icon.texture = load(ICON_ART % ("tab_" + TAB_NAMES[index].to_lower()))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_min_dp(icon, Vector2(TAB_ICON_DP, TAB_ICON_DP))
		content.add_child(icon)
		var label: Label = Label.new()
		label.name = "Name"
		label.text = TAB_NAMES[index]
		label.theme_type_variation = NAME_VARIATION
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(label)
		_tab_row.add_child(button)
		_tabs.append(button)
		_tab_icons.append(icon)
	_build_close()


## The icon's tint: the open tab's white or the resting grey, from the tab's theme colours.
func _tab_tint(open: bool) -> Color:
	return get_theme_color(&"icon_pressed_color" if open else &"icon_normal_color", TAB_VARIATION)


## Makes the tiles again when the match or the type tables changed, then shows each one's state.
func _refresh_items(snap: MatchSnapshot, player: int) -> void:
	var key: Vector2i = Vector2i(snap.match_serial, snap.type_tab.size())
	if key != _built:
		_built = key
		_cancelling = null  # A new match: the old Command and ticks mean nothing.
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
	_makers.resize(World.TABS)
	_makers.fill(-1)
	for type: int in snap.type_produces.size():
		var made: int = snap.type_produces[type]
		var kin: bool = snap.type_faction[type] < 0 or snap.type_faction[type] == _faction
		if made >= 0 and made < World.TABS and kin and (_makers[made] < 0 or _owned[type] > 0):
			_makers[made] = type
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
	var lacks: int = -1
	if state == ItemTile.State.LOCKED:
		lacks = _makers[tile.tab] if _producers[tile.tab] == 0 else requires
	tile.set_needs(snap.type_names[lacks] if lacks >= 0 else "")


## One tile per buildable type, in the type table's order, for the snapshot's match.
func _build_tiles(snap: MatchSnapshot) -> void:
	for old: ItemTile in _tiles:
		_grid.remove_child(old)
		old.queue_free()
	_tiles.clear()
	_faction = -1  # The match's own rows tell it again (`_refresh_items`).
	var settings: InputSettings = _input_settings()
	for type: int in snap.type_tab.size():
		var type_tab: int = snap.type_tab[type]
		if type_tab < 0 or type_tab >= World.TABS:
			continue
		var art: String = CommandBar.ICON_ART % snap.type_ids[type]  # The generated card (P99b).
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
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # The columns share the room.
		tile.hold_ms = settings.long_press_ms
		tile.slop_dp = settings.tap_slop_dp
		tile.chose.connect(_on_chose.bind(tile))
		tile.long_pressed.connect(_on_long_pressed.bind(tile))
		tile.dragged.connect(_scroll_by)
		_grid.add_child(tile)
		_tiles.append(tile)
	_show_tab()


## Shows the tiles of the open tab that the local player's faction may queue, as cards of the
## orientation's size, in as many columns as the drawer's width holds (no more than the cards).
func _show_tab() -> void:
	var card: Vector2 = ItemTile.CARD_PORTRAIT_DP if _portrait else ItemTile.CARD_DP
	var shown: int = 0
	for tile: ItemTile in _tiles:
		tile.set_card(card)
		tile.visible = tile.tab == tab and (tile.faction < 0 or tile.faction == _faction)
		shown += 1 if tile.visible else 0
	_items_fit.min_dp = Vector2(0.0, FIT_LEAST_DP)
	# As many columns as the width holds, no more than there are cards: the cards (they expand)
	# then end at the right edge, with the margin the left edge has.
	var room: float = _rect.size.x / _dp_px - 4.0 * PAD_DP + GAP_DP
	_grid.columns = clampi(floori(room / (card.x + GAP_DP)), 1, maxi(shown, 1))


## A tap: an available tile queues one item, a ready structure enters placement mode (plan P86) and
## closes the drawer (also when a placement runs already: it restarts), any other tile shakes.
func _on_chose(tile: ItemTile) -> void:
	match tile.state:
		ItemTile.State.AVAILABLE:
			_send(Command.queue(_local_player(), tile.type_index))
		ItemTile.State.READY:
			if placement != null and placement.begin(tile.type_index):
				collapse()
		_:
			tile.shake()


## A hold on a card (`hold_ms`, final once it fires, ADR 0004; a drag after it does not take it
## back) cancels the last item of its type that is queued, with the refund, units, vehicles and
## structures alike. A card with none queued does nothing. Slots shift after a cancel, so holds wait
## until a snapshot newer than the CANCEL's stamped tick has been read (PlacementController's rule:
## on Android the first snapshot after a hold is published before the Command is drained).
func _on_long_pressed(tile: ItemTile) -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null or controller == null:
		return
	if _cancelling != null:
		if _cancelling.tick < 0 or snap.tick <= _cancelling.tick:
			return
		_cancelling = null
	var player: int = _local_player()
	var queue: int = player * World.TABS + tile.tab
	var base: int = queue * _queue_slots(snap)
	for slot: int in range(_entry(snap.queue_count, queue) - 1, -1, -1):
		if snap.queue_type[base + slot] == tile.type_index:
			_cancelling = Command.cancel(player, tile.tab, slot)
			_send(_cancelling)
			return


## The grid follows a finger that went beyond the slop on a tile.
func _scroll_by(relative: Vector2) -> void:
	_items.scroll_vertical -= roundi(relative.y)


## The Command goes out through the controller's sink, with the light haptic.
func _send(command: Command) -> void:
	if controller == null:
		return
	controller.command_sink.call(command)
	_buzz()


func _buzz() -> void:
	if HudPrefs.vibrates(controller.settings):
		controller.vibrate.call(controller.settings.haptic_ms)


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
	_measure()
	var gap: int = roundi(UiScale.dp(GAP_DP))
	_stack.add_theme_constant_override("separation", gap)
	_tab_row.add_theme_constant_override("separation", roundi(UiScale.dp(TAB_GAP_DP)))
	_grid.add_theme_constant_override("h_separation", gap)
	_grid.add_theme_constant_override("v_separation", gap)
	for button: Button in _tabs:  # The content stands inside the plate's margins.
		var plate: StyleBox = button.get_theme_stylebox(&"normal", TAB_VARIATION)
		var content: Control = button.get_node("Content")
		content.offset_left = plate.get_margin(SIDE_LEFT)
		content.offset_top = plate.get_margin(SIDE_TOP)
		content.offset_right = -plate.get_margin(SIDE_RIGHT)
		content.offset_bottom = -plate.get_margin(SIDE_BOTTOM)
	_grab.visible = _portrait
	_handle.visible = _portrait
	_handle.custom_minimum_size = Vector2(UiScale.dp(HANDLE_DP.x), UiScale.dp(HANDLE_DP.y))
	_grab.custom_minimum_size.y = UiScale.dp(HANDLE_DP.y + HANDLE_GAP_DP)
	_handle.color = _tab_tint(false)  # The resting grey of the tabs' icons.
	for at: int in _tab_icons.size():
		_tab_icons[at].modulate = _tab_tint(_tabs[at].button_pressed)
	_chevron.rotation = PI / 2.0 if _portrait else 0.0  # Toward the edge it leaves by.
	var pad: int = roundi(UiScale.dp(PAD_DP))
	_pad.add_theme_constant_override("margin_left", pad)
	_pad.add_theme_constant_override("margin_top", 0)
	_pad.add_theme_constant_override("margin_right", pad + (0 if _portrait else roundi(_edge)))
	_pad.add_theme_constant_override("margin_bottom", pad + (roundi(_edge) if _portrait else 0))
	_show_tab()
	_place(true)
	if is_open():
		state_changed.emit()  # `HudLayout.drawer_side_dp` has a new value.


## Reads what the window decides, once per resize: the orientation and the dp, the drawer's rect
## (`HudCorners.place`, the safe rect of `safe_area`) and the screen's edge beyond it. A slide frame
## uses these and asks `UiScale` for nothing.
func _measure() -> void:
	_portrait = HudLayout.is_portrait()
	_dp_px = UiScale.base_px_per_dp()
	var full: Rect2 = get_viewport().get_visible_rect()
	var margin_dp: float = (
		SafeAreaMargin.DEFAULT_MARGIN_DP if safe_area == null else safe_area.margin_dp
	)
	var safe: Rect2 = SafeAreaMargin.rect_inside(full, margin_dp)
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	shown.drawer = true
	_rect = HudCorners.place(safe, _portrait, _dp_px, false, shown)[HudCorners.DRAWER]
	_open_px = _rect.size.y if _portrait else _rect.size.x
	_edge = full.end.y - safe.end.y if _portrait else full.end.x - safe.end.x


## Lays the drawer out for the state: the holder goes to the target's extent, at once when `settle`
## (a resize), the first time, with no slide in the settings or when it is there already, else over
## the slide (the share of `menu_slide_ms` that the distance needs); a request mid-slide starts from
## the extent the drawer has.
func _place(settle: bool) -> void:
	_target = _open_px if is_open() else 0.0
	HudLayout.drawer_side_dp = _open_px / _dp_px if is_open() and not _portrait else 0.0
	var distance: float = absf(_target - _extent)
	var ms: float = float(_slide_ms())
	if settle or not _placed or ms <= 0.0 or distance < 0.5:
		_sliding = false
		_apply_extent(_target)
	else:
		_sliding = true
		_from = _extent
		_elapsed = 0.0
		_duration = ms * distance / _open_px
		_apply_extent(_extent)
	_placed = true


func _slide_ms() -> int:
	return _slide_override if _slide_override >= 0 else _input_settings().menu_slide_ms


## Sets the holder over the part that has slid in and publishes the zone and the top (ADR 0024
## section 4). A frame of the slide is this alone: the metrics are cached, so it asks `UiScale`
## nothing and allocates nothing but the signal's.
func _apply_extent(extent: float) -> void:
	_extent = extent
	visible = extent > 0.0
	var holder: Vector2
	if _portrait:
		position = Vector2(_rect.position.x, _rect.end.y - extent)
		holder = Vector2(_rect.size.x, extent + _edge)
		_backdrop.size = Vector2(_rect.size.x, _rect.size.y + _edge)
		size = holder
		_backdrop.position = Vector2(0.0, holder.y - _backdrop.size.y)
	else:
		position = Vector2(_rect.end.x - extent, _rect.position.y)
		holder = Vector2(extent + _edge, _rect.size.y)
		_backdrop.size = Vector2(_rect.size.x + _edge, _rect.size.y)
		size = holder
		_backdrop.position = Vector2(holder.x - _backdrop.size.x, 0.0)
	var zone: float = 0.0
	var top: float = INF
	if _portrait:
		zone = extent
		top = _rect.end.y - extent if extent > 0.0 else INF
	HudLayout.bottom_zone_dp = zone / _dp_px
	HudLayout.menu_top_px = top
	if top != _told.x or zone != _told.y:
		_told = Vector2(top, zone)
		zone_changed.emit(top, zone)
