class_name PlayerController
extends Node
## Turns the selection gestures of TouchInput into selection changes and Commands (ADR 0004
## section 5). It reads the view and the published snapshot (ADR 0012 section 3), afresh at each
## call and never kept (the enemy tap still reads the World for the target's position), and never
## writes to the sim: an order leaves through `command_sink` as an ATTACK_MOVE Command that carries
## the sorted selection (ADR 0003).
## A tap acts at once. A double-tap on an own unit selects its type on screen, a box selects the
## own units inside it, and an empty box clears the selection (the one way to deselect). Selection
## is not a Command, so it never reaches the sim. A unit that dies leaves the selection and the
## groups at once, inside `runner.ticked`, and the rings, the panel and the badges follow.
## Each order shows its marker and the BoxOverlay follows a long-press and its box, both in the
## frame of the gesture. The selection rings follow `selection_changed` (wired in the scene).

## Emitted with the new `selection.selected` after every real change.
signal selection_changed(ids: PackedInt32Array)

@export var runner: MatchRunner
@export var unit_layer: UnitLayer
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
	var hit: int = _pick(pos)
	if hit >= 0 and _snap.owners[hit] == _local_player():
		selection.set_ids(PackedInt32Array([_snap.ids[hit]]))
	elif hit >= 0:  # An enemy: only picked while a selection exists. Attack-move to where it is.
		_attack_move(runner.world.pos_x[hit], runner.world.pos_y[hit], true)
	elif not selection.selected.is_empty():
		var world_px: Vector2 = camera.screen_to_world(pos)
		_attack_move(ViewScale.px_to_milli(world_px.x), ViewScale.px_to_milli(world_px.y))


func _double_tap(pos: Vector2) -> void:
	var hit: int = _pick(pos)
	if hit < 0 or _snap.owners[hit] != _local_player():
		_tap(pos)  # Anywhere but on an own unit it is a plain tap.
		return
	var on_screen: Rect2 = get_viewport().get_visible_rect()
	Picker.own_of_type_in_rect(_snap, _snap.type_index[hit], on_screen, _local_player(), _found)
	_found.append(_snap.ids[hit])  # The tapped unit counts, even with its centre off screen.
	selection.set_ids(_found)


## Refreshes the snapshot and returns the Picker's index for `pos` (a World row), or -1.
func _pick(pos: Vector2) -> int:
	_refresh()
	return Picker.pick(_snap, pos, _local_player(), not selection.selected.is_empty())


func _refresh() -> void:
	unit_layer.fill_pick_snapshot(_snap, UiScale.dp(settings.hit_radius_dp))


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


## Attack-move to a point in milli-tiles, with its marker: the diamond on an enemy, else chevrons.
## The marker shows the point as ordered. Near a map edge the sim moves the formation inward by the
## largest unit radius, so the units stop that much off the marker.
func _attack_move(target_x: int, target_y: int, on_enemy: bool = false) -> void:
	command_sink.call(Command.attack_move(_local_player(), selection.selected, target_x, target_y))
	var at: Vector2 = ViewScale.milli_to_px_vec(target_x, target_y)
	if on_enemy:
		marker_layer.show_target(at)
	else:
		marker_layer.show_attack_move(at)


func _local_player() -> int:
	return runner.scenario.local_player
