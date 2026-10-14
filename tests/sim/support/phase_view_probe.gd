extends SimProbe
## Writes down, at each mark() of Sim.step, the phase and what row 0 of `world` holds then: its x
## intent and its x position. It shows where a mark sits relative to the phase before it. A probe
## of the game never reads the World; this one is a test's. Not a test suite; test_movement.gd
## preloads it. It is a file of its own, not an inner class, because an inner class with a script
## base would name itself at run time.

var world: World
var phases: Array[int] = []
var intents_x: Array[int] = []
var positions_x: Array[int] = []


func mark(phase: int) -> void:
	phases.append(phase)
	intents_x.append(world.intent_x[0])
	positions_x.append(world.pos_x[0])
