extends Control
## Touch probe (developer scene, ADR 0004 section 3): what the engine reports about the screen,
## what `UiScale` makes of it (the base size it is stretched from and the window's orientation,
## ADR 0015), a square that should measure 7.6 mm (48 dp) with a ruler, the live touch points (base
## px) and the last 8 gestures a `GestureRecognizer` makes of them. The square is exactly
## `UiScale.dp(48)` per side, kept so by `DpMinSize` on resize. It sits in a plain Control, because
## a BoxContainer rounds the heights of its children up to whole px.
## The layout fits a 360 dp wide screen held upright (the column and Back side by side) and a
## 304 dp tall one held sideways (a phone browser): the ruler's text sits beside the square, and no
## line is wider than about 30 characters.

const SQUARE_DP: float = 48.0
const TOUCH_RADIUS_DP: float = 24.0  ## A finger-sized circle: 48 dp across.
const LOG_LINES: int = 8
const SETTINGS: InputSettings = preload("res://data/input_settings.tres")
const FONT_DP: float = 16.0
const GAP_DP: float = 12.0
const BACKGROUND: Color = Color(0.11, 0.13, 0.15)
const TOUCH_FILL: Color = Color(0.18, 0.5, 0.93, 0.35)

## What Back does. Tests replace it so that no scene changes.
var back_action: Callable = _open_dev_menu
## Returns the time in ms. Tests replace it.
var clock: Callable = Time.get_ticks_msec
## Live touch points by finger index, base px.
var touches: Dictionary[int, Vector2] = {}
## The last gestures, oldest first, one `describe()` line each.
var log_lines: PackedStringArray = []

var _recognizer: GestureRecognizer = GestureRecognizer.new()
var _events: Array[GestureEvent] = []
var _previous_quit_on_go_back: bool = true

@onready var _column: VBoxContainer = $Margin/Column
@onready var _square_row: HBoxContainer = $Margin/Column/SquareRow
@onready var _metrics_label: Label = $Margin/Column/MetricsLabel
@onready var _square_label: Label = $Margin/Column/SquareRow/SquareLabel
@onready var _back_button: Button = $Margin/BackButton
@onready var _log_label: Label = $Margin/GestureLog


func _enter_tree() -> void:
	# SceneTree.quit_on_go_back is true by default and would quit the app on the Android back
	# button before the probe can leave. Switch it off while the probe is open.
	var tree: SceneTree = get_tree()
	_previous_quit_on_go_back = tree.quit_on_go_back
	tree.quit_on_go_back = false


func _exit_tree() -> void:
	get_tree().quit_on_go_back = _previous_quit_on_go_back


func _ready() -> void:
	_back_button.pressed.connect(_go_back)
	get_viewport().size_changed.connect(_refresh)
	_refresh()
	_show_log()


func _input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	var now_ms: int = clock.call()
	if touch != null and touch.pressed:
		touches[touch.index] = touch.position
		_recognizer.touch_down(touch.index, touch.position, now_ms)
	elif touch != null:
		touches.erase(touch.index)
		_recognizer.touch_up(touch.index, touch.position, now_ms, touch.canceled)
	elif drag != null:
		touches[drag.index] = drag.position
		_recognizer.touch_move(drag.index, drag.position, now_ms)
	_collect_gestures()
	queue_redraw()


func _process(_delta: float) -> void:
	_recognizer.advance(clock.call())  # A long-press arrives while the finger rests.
	_collect_gestures()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Never change scenes from inside a notification dispatch.
		_go_back.call_deferred()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	var radius: float = UiScale.dp(TOUCH_RADIUS_DP)
	for at: Vector2 in touches.values():
		draw_circle(at, radius, TOUCH_FILL)
		draw_arc(at, radius, 0.0, TAU, 48, Color.WHITE, 2.0)


## One line per gesture: its name and the numbers that matter, rounded to whole base px.
static func describe(e: GestureEvent) -> String:
	var kind_name: String = GestureEvent.Kind.keys()[e.kind]
	match e.kind:
		GestureEvent.Kind.TAP, GestureEvent.Kind.DOUBLE_TAP, GestureEvent.Kind.LONG_PRESS:
			return "%s %s" % [kind_name, _xy(e.position)]
		GestureEvent.Kind.BOX_UPDATE, GestureEvent.Kind.BOX_END:
			return "%s %s %s" % [kind_name, _xy(e.rect.position), _xy(e.rect.size, "x")]
		GestureEvent.Kind.PAN:
			return "%s move %s" % [kind_name, _xy(e.delta)]
		GestureEvent.Kind.PINCH:
			return "%s x%.2f move %s at %s" % [kind_name, e.scale, _xy(e.delta), _xy(e.centre)]
	return kind_name


static func _xy(v: Vector2, separator: String = ",") -> String:
	return "%d%s%d" % [roundi(v.x), separator, roundi(v.y)]


## Moves the recognizer's new gestures into the log, which keeps the last LOG_LINES of them.
func _collect_gestures() -> void:
	if _recognizer.take_events(_events) == 0:
		return
	for event: GestureEvent in _events:
		log_lines.append(describe(event))
	_events.clear()
	log_lines = log_lines.slice(maxi(log_lines.size() - LOG_LINES, 0))
	_show_log()


## Always LOG_LINES lines, so the label keeps its height and the newest line its place.
func _show_log() -> void:
	var padding: PackedStringArray = []
	padding.resize(LOG_LINES - log_lines.size())
	_log_label.text = "\n".join(padding + log_lines)


## Recomputes everything that depends on dp: the numbers, the font, the gap and the recognizer's
## thresholds. The screen margins are the SafeAreaMargin's.
func _refresh() -> void:
	_recognizer.configure(SETTINGS, UiScale.base_px_per_dp())
	var m: UiMetrics = UiScale.current()
	var base: Vector2i = get_window().content_scale_size
	var lines: PackedStringArray = [
		"OS: %s" % m.os_name,
		"dpi: %d" % m.dpi,
		"screen scale: %.3f" % m.screen_scale,
		"stretch scale: %.3f" % m.stretch_scale,
		"window: %d x %d px" % [m.window_size.x, m.window_size.y],
		"base %d x %d (%s)" % [base.x, base.y, _orientation_name(m)],
		"safe area: %s px" % _compact(m.safe_area),
		"base px per dp: %.3f" % UiScale.base_px_per_dp(),
		"dp(%d): %.1f base px" % [roundi(SQUARE_DP), UiScale.dp(SQUARE_DP)],
	]
	_metrics_label.text = "\n".join(lines)
	var font_size: int = roundi(UiScale.dp(FONT_DP))
	for control: Control in [_metrics_label, _square_label, _back_button, _log_label]:
		control.add_theme_font_size_override("font_size", font_size)
	_column.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	_square_row.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	queue_redraw()


## A rectangle as "x,y WxH": the engine's own text of a Rect2i is too wide for a 360 dp screen.
static func _compact(rect: Rect2i) -> String:
	return "%d,%d %dx%d" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


## The window's orientation by UiScale's one rule (ADR 0015 section 2).
static func _orientation_name(m: UiMetrics) -> String:
	return "portrait" if UiScale.is_portrait_size(m.window_size) else "landscape"


func _go_back() -> void:
	back_action.call()


func _open_dev_menu() -> void:
	DevRoutes.open(get_tree(), DevRoutes.DEV_MENU_SCENE)
