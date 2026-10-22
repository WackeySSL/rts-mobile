# UiOrientation autoload (ADR 0015 section 2). Keeps the root window's content scale size at the
# base size of the window's orientation: the project's 1280x720 in a landscape window and 720x1280
# in a portrait one, so the stretch under canvas_items and expand is the same number for the same
# device in both orientations and nothing shrinks when the phone turns. It lives in game/ui because
# it is a screen concern, and it holds no game rule and no state. A scene never needs a step of its
# own: this node enters the tree before any scene, so its handler of the root viewport's
# size_changed runs before theirs (a flip runs every handler twice, both times with the new
# stretch; each recomputes from the current metrics, so the end state is the same).
extends Node


func _ready() -> void:
	get_tree().root.size_changed.connect(_apply)
	_apply()


## Sets the content scale size when the window's orientation asks for another one. Setting it
## emits size_changed again at once, and that nested call finds the value in place and stops.
func _apply() -> void:
	var root: Window = get_tree().root
	var wanted: Vector2i = UiScale.base_size_for(root.size, _landscape_base())
	if root.content_scale_size != wanted:
		root.content_scale_size = wanted


## The base size of project.godot (display/window/size), the one the landscape layout is made for.
func _landscape_base() -> Vector2i:
	var width: int = ProjectSettings.get_setting("display/window/size/viewport_width")
	var height: int = ProjectSettings.get_setting("display/window/size/viewport_height")
	return Vector2i(width, height)
