extends SimProbe
## Writes down, at each mark() of Sim.step, where the damage and the removal of a tick happen: the
## phase, the hp of row 1, the number of rows, the number of event ints and the cooldown of row 0.
## It shows that FIRE lowers the hp (and writes the SHOT) before REMOVE takes the row away (and
## writes the DIED). A probe of the game never reads the World; this one is a test's. Not a test
## suite; test_combat.gd preloads it. It is a file of its own, not an inner class, because an inner
## class with a script base would name itself at run time.

var world: World
var phases: Array[int] = []
var hit_points: Array[int] = []
var rows: Array[int] = []
var event_ints: Array[int] = []
var cooldowns: Array[int] = []


func _init(for_world: World = null) -> void:
	world = for_world


func mark(phase: int) -> void:
	phases.append(phase)
	hit_points.append(world.hp[1] if world.unit_count() > 1 else 0)
	rows.append(world.unit_count())
	event_ints.append(world.events.size())
	cooldowns.append(world.cooldown[0])
