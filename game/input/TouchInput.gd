class_name TouchInput
extends Node
## The engine adapter for fingers (ADR 0004 section 1). It feeds a pure GestureRecognizer and
## routes each GestureEvent at once: PAN, PINCH and CAMERA_END drive the RtsCamera. TAP, DOUBLE_TAP,
## LONG_PRESS and BOX_* go to the PlayerController (none set: dropped), and LONG_PRESS also buzzes.
## A press the GUI did not take reaches `_unhandled_input` and belongs to the recognizer. Its drags
## and release are taken in `_input` and marked handled, so a pan that crosses a HUD button keeps
## panning and never presses it. A touch that starts on a Control stays with it. Mouse buttons and
## motion are ignored (desktop clicks arrive as emulated touches); only the wheel steps the zoom.
## A turn of the phone cancels every gesture in flight (ADR 0015 section 3): the finger positions
## belong to the old layout. A box is cancelled for the controller, the camera never hears the end
## of a pan or pinch (it would snap the zoom about a stale anchor), and no tap is made.

@export var settings: InputSettings
@export var camera: RtsCamera
@export var controller: PlayerController

## Returns the time in ms. Tests replace it.
var clock: Callable = Time.get_ticks_msec
## Vibrates for the given ms. Tests replace it.
var vibrate: Callable = Input.vibrate_handheld

var _recognizer: GestureRecognizer = GestureRecognizer.new()
var _portrait: bool = false  ## The window's orientation at the last size_changed.
var _events: Array[GestureEvent] = []
## Fingers that started on the map and are still down. The values are unused.
var _owned: Dictionary[int, bool] = {}


func _ready() -> void:
	if settings == null:
		settings = InputSettings.new()  # The script defaults are the ADR table.
	_portrait = UiScale.is_portrait_size(get_tree().root.size)
	get_viewport().size_changed.connect(_on_size_changed)
	configure()


## Reads the thresholds again: dp is a different number of base px after a resize.
func configure() -> void:
	_recognizer.configure(settings, UiScale.base_px_per_dp())


## Every resize reads the thresholds again, and a turn (another orientation than at the last
## resize) ends the gestures. The first run of a flip's two sees the turn, the second finds the
## orientation in place and changes nothing, whatever the order of the handlers.
func _on_size_changed() -> void:
	configure()
	var portrait: bool = UiScale.is_portrait_size(get_tree().root.size)
	if portrait == _portrait:
		return
	_portrait = portrait
	_recognizer.cancel_all()
	if _recognizer.take_events(_events) == 0:
		return
	for e: GestureEvent in _events:
		if e.kind != GestureEvent.Kind.CAMERA_END:  # Its snap would undo the camera's turn rule.
			_route(e)
	_events.clear()


func _process(_delta: float) -> void:
	_recognizer.advance(clock.call())  # A long-press arrives while the finger rests.
	_dispatch()


func _notification(what: int) -> void:
	# A finger that was down when the app lost focus may never send its release.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_owned.clear()
		_recognizer.cancel_all()
		_dispatch()


## Runs before the GUI, so a release is never missed and a pan drag never reaches a Control.
func _input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if touch != null and _owned.erase(touch.index):
		# A press for a finger still down: its release was lost. End it, the press goes on.
		_recognizer.touch_up(
			touch.index, touch.position, clock.call(), touch.canceled or touch.pressed
		)
	elif drag != null and _owned.has(drag.index):
		_recognizer.touch_move(drag.index, drag.position, clock.call())
	else:
		return
	_dispatch()
	if touch == null or not touch.pressed:
		get_viewport().set_input_as_handled()


## Only presses the GUI did not take get here.
func _unhandled_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var wheel: InputEventMouseButton = event as InputEventMouseButton
	if touch != null and touch.pressed:
		_owned[touch.index] = true
		_recognizer.touch_down(touch.index, touch.position, clock.call())
		_dispatch()
	elif wheel != null and wheel.pressed:
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.step_zoom(1, wheel.position)
		elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.step_zoom(-1, wheel.position)


func _dispatch() -> void:
	if _recognizer.take_events(_events) == 0:
		return
	for e: GestureEvent in _events:
		_route(e)
	_events.clear()


func _route(e: GestureEvent) -> void:
	match e.kind:
		GestureEvent.Kind.PAN:
			camera.pan_by_screen(e.delta)
		GestureEvent.Kind.PINCH:
			# Two fingers moving in one frame give two events whose scales multiply.
			camera.pan_by_screen(e.delta)
			camera.pinch(e.centre, e.scale)
		GestureEvent.Kind.CAMERA_END:
			camera.end_gesture()
		GestureEvent.Kind.LONG_PRESS:
			if settings.haptics_enabled:
				vibrate.call(settings.haptic_ms)
			_to_controller(e)
		_:  # TAP, DOUBLE_TAP and BOX_*.
			_to_controller(e)


func _to_controller(e: GestureEvent) -> void:
	if controller != null:
		controller.handle_gesture(e)
