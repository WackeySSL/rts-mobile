extends SimProbe
## Writes down how many commands the loop's list holds, and the world's tick, when Sim.step starts.
## Not a test suite; test_match_loop.gd preloads it. It is a file of its own, not an inner class,
## because an inner class with a script base would name itself at run time.

var loop: MatchLoop
var world: World
var sizes: Array[int] = []
var ticks: Array[int] = []


func begin() -> void:
	sizes.append(loop._commands.size())
	ticks.append(world.tick)
