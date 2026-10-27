extends SimProbe
## Writes down, at each mark() of Sim.step, the phase and what the strike suites watch then: the
## number of rows, the hit points and the `offline_until` of row `watched` (a unit id; -1000000 and
## -1 when it has no row) and player 1's pending strike tick. It shows that a rupture lowers the hit
## points and clears the pending strike inside the FIRE mark, that the row is gone at the REMOVE
## mark, and (P111) that a blackout is written by the COMMANDS mark. A probe of the game never reads
## the World; this one is a test's. Not a test suite. It is a file of its own, not
## an inner class, because an inner class with a script base would name itself at run time.

var world: World
var watched: int = 0
var phases: Array[int] = []
var rows: Array[int] = []
var hit_points: Array[int] = []
var offline: Array[int] = []
var pending: Array[int] = []


func _init(for_world: World = null, unit_id: int = 0) -> void:
	world = for_world
	watched = unit_id


func mark(phase: int) -> void:
	phases.append(phase)
	rows.append(world.unit_count())
	var row: int = world.index_of(watched)
	hit_points.append(world.hp[row] if row >= 0 else -1000000)
	offline.append(world.offline_until[row] if row >= 0 else -1)
	pending.append(world.strike_tick[1])
