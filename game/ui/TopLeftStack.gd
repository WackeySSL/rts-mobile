class_name TopLeftStack
extends VBoxContainer
## The Dev button with the Surrender button under it (plan P90); P124 takes both away. The gap
## between them is dp, so it follows a resize and a turn.

const GAP_DP: float = 8.0


func _ready() -> void:
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()


func _apply_dp() -> void:
	add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
