extends SimProbe
## Checks, at the TARGETING mark of every tick it sees, that the targets just chosen stand inside
## the sight of the unit that chose them: the authoring rule of the fog PR (P46b), which checks the
## vision of a unit when it scans. It looks at the units that were due this tick only (the other
## rows keep a target from earlier scans, which the units' own moves may have taken out of sight
## since, up to 4 ticks later). `outside` collects the ids that broke the rule, `checked` counts the
## targets it looked at. A probe of the game never reads the World; this one is a test's. Not a test
## suite; test_targeting.gd preloads it. It is a file of its own, not an inner class, because an
## inner class with a script base would name itself at run time.

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")

var world: World
var outside: Array[int] = []
var checked: int = 0


func _init(for_world: World = null) -> void:
	world = for_world


func mark(phase: int) -> void:
	if phase != SimProbe.Phase.TARGETING:
		return
	outside.append_array(Rig.outside_sight(world, true))
	for row: int in world.unit_count():
		if world.target[row] != 0 and Rig.is_due(world, row):
			checked += 1
