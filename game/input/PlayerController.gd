class_name PlayerController
extends Node
## Turns the selection gestures of TouchInput into selection changes and Commands (ADR 0004
## section 5). It reads the view and the published snapshot (ADR 0012 section 3), afresh at each
## call and never kept, and never writes to the sim: an order leaves through `command_sink` as one
## Command that carries the sorted selection (ADR 0003), a MOVE to a ground point or an ATTACK on
## an enemy's id. A ground tap moves and does not fight, also out of a fight (P43c): the sim drops
## the units' targets and holds their fire until they arrive and stand idle again.
## A ground tap goes through the inverse projection (`IsoProjection.px_to_ground`, ADR 0023
## section 3), rounded to milli-tiles, so the sim only sees integers; a tap outside the map's
## diamond is a Command too, and the sim clamps its target.
## A tap acts at once. A double-tap on an own unit selects its type on screen, a box (a rect on the
## screen, over the units' projected positions) selects the own units inside it, and an empty box
## clears the selection (so does the bar's Deselect, `deselect`). Selection is not a Command, so it
## never reaches the sim. A unit that dies leaves the selection and the groups at once, inside
## `runner.ticked`, and the rings, the bar and the badges follow.
## A building (P115b, ADR 0019 section 3, ADR 0023 section 3) is picked after the units, on its
## silhouette (`Picker.pick_building`): a tap on an own or a shown enemy building selects it alone
## (an enemy one for its info only: it gets no order), the frame, the panel and the sidebar's tab
## follow `selection_changed`. A building never joins a box, a double-tap or "All army". With own
## units selected a tap on an enemy building attacks it, if the sim would take that attack
## (`PickSnapshot.is_targetable`: the view draws an enemy building for any seen cell of its
## footprint, the sim sees it at the cell under its position) and is a ground tap if not. With a
## building selected enemy units do not count (`Picker.pick`), so a tap on one is a tap on the
## ground (ADR 0019 section 3's note of P26ak).
## With own units selected a tap on the ground moves them, and tankers alone (P87) HARVEST when the
## tap is on or near an oil or gas field (`OrderRules.near_field`, a fingertip of reach) and the
## sim would take the order (`OrderRules.ore_within`: ore left within the rules'
## `harvest_pick_milli` of the point); a dry field or a tap too far from the ore is a move. With one
## own barracks or vehicle factory selected a tap on the ground sets that tab's rally point (RALLY),
## shows the flag at once (`rally_ordered`, which `RallyLayer` listens to) and buzzes lightly, and
## the building stays selected; with any other building selected, a Headquarters included, it lets
## go of the selection. "All army" and a box leave tankers out unless the box holds nothing else
## (`OrderRules`).
## While the Board or Unload aim is open (P265, `carry_aim`) a tap on a unit picks the carrier to
## board (anything else is refused with no Command) or a tap on the ground sets the unload point;
## nothing is selected, ordered or boxed.
## While the strike is being aimed (P112, `strike_aim.active`) a tap places its point on the ground
## and no gesture does anything else: nothing is selected, ordered or boxed.
## While placement mode is on (P86, `placement.active`) the gestures go to `placement` alone: a tap
## or a ghost drag moves the ghost, and nothing is selected, ordered or boxed.
## Each order shows its marker and the BoxOverlay follows a long-press and its box, both in the
## frame of the gesture. The selection rings follow `selection_changed` (wired in the scene).

## Emitted with the new `selection.selected` after every real change, and again when a tap lands on
## the one building that is selected already: the sidebar goes back to the tab it builds.
signal selection_changed(ids: PackedInt32Array)
## Emitted with every RALLY a ground tap sends: the tab it is for (a `World.Tab`) and the point as
## sent, in milli-tiles. `RallyLayer` shows the flag at once, before the sim has applied the order.
signal rally_ordered(tab: int, x: int, y: int)

@export var runner: MatchRunner
@export var unit_layer: UnitLayer
@export var building_layer: BuildingLayer  ## Without one no building can be picked.
@export var camera: RtsCamera
@export var settings: InputSettings
@export var marker_layer: MoveMarkerLayer
@export var box_overlay: BoxOverlay
@export var group_column: GroupColumn
@export var strike_aim: StrikeAim  ## Without one there is no strike to aim.
@export var placement: PlacementController  ## Without one there is no placement mode.
@export var carry_aim: CarryAim  ## Without one there are no Board and Unload aims.

var selection: SelectionModel = SelectionModel.new()
## Receives each Command. Tests replace it.
var command_sink: Callable = CommandQueue.submit
## Buzzes for the given ms when a group is assigned. Tests replace it.
var vibrate: Callable = Input.vibrate_handheld

var _snap: PickSnapshot = PickSnapshot.new()
var _group_counts: PackedInt32Array = PackedInt32Array([0, 0, 0])  ## `_show_groups`' scratch.
var _found: PackedInt32Array = PackedInt32Array()  ## Scratch for the Picker's box queries.
var _dead: PackedInt32Array = PackedInt32Array()  ## Scratch for the ids a tick's events name.


func _init() -> void:
	selection.changed.connect(_on_selection_changed)


func _ready() -> void:
	if settings == null:
		settings = InputSettings.new()  # The script defaults are the ADR table.
	if runner != null:
		runner.ticked.connect(_on_ticked)
	if group_column != null:
		group_column.all_army_pressed.connect(select_all_army)
		group_column.group_tapped.connect(tap_group)
		group_column.group_assign_requested.connect(assign_group)
		group_column.save_requested.connect(save_group)


func handle_gesture(e: GestureEvent) -> void:
	if strike_aim != null and strike_aim.active:
		if e.kind == GestureEvent.Kind.TAP or e.kind == GestureEvent.Kind.DOUBLE_TAP:
			strike_aim.place(IsoProjection.px_to_ground(camera.screen_to_world(e.position)))
		return
	if carry_aim != null and carry_aim.is_active():
		if e.kind == GestureEvent.Kind.TAP or e.kind == GestureEvent.Kind.DOUBLE_TAP:
			_carry_tap(e.position)
		return
	if placement != null and placement.active:
		placement.handle_gesture(e)
		return
	match e.kind:
		GestureEvent.Kind.TAP:
			_tap(e.position)
		GestureEvent.Kind.DOUBLE_TAP:
			_double_tap(e.position)
		GestureEvent.Kind.LONG_PRESS:
			box_overlay.show_anchor(e.position)
		GestureEvent.Kind.BOX_UPDATE:
			box_overlay.show_rect(e.rect)
		GestureEvent.Kind.BOX_CANCEL:
			box_overlay.hide_all()
		GestureEvent.Kind.BOX_END:
			box_overlay.hide_all()
			_refresh()
			Picker.own_in_rect(_snap, e.rect, _local_player(), _found)
			# No unit in the box: this clears the selection. Tankers join only a box of tankers.
			selection.set_ids(OrderRules.box_selection(runner.snapshot, _found))


## "All army": every own unit that can move, wherever it is, tankers left out (ADR 0004 section 5,
## ADR 0019 section 3).
func select_all_army() -> void:
	var snap: MatchSnapshot = runner.snapshot
	if snap != null:
		selection.set_ids(OrderRules.all_army(snap, _local_player()))


## The command bar's Deselect (ADR 0025 section 9): clears the selection, units or a building, own
## or an enemy's. No Command, nothing in the sim; it works during placement and the strike aim too.
func deselect() -> void:
	selection.clear()


## The command bar's Stop: one STOP with the selected units, with the light buzz. Nothing with a
## building or nothing selected. It is a HUD tap, not a map tap, so it works while a building is
## placed or a strike aimed too.
func stop() -> bool:
	if not _units_selected():
		return false
	command_sink.call(Command.stop(_local_player(), selection.selected))
	_buzz()
	return true


## The command bar's Mend (ADR 0037 section 4): one MEND for the one own complete building selected,
## its repair switched on or off, with the light buzz. False when the selection is anything else.
func mend(on: bool) -> bool:
	var row: int = _order_row()
	if row < 0:
		return false
	command_sink.call(Command.mend(_local_player(), runner.snapshot.unit_id[row], on))
	_buzz()
	return true


## The command bar's Sell, its second tap (`SellArm`): one SELL for the one own complete building
## selected that has a price, with the buzz. False for any other selection. The sim refuses the
## Headquarters and a site as well.
func sell() -> bool:
	var row: int = _order_row()
	if row < 0 or not BuildingOrders.can_sell(runner.snapshot, row):
		return false
	command_sink.call(Command.sell(_local_player(), runner.snapshot.unit_id[row]))
	_buzz()
	return true


## The row of the one own complete building selected, -1 for any other selection.
func _order_row() -> int:
	return BuildingOrders.target(runner.snapshot, selection.selected, _local_player())


func _buzz() -> void:
	if HudPrefs.vibrates(settings):
		vibrate.call(settings.haptic_ms)


## Whether the selection is own units (not nothing, not a building): what Stop is for.
func units_selected() -> bool:
	return _units_selected()


func tap_group(slot: int) -> void:
	selection.recall_group(slot)


## Stores the selected units in group `slot` (a hold on it overwrites it), shows the count and
## buzzes. With no unit selected (nothing, or a building) it changes nothing and does not buzz: a
## finger resting on a group never wipes it.
func assign_group(slot: int) -> void:
	if not _units_selected():
		return
	selection.assign_group(slot)
	_show_groups()
	_buzz()


## "+": stores the selected units in the lowest free group, with the buzz. Nothing when all groups
## hold some (`assign_group` sees to the units).
func save_group() -> void:
	var slot: int = selection.lowest_free_group()
	if slot > 0:
		assign_group(slot)


func _tap(pos: Vector2) -> void:
	var units: bool = _units_selected()
	var hit: int = _pick(pos, units)
	if hit >= 0 and _snap.owners[hit] == _local_player():
		selection.set_ids(PackedInt32Array([_snap.ids[hit]]))
	elif hit >= 0:  # An enemy: only picked while own units are selected.
		_attack(_snap.ids[hit], _snap.screen_pos[hit] + Vector2(0.0, _snap.lift_of(hit)))
	else:
		var min_half: float = UiScale.dp(settings.hit_radius_dp)
		var shape: int = Picker.pick_building(_snap, pos, _local_player(), units, min_half)
		var hostile: bool = shape >= 0 and units and _snap.building_owners[shape] != _local_player()
		if hostile and _snap.is_targetable(shape):
			_attack(_snap.building_ids[shape], _snap.building_centres[shape])
		elif shape >= 0 and not hostile:
			_select_building(_snap.building_ids[shape])
		elif units:
			_ground_tap(pos)
		else:
			_building_ground_tap(pos)


## A tap on the ground with own units selected (P87): tankers alone, on or near a field that has
## ore the sim would take, HARVEST there; everything else moves.
func _ground_tap(pos: Vector2) -> void:
	var world: Vector2 = camera.screen_to_world(pos)
	var ground: Vector2i = IsoProjection.px_to_ground(world)
	var snap: MatchSnapshot = runner.snapshot
	var reach: float = UiScale.dp(settings.hit_radius_dp) / camera.zoom.x
	if (
		OrderRules.only_tankers(snap, selection.selected)
		and OrderRules.near_field(snap, world, reach)
		and OrderRules.ore_within(snap, ground, _harvest_pick_milli())
	):
		_harvest(ground.x, ground.y)
	else:
		_move(ground.x, ground.y)


## A tap on the ground with a building (or nothing) selected (P87, ADR 0019 section 3): an own
## barracks or vehicle factory alone gets the rally point there and stays selected; any other
## selection, a Headquarters or an enemy building included, is let go.
func _building_ground_tap(pos: Vector2) -> void:
	var building: int = OrderRules.rally_building(
		runner.snapshot, selection.selected, _local_player()
	)
	if building == 0:
		selection.clear()
		return
	var ground: Vector2i = IsoProjection.px_to_ground(camera.screen_to_world(pos))
	command_sink.call(Command.rally(_local_player(), building, ground.x, ground.y))
	rally_ordered.emit(OrderRules.rally_tab(runner.snapshot, building), ground.x, ground.y)
	_buzz()


## Selects building `id` alone. The model does not fire for the building that is the selection
## already, so then the signal goes out by hand: the player may have opened another tab since, and
## a tap on the building takes the sidebar back to the one it builds. Every listener is idempotent.
func _select_building(id: int) -> void:
	var alone: PackedInt32Array = PackedInt32Array([id])
	if selection.selected == alone:
		selection_changed.emit(selection.selected)
	else:
		selection.set_ids(alone)


func _double_tap(pos: Vector2) -> void:
	var hit: int = _pick(pos, _units_selected())
	if hit < 0 or _snap.owners[hit] != _local_player():
		_tap(pos)  # Anywhere but on an own unit it is a plain tap, also on a building.
		return
	var on_screen: Rect2 = get_viewport().get_visible_rect()
	Picker.own_of_type_in_rect(_snap, _snap.type_index[hit], on_screen, _local_player(), _found)
	_found.append(_snap.ids[hit])  # The tapped unit counts, even with its centre off screen.
	selection.set_ids(_found)


## Refreshes the snapshot and returns the Picker's index for `pos` (a World row), or -1. `units`:
## own units are selected, so an enemy unit can be picked.
func _pick(pos: Vector2, units: bool) -> int:
	_refresh()
	return Picker.pick(_snap, pos, _local_player(), units)


func _refresh() -> void:
	unit_layer.fill_pick_snapshot(_snap, UiScale.dp(settings.hit_radius_dp))
	if building_layer != null:
		building_layer.fill_pick_snapshot(_snap, camera)


## Whether the selection is units: any selection but the one building a tap on a building makes
## (it is alone, so its first id says).
func _units_selected() -> bool:
	if selection.selected.is_empty():
		return false
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	var row: int = -1 if snap == null else snap.index_of(selection.selected[0])
	return row < 0 or not WorldSort.is_building(snap, snap.type_index[row])


func _on_selection_changed() -> void:
	selection_changed.emit(selection.selected)
	_show_groups()  # "+" follows the selection.


## The units that died in the tick just published leave the selection and the groups. A change of
## the selection reaches the rings and the panel through `selection_changed`, in this frame, and
## the badges show the groups' new counts.
func _on_ticked(_tick: int) -> void:
	var events: PackedInt32Array = runner.snapshot.events
	_dead.clear()
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		if events[at] == World.Event.DIED:
			_dead.append(events[at + 1])
	if _dead.is_empty():
		return
	selection.remove_ids(_dead)
	_show_groups()


## Tells the group column the counts of the groups and whether "+" can save (units are selected and
## a group is free).
func _show_groups() -> void:
	if group_column == null:
		return
	for slot: int in range(1, SelectionModel.GROUP_COUNT + 1):
		_group_counts[slot - 1] = selection.group_size(slot)
	var can_save: bool = selection.lowest_free_group() > 0 and _units_selected()
	group_column.show_groups(_group_counts, can_save)


## A tap with the Board or Unload aim open (P265). Only own units and buildings are candidates: an
## enemy under the finger never steals the tap. Board rings the own carrier that can take squads (it
## wins over any other own unit the tap also hits; any other tap is refused with no Command).
## Unload refuses a tap on an own unit or building (a shake, no point) and sets the point anywhere
## else.
func _carry_tap(pos: Vector2) -> void:
	_refresh()
	var snap: MatchSnapshot = runner.snapshot
	var player: int = _local_player()
	var carrier: int = 0  # The nearest own carrier with a free seat the tap hits.
	var carrier_d2: float = INF
	var own: bool = false  # An own unit or building lies under the finger.
	for index: int in _snap.size():
		var skip: bool = index < _snap.pickable.size() and _snap.pickable[index] == 0
		var d2: float = _snap.screen_pos[index].distance_squared_to(pos)
		if skip or _snap.owners[index] != player or d2 > _snap.radius_px[index] ** 2:
			continue
		own = true
		var row: int = snap.index_of(_snap.ids[index])
		if row >= 0 and d2 < carrier_d2 and CarryRules.can_take_squads(snap, row, player):
			carrier = _snap.ids[index]
			carrier_d2 = d2
	if carry_aim.mode == CarryAim.Mode.BOARD:
		carry_aim.pick_carrier(carrier)
		return
	var shape: int = Picker.pick_building(
		_snap, pos, player, false, UiScale.dp(settings.hit_radius_dp)
	)
	own = own or (shape >= 0 and _snap.building_owners[shape] == player)
	if own:
		carry_aim.refuse()
	else:
		carry_aim.place(IsoProjection.px_to_ground(camera.screen_to_world(pos)))


## Move to a point in milli-tiles, with the chevrons. The units stop attacking and drive there in
## formation; on arrival they fire at enemies within weapon range without moving. The marker shows
## the point as ordered. Near a map edge the sim moves the formation inward by the largest unit
## radius, so the units stop that much off the marker.
func _move(target_x: int, target_y: int) -> void:
	command_sink.call(Command.move(_local_player(), selection.selected, target_x, target_y))
	marker_layer.show_attack_move(IsoProjection.ground_to_px(target_x, target_y))


## `harvest_pick_milli` of the match's rules, how far from a HARVEST's point the sim looks for ore
## (the scenario's rules, or the script defaults when it has none, as the ground layer reads them).
func _harvest_pick_milli() -> int:
	var rules: RulesDef = runner.scenario.rules if runner.scenario != null else null
	return (rules if rules != null else RulesDef.new()).harvest_pick_milli


## Send the selected tankers to the field at a point in milli-tiles, with the same chevrons. The sim
## takes the ore nearest the point; `_ground_tap` has seen to it that there is some in reach.
func _harvest(target_x: int, target_y: int) -> void:
	command_sink.call(Command.harvest(_local_player(), selection.selected, target_x, target_y))
	marker_layer.show_attack_move(IsoProjection.ground_to_px(target_x, target_y))


## The minimap's hold (P88b, ADR 0019 section 4): the MOVE a ground tap sends, with its marker, to
## `ground` (milli-tiles), and the buzz of a long-press. The point is sent and drawn as given, so
## a caller keeps it inside the map (the minimap sends the point its camera jump went to). Only
## own units take it: with nothing or a building selected, or while a strike is aimed or a building
## is placed (nothing is ordered then), it sends nothing. True when it sent the MOVE.
func move_selected_to(ground: Vector2i) -> bool:
	var aiming: bool = strike_aim != null and strike_aim.active
	var placing: bool = placement != null and placement.active
	if aiming or placing or not _units_selected():
		return false
	_move(ground.x, ground.y)
	_buzz()
	return true


## Attack the enemy with id `target`, drawn at `at` on the screen (base px). The sim takes the order
## only if the target is still a valid enemy there. The diamond marks it where it is drawn.
func _attack(target: int, at: Vector2) -> void:
	command_sink.call(Command.attack(_local_player(), selection.selected, target))
	marker_layer.show_target(camera.screen_to_world(at))


func _local_player() -> int:
	return runner.scenario.local_player
