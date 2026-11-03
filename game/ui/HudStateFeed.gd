class_name HudStateFeed
extends Node
## Owns the HUD's `HudState` and tells it what the screen does (ADR 0025 section 1, plan P119c):
## the parts that show an unfold read `feed.state`, nothing else holds it. It is the one Node the
## state needs, for frames and for fingers; it sends no Command and keeps nothing of the match.
## - A gesture on the map: `TouchInput.map_gesture`, the signal the build menu already folds on.
##   TouchInput never hears a press the GUI took, so a touch on a HUD control is not told there.
## - A finger down anywhere: a press seen in `_input`, before the GUI and before TouchInput, marks
##   nothing handled and so changes what no one else hears. It closes only the economy card. The
##   feed counts the fingers down (a release, lost or not, of any finger ends it; a focus loss ends
##   all) so that the state knows the first one.
## - A frame: the full map's timer (`HudState.advance`), in frame time.
## - Placement or a strike aim that begins (`PlacementController.active`, `StrikeAim.active` turning
##   true). Only the start folds: their later `changed`s (a ghost re-judged) and their end do not.
## - A new match: another `match_serial` in the published snapshot resets the state. A new main
##   scene starts with a fresh state anyway; `MatchRunner.start()` in the same scene is this case.
## A turn of the phone is no event here: the state is kept. The pause menu (P124) opens `PAUSE`
## through `state`; while it is open every touch is its own.

@export var settings: InputSettings  ## None: the script defaults (the file's table).
@export var touch_input: TouchInput
@export var runner: MatchRunner
@export var placement: PlacementController
@export var strike_aim: StrikeAim

## The state of the HUD. Made with the node, not in `_ready`, so a part that is ready before this
## node still finds it; read-only, so that nothing replaces the object the signals are wired to.
var state: HudState:
	get:
		return _state
	set(_value):
		assert(false, "HudStateFeed.state is read-only: the signals are wired to its object.")

var _state: HudState = HudState.new()
var _fingers: Dictionary[int, bool] = {}  ## The fingers down, by index. The values are unused.
var _serial: int = -1  ## match_serial of the snapshot last seen.
var _placing: bool = false  ## Placement was on at the last `placement.changed`.
var _aiming: bool = false  ## The strike aim was on at the last `strike_aim.changed`.


func _ready() -> void:
	if settings != null:
		_state.settings = settings
	_serial = _snapshot_serial()
	if touch_input != null:
		touch_input.map_gesture.connect(_state.map_gesture)
	if placement != null:
		placement.changed.connect(_on_placement_changed)
	if strike_aim != null:
		strike_aim.changed.connect(_on_aim_changed)


## Every finger that goes down, on the map or on a control. The event goes on unhandled. A press
## for a finger still down means its release was lost: it is a new touch.
func _input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch == null:
		return
	_fingers.erase(touch.index)
	if touch.pressed:
		_state.touch_down(_fingers.is_empty())
		_fingers[touch.index] = true


func _notification(what: int) -> void:
	# A finger that was down when the app lost focus may never send its release.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_fingers.clear()


func _process(delta: float) -> void:
	var serial: int = _snapshot_serial()
	if serial >= 0 and serial != _serial:
		_serial = serial
		_state.reset()
	_state.advance(delta * 1000.0)


func _snapshot_serial() -> int:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	return -1 if snap == null else snap.match_serial


func _on_placement_changed() -> void:
	if placement.active and not _placing:
		_state.mode_started()
	_placing = placement.active


func _on_aim_changed() -> void:
	if strike_aim.active and not _aiming:
		_state.mode_started()
	_aiming = strike_aim.active
