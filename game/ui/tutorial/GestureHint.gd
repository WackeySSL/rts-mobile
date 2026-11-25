class_name GestureHint
extends Control
## The tutorial's gesture hint (plan row P590, ADR 0048 section 6): a hand glyph that plays one
## gesture in a loop at the centre of this control. Standalone; the coach mark wires it in P592.
##
## `pose(kind, t_ms, timing)` is the motion: it writes the fingertips (dp offsets from the point),
## whether they press, the press ring's progress and the opacity into ONE reused `Pose`, so a frame
## allocates nothing. The hold lasts `long_press_ms` plus `hint_hold_extra_ms` and the gap of a
## double tap is half of `double_tap_ms`, so the hint never teaches a timing the game would refuse.
## `AUTO` and `NONE` are the caller's to resolve (P592): they show nothing here.
## Reduced effects: `key_pose` is a still hand with arrows (answer 5); no motion, no Tween.
##
## Input: the node is `MOUSE_FILTER_IGNORE` and `_input` only reads. While any touch is down, and
## for `hint_idle_ms` after the last release, the hint is not drawn: a fake finger never moves
## while a real one does. The clock is the sum of the frames' deltas (`advance` steps it by hand).
## One texture (the point or the pinch hand); the press ring, the arrows and the box are drawn in
## code. Colours come from the theme's `GuideTokens` (`hint_fill`, `hint_line`).

const POINT_TEXTURE: Texture2D = preload("res://assets/art/svg/ui/guide_hand_point.svg")
const PINCH_TEXTURE: Texture2D = preload("res://assets/art/svg/ui/guide_hand_pinch.svg")
## The fingertip in the point art (x 87 y 14 of 216) and the midpoint of the two fingertips in the
## pinch art (x 70 y 124 of 216), as shares of the glyph's side.
const POINT_TIP: Vector2 = Vector2(87.0, 14.0) / 216.0
const PINCH_TIP: Vector2 = Vector2(70.0, 124.0) / 216.0
const FADE_MS: int = 120  ## Fade in at the start of a loop and out at its end.
const RING_RADIUS_SHARE: float = 0.4  ## Of `hint_size_dp`, at full progress.
const SPREAD_NEAR_SHARE: float = 0.3  ## Half the pinch's finger gap, of `hint_size_dp`.
const SPREAD_FAR_SHARE: float = 1.2
const PINCH_AXIS: Vector2 = Vector2(-0.70710678, 0.70710678)  ## The fingers move along this.
const DEFAULT_DRAG_DP: Vector2 = Vector2(-160.0, 0.0)  ## The pan: 160 dp to the left.
const ARROW_HEAD_DP: float = 10.0
const LINE_DP: float = 3.0
const MOUSE_ID: int = -1


## One frame of the motion. Offsets are dp from the point the hint stands at.
class Pose:
	extends RefCounted
	var finger_a: Vector2 = Vector2.ZERO  ## The one fingertip, or the first of a pinch.
	var finger_b: Vector2 = Vector2.ZERO  ## The second fingertip of a pinch.
	var two_fingers: bool = false
	var pressed: bool = false
	var press_progress: float = 0.0  ## 0 to 1 of the press ring.
	var rings: int = 1  ## Rings of the press: 2 for the double tap's key pose.
	var alpha: float = 0.0


## The numbers of the motion, in ms and dp: the guide settings and the input settings joined.
class Timing:
	extends RefCounted
	var cycle_ms: int = 0
	var rest_ms: int = 0
	var tap_ms: int = 0
	var drag_ms: int = 0
	var pinch_ms: int = 0
	var hold_ms: int = 0  ## `long_press_ms` plus `hint_hold_extra_ms`.
	var gap_ms: int = 0  ## Between a double tap's two presses, inside `double_tap_ms`.
	var size_dp: float = 0.0
	var vector_dp: Vector2 = DEFAULT_DRAG_DP  ## The drag's and the box's diagonal.

	func load_from(guide: GuideSettingsDef, input: InputSettings) -> Timing:
		cycle_ms = guide.hint_cycle_ms
		rest_ms = guide.hint_rest_ms
		tap_ms = maxi(1, guide.hint_tap_ms)  # No length is 0: a share never divides by it.
		drag_ms = maxi(1, guide.hint_drag_ms)
		pinch_ms = maxi(1, guide.hint_pinch_ms)
		hold_ms = maxi(1, input.long_press_ms + guide.hint_hold_extra_ms)
		gap_ms = input.double_tap_ms / 2
		size_dp = guide.hint_size_dp
		return self

	## How long the gesture itself takes, before the rest.
	func active_ms(kind: TutorialBeatDef.Gesture) -> int:
		match kind:
			TutorialBeatDef.Gesture.DOUBLE_TAP:
				return tap_ms * 2 + gap_ms
			TutorialBeatDef.Gesture.LONG_PRESS:
				return hold_ms
			TutorialBeatDef.Gesture.DRAG:
				return drag_ms
			TutorialBeatDef.Gesture.BOX:
				return hold_ms + drag_ms
			TutorialBeatDef.Gesture.PINCH_OUT, TutorialBeatDef.Gesture.PINCH_IN:
				return pinch_ms
		return tap_ms

	## One loop: `cycle_ms`, or longer when the gesture and the rest do not fit in it.
	func period_ms(kind: TutorialBeatDef.Gesture) -> int:
		return maxi(1, maxi(cycle_ms, active_ms(kind) + rest_ms))


var settings: GuideSettingsDef = preload("res://data/tutorial/guide_settings.tres"):
	set(value):
		settings = value
		_reload()
var input_settings: InputSettings = preload("res://data/input_settings.tres"):
	set(value):
		input_settings = value
		_reload()
## Reduced effects: the still key pose. `_ready` adds the player switch; tests may set it.
var reduced: bool = false:
	set(value):
		reduced = value
		queue_redraw()
var kind: TutorialBeatDef.Gesture = TutorialBeatDef.Gesture.TAP:
	set(value):
		kind = value
		queue_redraw()
## The drag's and the box's diagonal in dp (`TutorialBeatDef.gesture_vector_dp`).
var vector_dp: Vector2 = DEFAULT_DRAG_DP:
	set(value):
		vector_dp = value
		_timing.vector_dp = value
		queue_redraw()

var _timing: Timing = Timing.new()
var _pose: Pose = Pose.new()
var _clock: float = 0.0  ## ms, summed as a float so rounded frames do not drift.
var _loop_ms: int = 0  ## The clock at the start of this showing.
var _down: Dictionary = {}  ## Touch index -> true, while that finger is down.
var _last_release_ms: int = -1  ## -1: no touch yet.
var _was_hidden: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	reduced = reduced or MenuPrefs.reduced_effects()
	_reload()


func _process(delta: float) -> void:
	advance(delta * 1000.0)


## Steps the clock. Redraws every frame while the hand moves; with reduced effects only when it
## hides or shows again.
func advance(delta_ms: float) -> void:
	_clock += delta_ms
	var hidden: bool = touched_hidden()
	if hidden != _was_hidden or (not hidden and not reduced):
		queue_redraw()
	_was_hidden = hidden


## The clock in whole ms.
func now_ms() -> int:
	return int(_clock)


## Starts the loop at its beginning (a new beat).
func restart() -> void:
	_loop_ms = now_ms()
	queue_redraw()


## True while a touch is down and for `hint_idle_ms` after the last release.
func touched_hidden() -> bool:
	if not _down.is_empty():
		return true
	return _last_release_ms >= 0 and now_ms() - _last_release_ms < settings.hint_idle_ms


## Only reads: never `set_input_as_handled`, never accepts.
func _input(event: InputEvent) -> void:
	var index: int = MOUSE_ID
	var pressed: bool = false
	if event is InputEventScreenTouch:
		index = (event as InputEventScreenTouch).index
		pressed = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		# Only the left button is a touch: a wheel notch (the web preview's zoom) is not.
		if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
			return
		pressed = (event as InputEventMouseButton).pressed
	else:
		return
	if pressed:
		_down[index] = true
	elif _down.erase(index):
		_last_release_ms = now_ms()
	_refresh_hidden()


## A lost focus never delivers the release: the fingers that were down are let go.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if not _down.is_empty():
			_down.clear()
			_last_release_ms = now_ms()
			_refresh_hidden()


func _refresh_hidden() -> void:
	var hidden: bool = touched_hidden()
	if hidden != _was_hidden:
		_was_hidden = hidden
		queue_redraw()


## The frame at `t_ms` into the loop of `for_kind`, written into the one reused `Pose`.
func pose(for_kind: TutorialBeatDef.Gesture, t_ms: int, timing: Timing) -> Pose:
	var p: Pose = _pose
	p.two_fingers = (
		for_kind == TutorialBeatDef.Gesture.PINCH_OUT
		or for_kind == TutorialBeatDef.Gesture.PINCH_IN
	)
	p.rings = 1
	p.finger_a = Vector2.ZERO
	p.finger_b = Vector2.ZERO
	p.pressed = false
	p.press_progress = 0.0
	p.alpha = 0.0
	if for_kind == TutorialBeatDef.Gesture.AUTO or for_kind == TutorialBeatDef.Gesture.NONE:
		return p
	var period: int = timing.period_ms(for_kind)
	var phase: int = posmod(t_ms, period)
	var active: int = timing.active_ms(for_kind)
	var run: int = mini(phase, active)
	p.alpha = clampf(float(mini(phase, period - phase)) / float(FADE_MS), 0.0, 1.0)
	match for_kind:
		TutorialBeatDef.Gesture.TAP:
			_press(p, run, timing.tap_ms, phase < active)
		TutorialBeatDef.Gesture.DOUBLE_TAP:
			var second: int = timing.tap_ms + timing.gap_ms
			if phase >= second:
				_press(p, phase - second, timing.tap_ms, phase < active)
			else:
				_press(p, phase, timing.tap_ms, phase < timing.tap_ms)
		TutorialBeatDef.Gesture.LONG_PRESS:
			_press(p, run, timing.hold_ms, phase < active)
		TutorialBeatDef.Gesture.DRAG:
			_press(p, run, active, phase < active)
			p.finger_a = timing.vector_dp * _share(run, timing.drag_ms)
		TutorialBeatDef.Gesture.BOX:
			_press(p, run, timing.hold_ms, phase < active)
			p.finger_a = timing.vector_dp * _share(run - timing.hold_ms, timing.drag_ms)
		_:
			var near: float = timing.size_dp * SPREAD_NEAR_SHARE
			var far: float = timing.size_dp * SPREAD_FAR_SHARE
			var share: float = _share(run, timing.pinch_ms)
			var out: bool = for_kind == TutorialBeatDef.Gesture.PINCH_OUT
			p.pressed = phase < active
			p.press_progress = 1.0 if p.pressed else 0.0
			p.finger_a = PINCH_AXIS * (lerpf(near, far, share) if out else lerpf(far, near, share))
			p.finger_b = -p.finger_a
	return p


## The still hand of reduced effects: the finger on the point, pressed, at full opacity; the arrow
## (drag, box) or the two arrows (pinch) are drawn from the kind.
func key_pose(for_kind: TutorialBeatDef.Gesture, timing: Timing) -> Pose:
	var p: Pose = pose(for_kind, 0, timing)
	if for_kind == TutorialBeatDef.Gesture.AUTO or for_kind == TutorialBeatDef.Gesture.NONE:
		return p
	p.pressed = true
	p.press_progress = 1.0
	p.alpha = 1.0
	p.finger_a = Vector2.ZERO
	p.rings = 2 if for_kind == TutorialBeatDef.Gesture.DOUBLE_TAP else 1
	if p.two_fingers:
		p.finger_a = PINCH_AXIS * timing.size_dp * (SPREAD_NEAR_SHARE + SPREAD_FAR_SHARE) * 0.5
		p.finger_b = -p.finger_a
	return p


func _press(p: Pose, run: int, length: int, down: bool) -> void:
	p.pressed = down
	p.press_progress = _share(run, length) if down else 0.0


func _share(run: int, length: int) -> float:
	return clampf(float(run) / float(length), 0.0, 1.0)


func _reload() -> void:
	_timing.load_from(settings, input_settings)
	_timing.vector_dp = vector_dp
	queue_redraw()


## What `_draw` shows: null while touched or idle, the still key pose with Reduced effects, else
## the pose of the loop's clock.
func draw_pose() -> Pose:
	if touched_hidden():
		return null
	if reduced:
		return key_pose(kind, _timing)
	return pose(kind, now_ms() - _loop_ms, _timing)


func _draw() -> void:
	var p: Pose = draw_pose()
	if p == null or p.alpha <= 0.0:
		return
	var dp: float = UiScale.base_px_per_dp()
	var fill: Color = get_theme_color(&"hint_fill", &"GuideTokens")
	var line: Color = get_theme_color(&"hint_line", &"GuideTokens")
	fill.a *= p.alpha
	line.a *= p.alpha
	var origin: Vector2 = size * 0.5
	var side: float = settings.hint_size_dp * dp
	if reduced:
		_draw_arrows(origin, dp, fill, line)
	elif kind == TutorialBeatDef.Gesture.BOX and p.finger_a != Vector2.ZERO:
		draw_rect(Rect2(origin, p.finger_a * dp).abs(), fill, false, LINE_DP * dp)
	if p.pressed:
		_draw_press(origin + p.finger_a * dp, p, dp, fill, line)
		if p.two_fingers:
			_draw_press(origin + p.finger_b * dp, p, dp, fill, line)
	var tip: Vector2 = PINCH_TIP if p.two_fingers else POINT_TIP
	var hand_at: Vector2 = (
		origin + (Vector2.ZERO if p.two_fingers else p.finger_a * dp) - tip * side
	)
	var texture: Texture2D = PINCH_TEXTURE if p.two_fingers else POINT_TEXTURE
	draw_texture_rect(texture, Rect2(hand_at, Vector2(side, side)), false, fill)


func _draw_press(at: Vector2, p: Pose, dp: float, fill: Color, line: Color) -> void:
	var radius: float = settings.hint_size_dp * RING_RADIUS_SHARE * dp
	for ring: int in p.rings:
		var r: float = radius * (0.4 + 0.6 * p.press_progress) + float(ring) * LINE_DP * 2.0 * dp
		draw_arc(at, r, 0.0, TAU, 32, line, LINE_DP * dp * 1.6)
		draw_arc(at, r, 0.0, TAU, 32, fill, LINE_DP * dp)


## Reduced effects: the arrow of a drag or a box along its diagonal, the two arrows of a pinch.
func _draw_arrows(origin: Vector2, dp: float, fill: Color, line: Color) -> void:
	if kind == TutorialBeatDef.Gesture.DRAG or kind == TutorialBeatDef.Gesture.BOX:
		_draw_arrow(origin, origin + vector_dp * dp, dp, fill, line)
	elif kind == TutorialBeatDef.Gesture.PINCH_OUT or kind == TutorialBeatDef.Gesture.PINCH_IN:
		var inner: float = settings.hint_size_dp * SPREAD_NEAR_SHARE * dp
		var outer: float = settings.hint_size_dp * SPREAD_FAR_SHARE * dp
		for side: float in [1.0, -1.0]:
			var near: Vector2 = origin + PINCH_AXIS * inner * side
			var far: Vector2 = origin + PINCH_AXIS * outer * side
			if kind == TutorialBeatDef.Gesture.PINCH_OUT:
				_draw_arrow(near, far, dp, fill, line)
			else:
				_draw_arrow(far, near, dp, fill, line)


func _draw_arrow(from: Vector2, to: Vector2, dp: float, fill: Color, line: Color) -> void:
	var direction: Vector2 = (to - from).normalized()
	var head: float = ARROW_HEAD_DP * dp
	var left: Vector2 = to - direction.rotated(0.5) * head
	var right: Vector2 = to - direction.rotated(-0.5) * head
	for pair: Array in [[line, LINE_DP * 1.6], [fill, LINE_DP]]:
		var color: Color = pair[0]
		var width: float = float(pair[1]) * dp
		draw_line(from, to, color, width)
		draw_line(to, left, color, width)
		draw_line(to, right, color, width)
