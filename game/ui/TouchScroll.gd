class_name TouchScroll
extends ScrollContainer
## A ScrollContainer a finger can drag (plan P672b). The project keeps `emulate_mouse_from_touch`
## off, because the match's gesture layer reads raw touch, so the stock container, which scrolls
## only from the mouse, never moves under a finger. This one reads `InputEventScreenTouch` and
## `InputEventScreenDrag` itself, before the controls under the finger see them:
## - a finger that moves past `InputSettings.tap_slop_dp`, more up or down than sideways, scrolls
##   the page with it; a mostly sideways move is left alone (a slider on the page keeps it);
## - a short tap is not touched, so the button under the finger presses as before;
## - once a drag scrolls, the rest of that touch (its moves and its release) is taken, so the
##   button the finger started on does not press, and the control that had the press lets go;
## - on release a fling carries on and fades out (`FLING_DECAY_PER_S`, frame-rate independent).
## Vertical only. A page that fits (nothing to scroll) is left alone, and so is a touch that starts
## outside the container or while it is hidden.

## A fling's speed falls by this share each second (`exp(-k * delta)`), and ends below the floor.
const FLING_DECAY_PER_S: float = 4.0
const FLING_FLOOR_PX_PER_S: float = 30.0
## A release slower than this (px/s) starts no fling.
const FLING_START_PX_PER_S: float = 200.0

var slop_dp: float = InputSettings.new().tap_slop_dp  ## `InputSettings.tap_slop_dp`.

var _finger: int = -1  ## The touch index being followed, -1 for none.
var _from: Vector2
var _scrolling: bool = false
var _velocity: float = 0.0  ## px/s the content moves, from the finger's last drag.
var _fling: float = 0.0  ## px/s of the fling in flight.
var _carry: float = 0.0  ## Sub-pixel remainder of the scroll, so slow drags are not lost.


func _ready() -> void:
	set_process(false)


func _input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if touch != null:
		if touch.canceled:
			_end(false)
		elif touch.pressed:
			_press(touch)
		elif touch.index == _finger:
			var took: bool = _scrolling
			_end(true)
			if took:
				get_viewport().set_input_as_handled()
	elif drag != null and drag.index == _finger:
		_move(drag)


func _process(delta: float) -> void:
	_fling *= exp(-FLING_DECAY_PER_S * delta)
	if absf(_fling) < FLING_FLOOR_PX_PER_S or not _can_scroll():
		_fling = 0.0
		set_process(false)
		return
	_scroll_by(_fling * delta)


func _press(touch: InputEventScreenTouch) -> void:
	_fling = 0.0
	set_process(false)
	if _finger != -1 or not is_visible_in_tree() or not _can_scroll():
		return
	if not get_global_rect().has_point(touch.position):
		return
	_finger = touch.index
	_from = touch.position
	_scrolling = false
	_velocity = 0.0
	_carry = 0.0


func _move(drag: InputEventScreenDrag) -> void:
	if not _scrolling:
		var moved: Vector2 = drag.position - _from
		if moved.length() <= UiScale.dp(slop_dp):
			return
		if absf(moved.y) < absf(moved.x):  # Sideways: not ours (a slider, a swipe).
			_finger = -1
			return
		_scrolling = true
		_let_go_of_press()
		_scroll_by(-moved.y)  # All the finger has moved since the press.
	else:
		_scroll_by(-drag.relative.y)
	_velocity = -drag.velocity.y
	get_viewport().set_input_as_handled()


func _end(released: bool) -> void:
	if released and _scrolling and absf(_velocity) >= FLING_START_PX_PER_S:
		_fling = _velocity
		set_process(true)
	_finger = -1
	_scrolling = false


## The control the press went to (a button) drops its pressed state, so it does not fire on a
## release that never reaches it and does not stay drawn as held.
func _let_go_of_press() -> void:
	var owner_of_focus: Control = get_viewport().gui_get_focus_owner()
	if owner_of_focus != null and is_ancestor_of(owner_of_focus):
		owner_of_focus.release_focus()


func _can_scroll() -> bool:
	if vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
		return false
	var bar: VScrollBar = get_v_scroll_bar()
	return bar.max_value - bar.page > 0.5


func _scroll_by(pixels: float) -> void:
	_carry += pixels
	var whole: int = int(_carry)  # Truncates toward 0.
	_carry -= whole
	scroll_vertical += whole
