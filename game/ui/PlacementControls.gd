class_name PlacementControls
extends HBoxContainer
## The check mark and the X of placement mode (plan P86, ADR 0019 section 2, ADR 0023 section 12):
## while the mode is on they take the card row's place, in the floating panel in landscape and in
## the band in portrait, `ACTION_DP` across (the strike's size) and a wide gap apart. The check
## mark is dimmed while the ghost does not fit, while a PLACE is pending and while the ghost is
## "Blocked" (P86b); it sends the one PLACE. The X sends nothing and works in every state.
## `BuildSidebar` owns the row, hides its cards meanwhile and tells it the cards' height
## (`set_row_dp`) so the panel keeps its size. The plates are the strike's: one look for all.

const ACTION_DP: float = 64.0  ## The check mark and the X: placement's size (touch-ui-rules).
const ICON_DP: float = 32.0
const GAP_DP: float = 24.0
const CONFIRM_VARIATION: StringName = &"StrikeConfirm"
const CANCEL_VARIATION: StringName = &"StrikeButton"
const ICON_ART: String = "res://assets/art/svg/icons/glyph_%s.svg"

@export var placement: PlacementController

var _confirm: Button = Button.new()
var _cancel: Button = Button.new()
var _row: DpMinSize = DpMinSize.new()  ## The row's least height: the cards' row it replaces.


func _init() -> void:
	_row.name = "RowHeight"
	_row.min_dp = Vector2.ZERO  # The sidebar sets the height; a default would be 48 dp square.


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_row)
	_confirm.name = "PlaceConfirm"
	_cancel.name = "PlaceCancel"
	_confirm.pressed.connect(placement.confirm)
	_cancel.pressed.connect(placement.cancel)
	for action: Array in [
		[_confirm, CONFIRM_VARIATION, "check"], [_cancel, CANCEL_VARIATION, "cross"]
	]:
		var button: Button = action[0]
		button.theme_type_variation = action[1]
		button.icon = load(ICON_ART % action[2])
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER  # The icon alone, in the plate.
		button.focus_mode = Control.FOCUS_NONE  # No focus ring left behind after a tap.
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # A plate keeps its shape.
		var fit: DpMinSize = DpMinSize.new()
		fit.min_dp = Vector2(ACTION_DP, ACTION_DP)
		button.add_child(fit)
		add_child(button)
	placement.changed.connect(_show)
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()
	_show()


## The row is at least `height_dp` high, the cards' row it takes the place of.
func set_row_dp(height_dp: float) -> void:
	_row.min_dp = Vector2(0.0, height_dp)


## Shown while the mode is on; the check mark waits for a ghost that fits and is not pending.
func _show() -> void:
	visible = placement.active
	_confirm.disabled = not placement.can_confirm()


## Sizes are dp, so they follow a resize like DpMinSize does.
func _apply_dp() -> void:
	add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	for button: Button in [_confirm, _cancel]:
		button.add_theme_constant_override("icon_max_width", roundi(UiScale.dp(ICON_DP)))
