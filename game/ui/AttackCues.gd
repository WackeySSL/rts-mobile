class_name AttackCues
extends Node
## The attack cue (ADR 0025 section 8, plan P123): the one place that decides an own row was hit
## out of view. It reads the published events only (`SHOT` and `IMPACT`, each tick) and sends
## nothing. A hit on a row of the local player whose point lies outside the camera's visible world
## rect raises a cue, unless the last cue was less than `attack_cue_ms` ago and within
## `attack_cue_area_tiles` of this point (both in `data/input_settings.tres`): a steady attack keeps
## one cue up. A newer cue replaces the one that shows. A cue lives `attack_toast_ms` of frame
## time.
## The toast, the scope's rim wedge and the full map's ping read it; none of them keeps a copy. One
## cue is kept, so nothing is allocated per hit but the text of a new cue. A new match clears it.

signal cue_changed  ## A cue was raised, replaced, dismissed or ran out.

@export var runner: MatchRunner
@export var camera: RtsCamera
@export var feed: HudStateFeed  ## Its state's settings give the three numbers.

var active: bool = false
var point: Vector2 = Vector2.ZERO  ## World px (the iso screen space) of the hit.
var title: String = ""  ## "<NAME> UNDER ATTACK", "UNITS UNDER ATTACK" for a unit.

var _left_ms: float = 0.0  ## What the shown cue has left.
var _clock_ms: float = 0.0  ## Frame time since the node entered the tree.
var _last_ms: float = -1.0e9  ## When the last cue was raised, and where (milli-tiles).
var _last_ground: Vector2i = Vector2i.ZERO
var _serial: int = -1


func _ready() -> void:
	if runner != null:
		runner.ticked.connect(_on_ticked)


func _process(delta: float) -> void:
	advance(delta * 1000.0)


## A frame of `delta_ms` passed: the clock runs and the shown cue ages.
func advance(delta_ms: float) -> void:
	_clock_ms += delta_ms
	if active:
		_left_ms -= delta_ms
		if _left_ms <= 0.0:
			dismiss()


## Takes the cue away (a tap on the toast, a new match, its time).
func dismiss() -> void:
	if active:
		active = false
		cue_changed.emit()


## Looks through `snap`'s events for a hit on a row of `player` outside `view` (the camera's visible
## world rect). True when it raised a cue.
func scan(snap: MatchSnapshot, player: int, view: Rect2) -> bool:
	if snap.match_serial != _serial:
		_serial = snap.match_serial
		_last_ms = -1.0e9
		dismiss()
	var raised: bool = false
	var events: PackedInt32Array = snap.events
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		var kind: int = events[at]
		if kind != World.Event.SHOT and kind != World.Event.IMPACT:
			continue
		var row: int = snap.index_of(events[at + 4])  # The hit row; 0 (no target) is none.
		if row < 0 or snap.owner[row] != player:
			continue
		var shot: bool = kind == World.Event.SHOT
		var ground: Vector2i = Vector2i(
			events[at + (6 if shot else 2)], events[at + (7 if shot else 3)]
		)
		var px: Vector2 = IsoProjection.ground_to_px(ground.x, ground.y)
		if view.has_point(px) or _is_repeat(ground):
			continue
		_raise(snap, row, ground, px)
		raised = true
	return raised


## Whether `ground` is the area of the last cue within its interval.
func _is_repeat(ground: Vector2i) -> bool:
	if _clock_ms - _last_ms >= float(_settings().attack_cue_ms):
		return false
	var reach: int = _settings().attack_cue_area_tiles * World.MILLI_PER_TILE
	var offset: Vector2i = ground - _last_ground
	return int(offset.x) * offset.x + int(offset.y) * offset.y < reach * reach


func _raise(snap: MatchSnapshot, row: int, ground: Vector2i, px: Vector2) -> void:
	var type: int = snap.type_index[row]
	var building: bool = snap.type_foot_w[type] > 0
	title = (snap.type_names[type].to_upper() if building else "UNITS") + " UNDER ATTACK"
	point = px
	active = true
	_left_ms = float(_settings().attack_toast_ms)
	_last_ms = _clock_ms
	_last_ground = ground
	cue_changed.emit()


func _on_ticked(_tick: int) -> void:
	var snap: MatchSnapshot = runner.snapshot
	if snap != null and camera != null:
		scan(snap, FogLayer.local_player_of(runner), camera.visible_world_rect())


func _settings() -> InputSettings:
	return InputSettings.new() if feed == null else feed.state.settings
