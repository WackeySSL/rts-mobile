class_name FakeBillingSheet
extends CanvasLayer
## The "Test purchase" sheet FakeBilling draws so Remove ads can be tried in the editor and on the
## web preview (ADR 0039 section 2), with Buy, Pending and Cancel. Sizes are in dp, the layout
## stays inside the safe area and is recomputed when the viewport's size changes. It ignores the
## pause (`PROCESS_MODE_ALWAYS`). Developer-only text: fake mode never ships in a release build.

const LAYER: int = 125
## Every button is at least this big (dp); touch targets are 48 dp or more.
const BUTTON_MIN_DP: Vector2 = Vector2(160, 56)

var _area: Control = null
var _buttons: Array[Button] = []


## `on_buy`, `on_pending` and `on_cancel` run when their button is pressed.
static func build(
	price: String, on_buy: Callable, on_pending: Callable, on_cancel: Callable
) -> FakeBillingSheet:
	var layer: FakeBillingSheet = FakeBillingSheet.new()
	layer.name = "FakeTestPurchase"
	layer.layer = LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.1, 0.1, 0.12, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var area: Control = Control.new()
	area.name = "SafeArea"
	layer._area = area
	layer.add_child(area)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	area.add_child(center)
	var box: VBoxContainer = VBoxContainer.new()
	center.add_child(box)
	var label: Label = Label.new()
	label.text = "Test purchase: Remove ads\n%s" % price
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	layer._add_button(box, "Buy", on_buy)
	layer._add_button(box, "Pending", on_pending)
	layer._add_button(box, "Cancel", on_cancel)
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


func _add_button(box: Control, text: String, on_press: Callable) -> void:
	var button: Button = Button.new()
	button.name = text
	button.text = text
	button.pressed.connect(on_press)
	_buttons.append(button)
	box.add_child(button)
