class_name MoveMarkerLayer
extends Node2D
## Order feedback in world space (STYLE.md "Feedback markers"): four chevrons closing in on an
## attack-move point, or a diamond flash on an enemy. `pool_size` marks are reused oldest first and
## each lives `settings.marker_ms` by `clock`. A mark is scaled by dp / zoom every frame, so its dp
## children keep their size on screen through a pinch. It fades as ONE group through
## `CanvasGroup.self_modulate`: `modulate` would reach the lines too and blend twice, which turns
## the marker dark mid-fade.

const WARNING: Color = Color("F5A524")
const DANGER: Color = Color("E5484D")
const CHEVRON_DP: Vector2 = Vector2(36.0, 12.0)  ## Tip distance from the point: start, rest.
const CHEVRON_MS: float = 200.0
const DIAMOND_PX: float = 45.8  ## Corner distance in world px: 1.3 x a light tank's ring.
const DIAMOND_START: float = 1.5  ## Times the size, easing to 1.
const DIAMOND_MS: float = 150.0
const FADE_START_MS: float = 200.0  ## Full alpha up to min(this, marker_ms / 3).

@export var pool_size: int = 4
@export var settings: InputSettings

var clock: Callable = Time.get_ticks_msec  ## Returns ms. Tests replace it.
var _marks: Array[Mark] = []
var _next: int = 0  ## Pool slot for the next mark: round robin is oldest first.


## Children 0-4 are the outline passes (four chevrons, then the diamond), 5-9 the colour passes.
class Mark:
	extends CanvasGroup

	const CHEVRON: PackedVector2Array = [Vector2(7, -7), Vector2.ZERO, Vector2(7, 7)]  ## dp
	const CORNERS: PackedVector2Array = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]

	var born_ms: int = 0
	var diamond: bool = false
	var dp_px: float = 1.0  ## Base px per dp when the mark was shown.

	func _init() -> void:
		for outline: bool in [true, false]:
			for shape: int in 5:
				var line: Line2D = Line2D.new()
				line.default_color = FeedbackStyle.OUTLINE
				if not outline:
					line.default_color = DANGER if shape == 4 else WARNING
				line.width = (
					FeedbackStyle.STROKE_DP + (FeedbackStyle.OUTLINE_DP if outline else 0.0)
				)
				line.joint_mode = Line2D.LINE_JOINT_ROUND
				line.begin_cap_mode = Line2D.LINE_CAP_ROUND
				line.end_cap_mode = Line2D.LINE_CAP_ROUND
				line.antialiased = true
				line.closed = shape == 4
				line.points = CORNERS if shape == 4 else CHEVRON
				line.rotation = shape * PI / 2.0 if shape < 4 else 0.0
				add_child(line)

	## The size, fade and motion `age` ms after the mark was shown, at camera `zoom`.
	func pose(age: float, marker_ms: float, zoom: float) -> void:
		scale = Vector2.ONE * dp_px / zoom
		var fade_start: float = minf(FADE_START_MS, marker_ms / 3.0)
		self_modulate.a = clampf((marker_ms - age) / maxf(marker_ms - fade_start, 1.0), 0.0, 1.0)
		var reach: float = lerpf(
			CHEVRON_DP.x, CHEVRON_DP.y, FeedbackStyle.ease_out(age / CHEVRON_MS)
		)
		var size: float = lerpf(DIAMOND_START, 1.0, FeedbackStyle.ease_out(age / DIAMOND_MS))
		for first: int in [0, 5]:
			for shape: int in 4:
				var chevron: Line2D = get_child(first + shape)
				chevron.visible = not diamond
				chevron.position = Vector2(reach, 0.0).rotated(shape * PI / 2.0)
			var flash: Line2D = get_child(first + 4)
			flash.visible = diamond
			for corner: int in 4:  # World px: this node's scale turns them into dp.
				flash.set_point_position(corner, CORNERS[corner] * DIAMOND_PX / scale.x * size)


func _ready() -> void:
	if settings == null:
		settings = InputSettings.new()  # The script defaults are the ADR table.


func show_attack_move(world_px: Vector2) -> void:
	_show(world_px, false)


func show_target(world_px: Vector2) -> void:
	_show(world_px, true)


func active_count() -> int:
	return _marks.filter(func(mark: Mark) -> bool: return mark.visible).size()


func _process(_delta: float) -> void:
	var now: int = clock.call()
	var zoom: float = get_canvas_transform().get_scale().x
	for mark: Mark in _marks:
		var age: int = now - mark.born_ms
		if mark.visible:
			mark.pose(age, settings.marker_ms, zoom)
			mark.visible = age < settings.marker_ms


func _show(world_px: Vector2, diamond: bool) -> void:
	if _next >= _marks.size():  # The pool fills once, then every mark is reused.
		_marks.append(Mark.new())
		add_child(_marks.back())
	var mark: Mark = _marks[_next]
	_next = (_next + 1) % maxi(pool_size, 1)
	mark.position = world_px
	mark.dp_px = UiScale.base_px_per_dp()
	mark.diamond = diamond
	mark.born_ms = clock.call()
	mark.visible = true
	mark.pose(0.0, settings.marker_ms, get_canvas_transform().get_scale().x)
