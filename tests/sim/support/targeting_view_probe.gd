extends SimProbe
## Writes down, at each mark() of Sim.step, what the targeting part of the tick looks like from
## outside: the phase, the cells of the targeting grid that hold a row, the target of row 0 and the
## TARGET_CANDIDATES count. It shows where the GRIDS and TARGETING marks sit relative to the phases
## around them. A probe of the game never reads the World; this one is a test's. Not a test suite;
## test_targeting.gd preloads it. It is a file of its own, not an inner class, because an inner
## class with a script base would name itself at run time.

var world: World
var phases: Array[int] = []
var occupied: Array[int] = []
var targets: Array[int] = []
var candidates: Array[int] = []


func _init(for_world: World = null) -> void:
	world = for_world


func mark(phase: int) -> void:
	phases.append(phase)
	var heads: PackedInt32Array = world.target_grid.head
	occupied.append(heads.size() - heads.count(-1))
	targets.append(world.target[0])
	candidates.append(world.stats[World.Stat.TARGET_CANDIDATES])
