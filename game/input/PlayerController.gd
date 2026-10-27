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
## clears the selection (the one way to deselect). Selection is not a Command, so it never reaches
## the sim. A unit that dies leaves the selection and the groups at once, inside `runner.ticked`,
## and the rings, the panel and the badges follow.
## A building (P115b, ADR 0019 section 3, ADR 0023 section 3) is picked after the units, on its
## silhouette (`Picker.pick_building`): a tap on an own or a shown enemy building selects it alone
## (an enemy one for its info only: it gets no order), the frame, the panel and the sidebar's tab
## follow `selection_changed`. A building never joins a box, a double-tap or "All army". With own
## units selected a tap on an enemy building attacks it, if the sim would take that attack
## (`PickSnapshot.is_targetable`: the view draws an enemy building for any seen cell of its
## footprint, the sim sees it at the cell under its position) and is a ground tap if not; with a
## building selected a tap on the ground, or on an enemy unit, selects nothing and orders nothing.
## Each order shows its marker and the BoxOverlay follows a long-press and its box, both in the
## frame of the gesture. The selection rings follow `selection_changed` (wired in the scene).

## Emitted with the new `selection.selected` after every real change, and again when a tap lands on
## the one building that is selected already: the sidebar goes back to the tab it builds.
signal selection_changed(ids: PackedInt32Array)

@export var runner: MatchRunner
@export var unit_layer: UnitLayer
@export var building_layer: BuildingLayer  ## Without one no building can be picked.
@export var camera: RtsCamera
@export var settings: InputSettings
@export var marker_layer: MoveMarkerLayer
@export var box_overlay: BoxOverlay
@export var army_bar: ArmyBar

var selection: SelectionModel = SelectionModel.new()
## Receives each Command. Tests replace it.
var command_sink: Callable = CommandQueue.submit
## Buzzes for the given ms when a group is assigned. Tests replace it.
var vibrate: Callable = Input.vibrate_handheld

var _snap: PickSnapshot = PickSnapshot.new()
var _found: PackedInt32Array = PackedInt32Array()  ## Scratch for the Picker's box queries.
var _dead: PackedInt32Array = PackedInt32Array()  ## Scratch for the ids a tick's events name.


func _init() -> void:
	selection.changed.connect(_on_selection_changed)


func _ready() -> void:
	if settings == null:
		settings = InputSettings.new()  # The script defaults are the ADR table.
	if runner != null:
		runner.ticked.connect(_on_ticked)
	if army_bar != null:
		army_bar.all_army_pressed.connect(select_all_army)
		army_bar.group_tapped.connect(tap_group)
		army_bar.group_assign_requested.connect(assign_group)


func handle_gesture(e: GestureEvent) -> void:
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
			selection.set_ids(_found)  # No unit in the box: this clears the selection.


## "All army": every own unit that can move, wherever it is (ADR 0004 section 5).
func select_all_army() -> void:
	var snap: MatchSnapshot = runner.snapshot
	if snap == null:
		return
	var local_player: int = _local_player()
	var unit_ids: PackedInt32Array = snap.unit_id
	var owners: PackedInt32Array = snap.owner
	var types: PackedInt32Array = snap.type_index
	var speeds: PackedInt32Array = snap.type_speed
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in unit_ids.size():
		if owners[row] == local_player and speeds[types[row]] > 0:
			ids.append(unit_ids[row])
	selection.set_ids(ids)


func tap_group(slot: int) -> void:
	selection.recall_group(slot)


## Stores the selection in group `slot`, shows the count and buzzes.
func assign_group(slot: int) -> void:
	selection.assign_group(slot)
	_show_group_count(slot)
	if settings.haptics_enabled:
		vibrate.call(settings.haptic_ms)


func _tap(pos: Vector2) -> void:
	var units: bool = _units_selected()
	var hit: int = _pick(pos, units)
	if hit >= 0 and _snap.owners[hit] == _local_player():
		selection.set_ids(PackedInt32Array([_snap.ids[hit]]))
	elif hit >= 0:  # An enemy: only picked while own units are selected.
		_attack(_snap.ids[hit], _snap.screen_pos[hit])
	else:
		var min_half: float = UiScale.dp(settings.hit_radius_dp)
		var shape: int = Picker.pick_building(_snap, pos, _local_player(), units, min_half)
		var hostile: bool = shape >= 0 and units and _snap.building_owners[shape] != _local_player()
		if hostile and _snap.is_targetable(shape):
			_attack(_snap.building_ids[shape], _snap.building_centres[shape])
		elif shape >= 0 and not hostile:
			_select_building(_snap.building_ids[shape])
		elif units:
			var ground: Vector2i = IsoProjection.px_to_ground(camera.screen_to_world(pos))
			_move(ground.x, ground.y)
		else:
			selection.clear()  # A building was selected: a tap on the ground lets go of it.


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
	var snap: MatchSnapshot = runner.snapshot
	var row: int = -1 if snap == null else snap.index_of(selection.selected[0])
	return row < 0 or not WorldSort.is_building(snap, snap.type_index[row])


func _on_selection_changed() -> void:
	selection_changed.emit(selection.selected)


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
	for slot: int in range(1, SelectionModel.GROUP_COUNT + 1):
		_show_group_count(slot)


func _show_group_count(slot: int) -> void:
	if army_bar != null:
		army_bar.set_group_count(slot, selection.group(slot).size())


## Move to a point in milli-tiles, with the chevrons. The units stop attacking and drive there in
## formation; on arrival they fire at enemies within weapon range without moving. The marker shows
## the point as ordered. Near a map edge the sim moves the formation inward by the largest unit
## radius, so the units stop that much off the marker.
func _move(target_x: int, target_y: int) -> void:
	command_sink.call(Command.move(_local_player(), selection.selected, target_x, target_y))
	marker_layer.show_attack_move(IsoProjection.ground_to_px(target_x, target_y))


## Attack the enemy with id `target`, drawn at `at` on the screen (base px). The sim takes the order
## only if the target is still a valid enemy there. The diamond marks it where it is drawn.
func _attack(target: int, at: Vector2) -> void:
	command_sink.call(Command.attack(_local_player(), selection.selected, target))
	marker_layer.show_target(camera.screen_to_world(at))


func _local_player() -> int:
	return runner.scenario.local_player
