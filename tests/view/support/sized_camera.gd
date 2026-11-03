extends RtsCamera
## A camera whose screen is a size the test sets (`screen`), so a suite can read the visible world
## rect of a phone in either orientation without resizing the window (plan P141). Not a test
## suite; made from its preload and set through `set(&"screen", size)`.

var screen: Vector2 = Vector2(1280.0, 720.0)


func _view_size() -> Vector2:
	return screen
