extends RefCounted
## Pushes touch events into a viewport as the engine delivers them. `push_input` takes window px
## but the game thinks in base px (canvas units), so each helper converts with the final transform.
## Not a test suite.


static func press(vp: Viewport, index: int, at_base: Vector2) -> void:
	_push(vp, index, at_base, true, false)


static func release(vp: Viewport, index: int, at_base: Vector2, canceled: bool = false) -> void:
	_push(vp, index, at_base, false, canceled)


## The finger is now at `at_base`, having moved by `relative_base`.
static func drag(vp: Viewport, index: int, at_base: Vector2, relative_base: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = index
	event.position = vp.get_final_transform() * at_base
	event.relative = vp.get_final_transform().basis_xform(relative_base)
	vp.push_input(event)


## One wheel notch (MOUSE_BUTTON_WHEEL_UP or MOUSE_BUTTON_WHEEL_DOWN) at `at_base`.
static func wheel(vp: Viewport, button_index: int, at_base: Vector2) -> void:
	for pressed: bool in [true, false]:  # The engine follows every notch with a release.
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = button_index
		event.pressed = pressed
		event.position = vp.get_final_transform() * at_base
		vp.push_input(event)


static func _push(vp: Viewport, index: int, at: Vector2, pressed: bool, canceled: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = vp.get_final_transform() * at
	event.pressed = pressed
	event.canceled = canceled
	vp.push_input(event)
