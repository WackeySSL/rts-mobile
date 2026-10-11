class_name PlayerController
extends Node
## Turns the selection gestures of TouchInput into selection changes and Commands (ADR 0004
## section 5). It reads the World and the view, and never writes to the sim: an order leaves
## through `command_sink` as an ATTACK_MOVE Command that carries the sorted selection (ADR 0003).
## A tap acts at once. A double-tap on an own unit selects its type on screen, a box selects the
## own units inside it, and an empty box clears the selection (the one way to deselect). Selection
## is not a Command, so it never reaches the sim.

## Emitted with the new `selection.selected` after every real change.
signal selection_changed(ids: PackedInt32Array)

@export var runner: MatchRunner
@export var unit_layer: UnitLayer
@export var camera: RtsCamera
@export var settings: InputSettings

var selection: SelectionModel = SelectionModel.new()
## Receives each Command. Tests replace it.
var command_sink: Callable = CommandQueue.submit

var _snap: PickSnapshot = PickSnapshot.new()
var _found: PackedInt32Array = PackedInt32Array()  ## Scratch for the Picker's box queries.


func _init() -> void:
	selection.changed.connect(_on_selection_changed)


func _ready() -> void:
	if settings == null:
		settings = InputSettings.new()  # The script defaults are the ADR table.


## LONG_PRESS, BOX_UPDATE and BOX_CANCEL change nothing yet; feedback for them comes with P16.
func handle_gesture(e: GestureEvent) -> void:
	match e.kind:
		GestureEvent.Kind.TAP:
			_tap(e.position)
		GestureEvent.Kind.DOUBLE_TAP:
			_double_tap(e.position)
		GestureEvent.Kind.BOX_END:
			_refresh()
			Picker.own_in_rect(_snap, e.rect, _local_player(), _found)
			selection.set_ids(_found)  # No unit in the box: this clears the selection.


func _tap(pos: Vector2) -> void:
	var hit: int = _pick(pos)
	if hit >= 0 and _snap.owners[hit] == _local_player():
		selection.set_ids(PackedInt32Array([_snap.ids[hit]]))
	elif hit >= 0:  # An enemy: only picked while a selection exists. Attack-move to where it is.
		_attack_move(runner.world.pos_x[hit], runner.world.pos_y[hit])
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
	selection.set_ids(_found)


## Refreshes the snapshot and returns the Picker's index for `pos` (a World row), or -1.
func _pick(pos: Vector2) -> int:
	_refresh()
	return Picker.pick(_snap, pos, _local_player(), not selection.selected.is_empty())


func _refresh() -> void:
	unit_layer.fill_pick_snapshot(_snap, UiScale.dp(settings.hit_radius_dp))


func _on_selection_changed() -> void:
	selection_changed.emit(selection.selected)


func _attack_move(target_x: int, target_y: int) -> void:
	command_sink.call(Command.attack_move(_local_player(), selection.selected, target_x, target_y))


func _local_player() -> int:
	return runner.scenario.local_player
