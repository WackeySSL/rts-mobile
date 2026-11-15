class_name FakeAdPlaceholders
extends RefCounted
## The "Test ad" placeholders FakeAdBackend draws so the flows can be tried in the editor and on
## the web preview (ADR 0039 section 2). They run while the tree is paused, so Close works over
## the pause menu. Developer-only text: fake mode never ships in a release build.

const LAYER_FULLSCREEN: int = 120
const LAYER_BANNER: int = 110
const CLOSE_MIN_SIZE: Vector2 = Vector2(160, 64)


## A full-screen "Test ad" with a Close button; `on_close` runs when it is pressed.
static func build_fullscreen(on_close: Callable) -> CanvasLayer:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "FakeTestAd"
	layer.layer = LAYER_FULLSCREEN
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.1, 0.1, 0.12, 1.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	dim.add_child(box)
	var label: Label = Label.new()
	label.text = "Test ad"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var close: Button = Button.new()
	close.name = "Close"
	close.text = "Close"
	close.custom_minimum_size = CLOSE_MIN_SIZE
	close.pressed.connect(on_close)
	box.add_child(close)
	return layer


## A "Test ad" banner of `height_dp` at the foot of the screen; it takes no touch.
static func build_banner(height_dp: int) -> CanvasLayer:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "FakeTestBanner"
	layer.layer = LAYER_BANNER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var strip: ColorRect = ColorRect.new()
	strip.color = Color(0.25, 0.25, 0.3, 1.0)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -float(height_dp)
	layer.add_child(strip)
	var label: Label = Label.new()
	label.text = "Test ad"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(label)
	return layer
