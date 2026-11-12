class_name AttackCues
extends Node
## The attack cue (ADR 0025 section 8, plan P123): the one place that decides an own row was hit
## out of view. It reads the published events only (`SHOT` and `IMPACT` on an own row, and the
## `DIED` of one, which a lethal hit leaves instead) and sends nothing. A hit whose point lies
## outside the camera's visible world rect raises a cue, unless its area (within
## `attack_cue_area_tiles` of an earlier cue's point) had a cue less than `attack_cue_ms` ago: a
## small table of areas, allocated once, remembers them, so two fronts hit in turn raise two cues,
## not a swap on every hit. A hit in the shown cue's own area keeps that cue up, so a steady attack
## shows one cue without a gap. A newer cue replaces the one that shows; a cue lives
## `attack_toast_ms` of frame time. A new match clears everything.
## The toast, the scope's rim wedge and the full map's ping read it; none of them keeps a copy.
## The numbers are `data/input_settings.tres`'s (ADR 0019 section 5).

signal cue_changed  ## A cue was raised, replaced, dismissed or ran out.

const AREAS: int = 4  ## Areas remembered at once, each with the time of its last cue.
const NEVER: float = -1.0e9

@export var runner: MatchRunner
@export var camera: RtsCamera
@export var feed: HudStateFeed  ## Its state's settings give the three numbers.

var active: bool = false
var point: Vector2 = Vector2.ZERO  ## World px (the iso screen space) of the hit.
var title: String = ""  ## "<NAME> UNDER ATTACK", "UNITS UNDER ATTACK" for a unit.

var _left_ms: float = 0.0  ## What the shown cue has left.
var _clock_ms: float = 0.0  ## Frame time since the node entered the tree.
## The table of areas, allocated once: where each cue was raised (milli-tiles) and when.
var _area_x: PackedInt32Array = PackedInt32Array()
var _area_y: PackedInt32Array = PackedInt32Array()
var _area_ms: PackedFloat64Array = PackedFloat64Array()
var _shown_area: int = -1  ## The table entry of the shown cue.
var _serial: int = -1


func _ready() -> void:
	if runner != null:
		runner.ticked.connect(_on_ticked)


func _init() -> void:
	_area_x.resize(AREAS)
	_area_y.resize(AREAS)
	_area_ms.resize(AREAS)
	_forget()


func _process(delta: float) -> void:
	advance(delta * 1000.0)


## A frame of `delta_ms` passed: the clock runs and the shown cue ages.
func advance(delta_ms: float) -> void:
	_clock_ms += delta_ms
	if active:
		_left_ms -= delta_ms
		if _left_ms <= 0.0:
			dismiss()


## The cue clock, ms of frame time.
func clock_ms() -> float:
	return _clock_ms


## What the shown cue has left, ms (0 for none).
func remaining_ms() -> float:
	return maxf(_left_ms, 0.0) if active else 0.0


## Takes the cue away (a tap on the toast, a new match, its time).
func dismiss() -> void:
	_shown_area = -1
	if active:
		active = false
		cue_changed.emit()


## Looks through `snap`'s events for a hit on a row of `player` outside `view` (the camera's visible
## world rect): a SHOT or IMPACT on an own row, or the DIED of one (a row that one hit killed is
## gone from the snapshot). True when it raised a cue.
func scan(snap: MatchSnapshot, player: int, view: Rect2) -> bool:
	if snap.match_serial != _serial:
		_serial = snap.match_serial
		_forget()
		dismiss()
	var raised: bool = false
	var events: PackedInt32Array = snap.events
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		var kind: int = events[at]
		var type: int = -1
		var ground: Vector2i = Vector2i.ZERO
		if kind == World.Event.DIED:
			if events[at + 5] != player or events[at + Production.DIED_CANCEL_FLAG_AT] != 0:
				continue  # Not ours, a cancelled site or a sale (the player's own doing).
			type = events[at + 4]
			ground = Vector2i(events[at + 2], events[at + 3])
		elif kind == World.Event.SHOT or kind == World.Event.IMPACT:
			var row: int = snap.index_of(events[at + 4])  # The hit row; 0 (no target) is none.
			if row < 0 or snap.owner[row] != player:
				continue
			type = snap.type_index[row]
			var shot: bool = kind == World.Event.SHOT
			ground = Vector2i(events[at + (6 if shot else 2)], events[at + (7 if shot else 3)])
		else:
			continue
		if not view.has_point(IsoProjection.ground_to_px(ground.x, ground.y)):
			raised = _note(snap, type, ground) or raised
	return raised


## One hit out of view. In the shown cue's own area it keeps that cue up (a steady attack is one
## cue, with no gap). A repeat in another area that is still within its interval raises nothing;
## anything else raises a cue.
func _note(snap: MatchSnapshot, type: int, ground: Vector2i) -> bool:
	var area: int = _area_of(ground)
	if area >= 0 and active and area == _shown_area:
		_left_ms = float(_settings().attack_toast_ms)
		_area_ms[area] = _clock_ms
		return false
	if area >= 0 and _clock_ms - _area_ms[area] < float(_settings().attack_cue_ms):
		return false
	if area < 0:  # A new area takes a free entry or one whose interval has passed, else nothing.
		for index: int in AREAS:
			if _clock_ms - _area_ms[index] >= float(_settings().attack_cue_ms):
				area = index
				break
		if area < 0:
			return false
	_area_x[area] = ground.x
	_area_y[area] = ground.y
	_area_ms[area] = _clock_ms
	_shown_area = area
	var building: bool = snap.type_foot_w[type] > 0
	title = (snap.type_names[type].to_upper() if building else "UNITS") + " UNDER ATTACK"
	point = IsoProjection.ground_to_px(ground.x, ground.y)
	active = true
	_left_ms = float(_settings().attack_toast_ms)
	cue_changed.emit()
	return true


## The table entry whose centre `ground` is within `attack_cue_area_tiles` of (strictly), else -1.
func _area_of(ground: Vector2i) -> int:
	var reach: int = _settings().attack_cue_area_tiles * World.MILLI_PER_TILE
	for index: int in AREAS:
		var dx: int = ground.x - _area_x[index]
		var dy: int = ground.y - _area_y[index]
		if _area_ms[index] > NEVER and dx * dx + dy * dy < reach * reach:
			return index
	return -1


func _forget() -> void:
	_area_ms.fill(NEVER)


func _on_ticked(_tick: int) -> void:
	var snap: MatchSnapshot = runner.snapshot
	if snap != null and camera != null:
		scan(snap, FogLayer.local_player_of(runner), camera.visible_world_rect())


func _settings() -> InputSettings:
	return InputSettings.new() if feed == null else feed.state.settings
