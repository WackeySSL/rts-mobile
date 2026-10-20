extends SimProbe
## Writes down, at each mark() of Sim.step, the phase, the `fog_cell` column and the fog counts of
## the World. It shows where the fog sits in the tick: REMOVE unstamps a dead row, and the FOG
## update after it moves the rows that changed tile. A probe of the game never reads the World;
## this one is a test's. Not a test suite; test_fog.gd preloads it. It is a file of its own, not an
## inner class, because an inner class with a script base would name itself at run time.

var world: World
var phases: Array[int] = []
var stamped: Array[PackedInt32Array] = []
var visible: Array[PackedInt32Array] = []


func _init(for_world: World = null) -> void:
	world = for_world


func mark(phase: int) -> void:
	phases.append(phase)
	stamped.append(world.fog_cell.duplicate())
	visible.append(world.fog.visible.duplicate())
