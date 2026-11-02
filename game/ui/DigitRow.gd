class_name DigitRow
extends HBoxContainer
## A number whose digits keep fixed slots (ADR 0025 section 13). Chakra Petch has no `tnum`
## feature (P118 checked), so a figure that changes cannot rely on tabular digits: each digit is
## its own label, as wide as the widest digit of the theme's font, centred in its slot, and the row
## keeps room for `slots` digits at least. A "/", a "+" or a "-" keeps its own width. The labels are
## made when a longer number first needs them and are reused; the text is written only when it
## changes (`writes` counts them). The look is the theme's: `variation` is the Label type.

@export var variation: StringName = &"NumberLabel":
	set(value):
		variation = value
		for label: Label in _labels:
			label.theme_type_variation = value
		if is_node_ready():
			refit()
@export var slots: int = 0  ## The digits the row always has room for.
@export var edge_dp: float = 0.0  ## The dark edge of the digits (the theme's outline colour), dp.

var text: String = ""  ## The number now on show; set it through `set_text`.
var writes: int = 0  ## How often `set_text` changed the text.

var _labels: Array[Label] = []
var _slot_px: float = 0.0  ## The widest digit at the theme's font and size.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER if slots == 0 else BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 0)
	refit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		refit()


## Shows `value`: nothing is touched when it is the number on show already.
func set_text(value: String) -> void:
	if value == text:
		return
	text = value
	writes += 1
	while _labels.size() < value.length():
		var label: Label = Label.new()
		label.theme_type_variation = variation
		label.add_theme_constant_override("outline_size", roundi(UiScale.dp(edge_dp)))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(label)
		_labels.append(label)
	for index: int in _labels.size():
		_labels[index].visible = index < value.length()
		if index < value.length():
			_labels[index].text = value[index]
	_apply_slots()


## The slots follow the theme's font and size: the widest digit, and the room for `slots` of them.
func refit() -> void:
	var font: Font = get_theme_font(&"font", variation)
	var font_px: int = get_theme_font_size(&"font_size", variation)
	_slot_px = 0.0
	for digit: String in "0123456789":
		var advance: float = font.get_string_size(digit, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px).x
		_slot_px = maxf(_slot_px, advance)
	_slot_px = ceilf(_slot_px)
	custom_minimum_size.x = slots * _slot_px
	for label: Label in _labels:
		label.add_theme_constant_override("outline_size", roundi(UiScale.dp(edge_dp)))
	_apply_slots()


func _apply_slots() -> void:
	for index: int in text.length():
		var digit: bool = text[index] >= "0" and text[index] <= "9"
		_labels[index].custom_minimum_size.x = _slot_px if digit else 0.0
