extends SimProbe
## Writes down, at each mark() of Sim.step, what the separation part of the tick looks like from
## outside: the phase, the x pushes of rows 0 and 1, the x intent of row 0, the x positions of rows
## 0 and 1, the cells of the separation grid that hold a row, and the SEP_PAIRS count. It shows
## where the GRIDS and SEPARATION marks sit relative to the phases around them. A probe of the game
## never reads the World; this one is a test's. Not a test suite; test_separation_tick.gd preloads
## it. It is a file of its own, not an inner class, because an inner class with a script base would
## name itself at run time.

var world: World
var phases: Array[int] = []
var pushes: Array[Vector2i] = []
var intents: Array[int] = []
var positions: Array[Vector2i] = []
var occupied: Array[int] = []
var pairs: Array[int] = []


func _init(for_world: World = null) -> void:
	world = for_world


func mark(phase: int) -> void:
	phases.append(phase)
	pushes.append(Vector2i(world.push_x[0], world.push_x[1]))
	intents.append(world.intent_x[0])
	positions.append(Vector2i(world.pos_x[0], world.pos_x[1]))
	var heads: PackedInt32Array = world.sep_grid.head
	occupied.append(heads.size() - heads.count(-1))
	pairs.append(world.stats[World.Stat.SEP_PAIRS])
