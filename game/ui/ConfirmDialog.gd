class_name ConfirmDialog
extends ModalFrame
## A question with two answers over the HUD (ADR 0019 section 6; P124 builds the pause menu's
## confirms from it). Hidden until `open()`; the no button stands on the left.
## With `dismiss_outside` a touch outside the panel answers no (the sale of the last producer,
## P272); the pause menu's confirms keep the plain rule.

signal confirmed
signal cancelled

@export var question: String = ""
@export var detail: String = ""
@export var yes_text: String = ""
@export var no_text: String = ""
@export var dismiss_outside: bool = false

var _no: Button


func _ready() -> void:
	super()
	add_label(column, question, &"CapsTitle")
	add_label(column, detail, &"Label")
	var row: HBoxContainer = HBoxContainer.new()
	column.add_child(row)
	row.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	_no = add_button(row, no_text, _answer.bind(false))
	_no.name = &"NoButton"
	add_button(row, yes_text, _answer.bind(true)).name = &"YesButton"


func open() -> void:
	show_over(_no)


## A press outside the panel answers no and goes no further (nothing under the card sees it).
func _input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if not dismiss_outside or not visible or touch == null or not touch.pressed:
		return
	var panel: Control = column.get_parent() as Control
	if panel != null and not panel.get_global_rect().has_point(touch.position):
		get_viewport().set_input_as_handled()
		_answer(false)


## Hides the dialog without an answer (the match ended under it).
func close() -> void:
	visible = false


func _answer(yes: bool) -> void:
	visible = false
	if yes:
		confirmed.emit()
	else:
		cancelled.emit()
