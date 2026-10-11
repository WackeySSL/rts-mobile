class_name GestureRecognizer
extends RefCounted
## Finger events in, GestureEvents out (ADR 0004 section 2). Pure: time arrives as `now_ms` and
## positions are base px. Moving first is a pan, holding first is a box, a tap acts at once.
## One finger is tracked (P7). P8 adds MULTI where touch_down ignores a second finger.

enum State { IDLE, PENDING, PAN, BOX, MULTI }

var _state: int = State.IDLE
var _events: Array[GestureEvent] = []
var _slop_px: float = 0.0
var _long_press_ms: int = 0
var _double_tap_ms: int = 0
var _double_tap_slop_px: float = 0.0

var _index: int = -1  ## The tracked finger.
var _down_pos: Vector2 = Vector2.ZERO
var _down_ms: int = 0
var _pos: Vector2 = Vector2.ZERO  ## Last position of the tracked finger.
var _second_tap: bool = false  ## The press came in time and in range of the last tap.
var _has_last_tap: bool = false
var _last_tap_pos: Vector2 = Vector2.ZERO
var _last_tap_up_ms: int = 0


func _init() -> void:
	configure(InputSettings.new(), 1.0)


## Thresholds only, so it is safe mid-gesture.
func configure(settings: InputSettings, base_px_per_dp: float) -> void:
	_slop_px = settings.tap_slop_dp * base_px_per_dp
	_long_press_ms = settings.long_press_ms
	_double_tap_ms = settings.double_tap_ms
	_double_tap_slop_px = settings.double_tap_slop_dp * base_px_per_dp


func touch_down(index: int, pos: Vector2, now_ms: int) -> void:
	if _state != State.IDLE:
		if index != _index:
			return  # P8: a second finger starts MULTI here.
		_cancel_active()
	# Every press uses up the remembered tap, so a pan in between breaks a double-tap.
	_second_tap = (
		_has_last_tap
		and now_ms - _last_tap_up_ms <= _double_tap_ms
		and pos.distance_to(_last_tap_pos) <= _double_tap_slop_px
	)
	_has_last_tap = false
	_state = State.PENDING
	_index = index
	_down_pos = pos
	_pos = pos
	_down_ms = now_ms


func touch_move(index: int, pos: Vector2, now_ms: int) -> void:
	if _state == State.IDLE or index != _index:
		return
	advance(now_ms)  # A finger that rested 300 ms and then moved is a box, not a pan.
	_move_to(pos)


## A release inside the slop skips advance(): a long hold still taps. Outside it the release
## is a last move, and a move applies the time first.
func touch_up(index: int, pos: Vector2, now_ms: int, canceled: bool = false) -> void:
	if _state == State.IDLE or index != _index:
		return
	if canceled:
		_cancel_active()
		return
	if pos != _pos:
		if pos.distance_to(_down_pos) > _slop_px:
			advance(now_ms)
		_move_to(pos)
	match _state:
		State.PENDING:
			_tap(now_ms)
		State.PAN:
			_emit(GestureEvent.Kind.CAMERA_END)
		State.BOX:
			var rect: Rect2 = _box_rect(_pos)
			if rect.size.x > _slop_px or rect.size.y > _slop_px:
				_emit(GestureEvent.Kind.BOX_END).rect = rect
			else:
				# The finger only rested on the target: a slow tap.
				_emit(GestureEvent.Kind.BOX_CANCEL)
				_tap(now_ms)
	_state = State.IDLE


## Call every frame: the long-press time passes without any finger event.
func advance(now_ms: int) -> void:
	if _state == State.PENDING and now_ms - _down_ms >= _long_press_ms:
		_state = State.BOX
		_second_tap = false
		_emit(GestureEvent.Kind.LONG_PRESS).position = _down_pos


func cancel_all() -> void:
	_cancel_active()
	_has_last_tap = false


## Appends the queued events in order to `out`, clears the queue and returns how many.
func take_events(out: Array[GestureEvent]) -> int:
	var count: int = _events.size()
	out.append_array(_events)
	_events.clear()
	return count


func state() -> int:
	return _state


func _move_to(pos: Vector2) -> void:
	match _state:
		State.PENDING:
			if pos.distance_to(_down_pos) > _slop_px:
				_state = State.PAN
				# The first delta is the whole way from the press: the map stays under the finger.
				_emit(GestureEvent.Kind.PAN).delta = pos - _down_pos
		State.PAN:
			_emit(GestureEvent.Kind.PAN).delta = pos - _pos
		State.BOX:
			_emit(GestureEvent.Kind.BOX_UPDATE).rect = _box_rect(pos)
	_pos = pos


func _tap(now_ms: int) -> void:
	if _second_tap:
		_emit(GestureEvent.Kind.DOUBLE_TAP).position = _down_pos
		return
	_emit(GestureEvent.Kind.TAP).position = _down_pos
	_has_last_tap = true
	_last_tap_pos = _down_pos
	_last_tap_up_ms = now_ms


func _box_rect(to: Vector2) -> Rect2:
	return Rect2(_down_pos, Vector2.ZERO).expand(to)


## Ends the tracked touch without a tap.
func _cancel_active() -> void:
	match _state:
		State.PAN:
			_emit(GestureEvent.Kind.CAMERA_END)
		State.BOX:
			_emit(GestureEvent.Kind.BOX_CANCEL)
	_state = State.IDLE


func _emit(kind: int) -> GestureEvent:
	var event: GestureEvent = GestureEvent.new(kind)
	_events.append(event)
	return event
