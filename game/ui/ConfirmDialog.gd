class_name ConfirmDialog
extends ModalFrame
## A question with two answers over the HUD (ADR 0019 section 6; P124 builds the pause menu's
## confirms from it). Hidden until `open()`; the no button stands on the left.

signal confirmed
signal cancelled

@export var question: String = ""
@export var detail: String = ""
@export var yes_text: String = ""
@export var no_text: String = ""

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


## Hides the dialog without an answer (the match ended under it).
func close() -> void:
	visible = false


func _answer(yes: bool) -> void:
	visible = false
	if yes:
		confirmed.emit()
	else:
		cancelled.emit()
