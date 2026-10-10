class_name DpMinSize
extends Node
## Keeps its parent Control at least `min_dp` density-independent pixels in size (ADR 0004
## section 3). Add it as a child of any tappable Control. It sets the parent's
## `custom_minimum_size` in `_ready` and whenever the viewport's size changes (rotation, a browser
## toolbar), because the dp factor changes with it.

@export var min_dp: Vector2 = Vector2(48, 48)


func _ready() -> void:
	if not get_parent() is Control:
		push_warning("DpMinSize needs a Control parent: %s" % get_path())
		return
	get_viewport().size_changed.connect(_apply)
	_apply()


func _apply() -> void:
	var control: Control = get_parent() as Control
	if control == null:
		return
	control.custom_minimum_size = UiScale.dp_vec(min_dp.x, min_dp.y)
