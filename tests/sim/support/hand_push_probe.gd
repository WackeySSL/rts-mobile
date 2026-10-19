extends SimProbe
## Puts back the pushes a test wrote by hand. Since P39b `Sim.step` computes `push_x` and `push_y`
## itself (the SEPARATION phase writes every row), so a push that a test sets on the World before a
## step is lost. This probe copies the arrays at `begin()` (before any phase) and writes them again
## at the SEPARATION mark, right after `Separation.run`, so `Movement.integrate` sees the hand-set
## pushes as it did when nothing wrote them. The pushes stay between ticks: what the probe wrote
## back is what it copies at the next `begin()`. A probe of the game never reads or writes the
## World; this one is a test's. Not a test suite. It is a file of its own, not an inner class,
## because an inner class with a script base would name itself at run time.

var world: World
var _held_x: PackedInt32Array = PackedInt32Array()
var _held_y: PackedInt32Array = PackedInt32Array()


func _init(for_world: World = null) -> void:
	world = for_world


func begin() -> void:
	_held_x = world.push_x.duplicate()
	_held_y = world.push_y.duplicate()


func mark(phase: int) -> void:
	if phase != SimProbe.Phase.SEPARATION:
		return
	for row: int in _held_x.size():
		world.push_x[row] = _held_x[row]
		world.push_y[row] = _held_y[row]
