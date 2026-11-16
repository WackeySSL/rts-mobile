class_name FakeAdPlaceholders
extends CanvasLayer
## The "Test ad" placeholders FakeAdBackend draws so the flows can be tried in the editor and on
## the web preview (ADR 0039 section 2). Sizes are in dp and the layout stays inside the safe
## area; both are recomputed when the viewport's size changes (a turn, a browser toolbar). They
## ignore the pause (`PROCESS_MODE_ALWAYS`), so Close works over the pause menu. Developer-only
## text: fake mode never ships in a release build.

const LAYER_FULLSCREEN: int = 120
const LAYER_BANNER: int = 110
const CLOSE_MIN_DP: Vector2 = Vector2(160, 64)

var _banner_dp: int = 0
var _is_banner: bool = false
## The safe-area box (full-screen) or the strip (banner).
var _area: Control = null
var _close: Button = null


## A full-screen "Test ad" with a Close button; `on_close` runs when it is pressed.
static func build_fullscreen(on_close: Callable) -> FakeAdPlaceholders:
	var layer: FakeAdPlaceholders = FakeAdPlaceholders.new()
	layer.name = "FakeTestAd"
	layer.layer = LAYER_FULLSCREEN
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.1, 0.1, 0.12, 1.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var area: Control = Control.new()
	area.name = "SafeArea"
	layer._area = area
	layer.add_child(area)
	var center: CenterContainer = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	area.add_child(center)
	var box: VBoxContainer = VBoxContainer.new()
	center.add_child(box)
	var label: Label = Label.new()
	label.text = "Test ad"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var close: Button = Button.new()
	close.name = "Close"
	close.text = "Close"
	close.pressed.connect(on_close)
	layer._close = close
	box.add_child(close)
	return layer


## A "Test ad" banner of `height_dp` on the bottom edge of the safe area; it takes no touch.
static func build_banner(height_dp: int) -> FakeAdPlaceholders:
	var layer: FakeAdPlaceholders = FakeAdPlaceholders.new()
	layer.name = "FakeTestBanner"
	layer.layer = LAYER_BANNER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer._is_banner = true
	layer._banner_dp = height_dp
	var strip: ColorRect = ColorRect.new()
	strip.color = Color(0.25, 0.25, 0.3, 1.0)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer._area = strip
	layer.add_child(strip)
	var label: Label = Label.new()
	label.text = "Test ad"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(label)
	return layer


func _ready() -> void:
	get_viewport().size_changed.connect(layout)
	layout()


## Places the content from the current dp factor and safe rect.
func layout() -> void:
	var safe: Rect2 = UiScale.safe_rect_base()
	if _is_banner:
		var height: float = UiScale.dp(float(_banner_dp))
		_area.position = Vector2(safe.position.x, safe.end.y - height)
		_area.size = Vector2(safe.size.x, height)
	else:
		_area.position = safe.position
		_area.size = safe.size
		_close.custom_minimum_size = UiScale.dp_vec(CLOSE_MIN_DP.x, CLOSE_MIN_DP.y)
