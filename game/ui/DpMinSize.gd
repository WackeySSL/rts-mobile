class_name DpMinSize
extends Node
## Keeps its parent Control at least `min_dp` density-independent pixels in size (ADR 0004
## section 3). Add it as a child of any tappable Control. It sets the parent's
## `custom_minimum_size` in `_ready` and whenever the viewport's size changes (rotation, a browser
## toolbar), because the dp factor changes with it. Setting `min_dp` later applies it at once.

@export var min_dp: Vector2 = Vector2(48, 48):
	set(value):
		min_dp = value
		if is_node_ready():
			_apply()


func _ready() -> void:
	get_viewport().size_changed.connect(_apply)
	_apply()


func _apply() -> void:
	var control: Control = get_parent() as Control
	if control == null:
		return
	control.custom_minimum_size = UiScale.dp_vec(min_dp.x, min_dp.y)
