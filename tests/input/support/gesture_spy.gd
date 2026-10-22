extends PlayerController
## Records the kind of every gesture that TouchInput routes to the controller and does nothing
## else. Not a test suite. It has its own file because an inner class may not extend a script
## (tests/project/test_inner_classes_extend_engine_classes.gd).

var kinds: Array[int] = []


func handle_gesture(e: GestureEvent) -> void:
	kinds.append(e.kind)
