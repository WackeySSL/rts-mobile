extends Control
## Touch probe (developer scene, ADR 0004 section 3): what the engine reports about the screen,
## what `UiScale` makes of it, a square that should measure 7.6 mm (48 dp) with a ruler, and the
## live touch points (base px). The square is exactly `UiScale.dp(48)` per side, kept so by
## `DpMinSize` on resize. It sits in a plain Control, because a BoxContainer rounds the heights
## of its children up to whole px.

const SQUARE_DP: float = 48.0
const TOUCH_RADIUS_DP: float = 24.0  ## A finger-sized circle: 48 dp across.
const FONT_DP: float = 16.0
const GAP_DP: float = 12.0
const BACKGROUND: Color = Color(0.11, 0.13, 0.15)
const TOUCH_FILL: Color = Color(0.18, 0.5, 0.93, 0.35)

## What Back does. Tests replace it so that no scene changes.
var back_action: Callable = _open_dev_menu
## Live touch points by finger index, base px.
var touches: Dictionary[int, Vector2] = {}

var _previous_quit_on_go_back: bool = true

@onready var _margin: MarginContainer = $Margin
@onready var _metrics_label: Label = $Margin/Column/MetricsLabel
@onready var _square_label: Label = $Margin/Column/SquareLabel
@onready var _back_button: Button = $Margin/BackButton


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


func _input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if touch != null and touch.pressed:
		touches[touch.index] = touch.position
	elif touch != null:
		touches.erase(touch.index)
	elif drag != null:
		touches[drag.index] = drag.position
	queue_redraw()


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


## Recomputes everything that depends on dp: the numbers, the font and the margins.
func _refresh() -> void:
	var m: UiMetrics = UiScale.current()
	var lines: PackedStringArray = [
		"OS: %s" % m.os_name,
		"dpi: %d" % m.dpi,
		"screen scale: %.3f" % m.screen_scale,
		"stretch scale: %.3f" % m.stretch_scale,
		"window: %d x %d px" % [m.window_size.x, m.window_size.y],
		"base px per dp: %.3f" % UiScale.base_px_per_dp(),
		"dp(%d): %.1f base px" % [roundi(SQUARE_DP), UiScale.dp(SQUARE_DP)],
	]
	_metrics_label.text = "\n".join(lines)
	var font_size: int = roundi(UiScale.dp(FONT_DP))
	for control: Control in [_metrics_label, _square_label, _back_button]:
		control.add_theme_font_size_override("font_size", font_size)
	for side: String in ["left", "top", "right"]:
		_margin.add_theme_constant_override("margin_" + side, roundi(UiScale.dp(GAP_DP)))
	queue_redraw()


func _go_back() -> void:
	back_action.call()


func _open_dev_menu() -> void:
	DevRoutes.open(get_tree(), DevRoutes.DEV_MENU_SCENE)
