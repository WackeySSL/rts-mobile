extends SimProbe
## A SimProbe that writes down what Sim.step tells it: -1 for each begin() and the phase id for
## each mark(), in call order. Not a test suite; test_sim_step.gd preloads it.

var calls: PackedInt32Array = PackedInt32Array()


func begin() -> void:
	calls.append(-1)


func mark(phase: int) -> void:
	calls.append(phase)
