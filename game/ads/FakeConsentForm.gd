class_name FakeConsentForm
extends CanvasLayer
## The consent form placeholder FakeUmp draws so the flow can be tried in the editor and on the web
## preview (ADR 0039 section 3). Sizes are in dp and the layout stays inside the safe area; both are
## recomputed when the viewport's size changes. Ignores the pause. Developer-only text: fake mode
## never ships in a release build. Buttons stack vertically so a narrow portrait width holds them.

const LAYER: int = 130
const BUTTON_MIN_DP: Vector2 = Vector2(160, 64)

var _area: Control = null
var _buttons: Array[Button] = []


## Accept and Decline always; Close (the form dismissed, nothing changed) only for `with_close`.
static func build(
	with_close: bool, on_accept: Callable, on_decline: Callable, on_close: Callable
) -> FakeConsentForm:
	var layer: FakeConsentForm = FakeConsentForm.new()
	layer.name = "FakeConsentForm"
	layer.layer = LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.1, 0.1, 0.12, 1.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	layer._area = Control.new()
	layer._area.name = "SafeArea"
	layer.add_child(layer._area)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer._area.add_child(center)
	var box: VBoxContainer = VBoxContainer.new()
	center.add_child(box)
	var label: Label = Label.new()
	label.text = "Test consent form"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	layer._add_button(box, "Accept", on_accept)
	layer._add_button(box, "Decline", on_decline)
	if with_close:
		layer._add_button(box, "Close", on_close)
	return layer


func _ready() -> void:
	get_viewport().size_changed.connect(layout)
	layout()


## Places the content from the current dp factor and safe rect.
func layout() -> void:
	var safe: Rect2 = UiScale.safe_rect_base()
	_area.position = safe.position
	_area.size = safe.size
	for button: Button in _buttons:
		button.custom_minimum_size = UiScale.dp_vec(BUTTON_MIN_DP.x, BUTTON_MIN_DP.y)


func _add_button(box: Container, caption: String, on_press: Callable) -> void:
	var button: Button = Button.new()
	button.name = caption
	button.text = caption
	button.pressed.connect(on_press)
	_buttons.append(button)
	box.add_child(button)
