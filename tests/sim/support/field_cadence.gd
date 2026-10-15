extends RefCounted
## Runs unit 1 of a World along a flow field with a counting slot in slot 0 and checks that
## Movement asks `best_neighbour` at event cadence only (P37b; ADR 0008 section 2, ADR 0013 section
## 1). On a tick on which the unit follows slot 0 and the field is complete, the asks are: one if
## `nav_next` was -1 or the unit's line-check turn ((tick + id) % 5) comes (INTEGRATE, before the
## step, for the tile the unit stood in), and one if the step took the unit into a new tile (for
## the new tile). On every other tick there is no ask and `nav_next` keeps its value. Not a test
## suite: the test asserts on what `run` returns.

const CountingField: GDScript = preload("res://tests/sim/support/counting_field.gd")


## Steps `world` for up to `ticks` ticks with `order` given on tick 0 (stamped by this function).
## Slot 0 of the cache is replaced by a counting slot. Returns
## - "violations": one line per tick on which the asks or `nav_next` broke the rule (empty = ok),
## - "followed": the ticks the unit followed slot 0 (FIELD),
## - "lookups": the asks over the run,
## - "entry", "turn", "completion": the ticks of each kind of event on which the field was complete
##   (a completion is the tick the field turned complete).
static func run(world: World, order: Command, ticks: int) -> Dictionary:
	var counting: CountingField = CountingField.new()
	counting.reserve(world.map_cols, world.map_rows)
	world.flow.fields[0] = counting
	var violations: Array[String] = []
	var followed: int = 0
	var seen: Dictionary = {"entry": 0, "turn": 0, "completion": 0}
	for tick: int in ticks:
		var commands: Array[Command] = []
		if tick == 0:
			order.tick = 0
			commands.append(order)
		var cell_before: int = world.cell_of(world.pos_x[0], world.pos_y[0])
		var next_before: int = world.nav_next[0]
		var asked_before: int = counting.lookups
		var complete_before: bool = counting.complete
		Sim.step(world, commands)
		var asked: int = counting.lookups - asked_before
		if world.nav_mode[0] != World.NavMode.FIELD or world.field[0] != 0:
			if world.order[0] == World.Order.IDLE:
				break
			continue
		followed += 1
		var cell: int = world.cell_of(world.pos_x[0], world.pos_y[0])
		var entered: bool = cell != cell_before
		var turn: bool = (tick + 1) % 5 == 0
		var completed_now: bool = counting.complete and not complete_before
		var first: bool = (next_before == -1 or turn) and counting.complete
		var expected_asks: int = (1 if first else 0) + (1 if entered and counting.complete else 0)
		var label: String = "tick %d: " % tick
		if asked != expected_asks:
			violations.append(label + "asked %d, expected %d" % [asked, expected_asks])
		seen["entry"] += 1 if entered and counting.complete else 0
		seen["turn"] += 1 if turn and counting.complete else 0
		seen["completion"] += 1 if completed_now else 0
		var expected: int = next_before
		if expected_asks > 0:
			counting.counted = false
			var named: int = counting.best_neighbour(cell)
			counting.counted = true
			expected = named if named >= 0 else Movement.NO_NEXT
		if world.nav_next[0] != expected:
			violations.append(label + "nav_next %d, expected %d" % [world.nav_next[0], expected])
	return {
		"violations": violations,
		"followed": followed,
		"lookups": counting.lookups,
		"entry": seen["entry"],
		"turn": seen["turn"],
		"completion": seen["completion"],
	}
