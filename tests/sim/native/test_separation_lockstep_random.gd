extends GdUnitTestSuite
## The SEPARATION kernel against its GDScript twin on seeded random states (ADR 0013 section 4, plan
## P39n2). A state is a map of 1 to 13 x 1 to 11 tiles, one to five unit types with radii of every
## kind (0 to 50, the tank's 400, up to 600 or 3000, below 0), the five separation rules drawn from
## a range that crosses every guard (caps from -2 to 40, an idle share from -60 to 160, a push cap
## from -20 to 2500, a divisor from -3 to 60; one state in five has the shipped rules), 1 to 90
## units in clumps, piles, units next to one another within 3 milli, rows along an edge and units
## outside the map, half of them moving, garbage in the push rows (the rows past the count too) and
## in the work counts, and in a third of them a grid of another cell size (100 to 3000 milli) than
## the tile. The first case compares one SEPARATION phase on each of 1,500 such states (the state
## hash and the full state; in every other state the phase adds its looks to the garbage in the
## work count, as `stats[SEP_PAIRS] +=` says); the second steps 300 of them for 12 ticks through
## MatchLoop, with random orders at ticks 0 and 6, so that the pushes move the units, and compares
## after every tick.
## Every state is the same on the twin's side and the kernel's, and the twin takes all of them
## without error, so a difference is the kernel's. The tallies of the rig's probe, summed over the
## states, show that between them they meet every rule. The arena runs are in
## test_separation_lockstep.gd and the crafted crowds in test_separation_lockstep_cases.gd.

const Rig: GDScript = preload("res://tests/sim/support/separation_lockstep_rig.gd")
const TallyProbe: GDScript = preload("res://tests/sim/support/separation_tally_probe.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const PHASE_STATES: int = 1500
const RUN_STATES: int = 300
const RUN_TICKS: int = 12
const TINY_STATES: int = 600
const WIDE_STATES: int = 300
## What the states must reach, summed over all of them, by tally name (see TallyProbe.count).
const REACHED: Dictionary[StringName, int] = {
	&"hits": 50000,
	&"hit_capped": 2000,
	&"look_capped": 10000,
	&"fixed": 10000,
	&"same_point": 100,
	&"mixed": 20000,
	&"edge_rows": 10000,
	&"pushed": 10000,
	&"at_cap": 3000
}
## What the tiny crowds must reach, summed over all of them.
const REACHED_TINY: Dictionary[StringName, int] = {
	&"hits": 50000,
	&"inside_by_one": 200,
	&"touching": 1000,
	&"same_point": 500,
	&"fixed": 10000,
	&"hit_capped": 5000,
	&"look_capped": 5000
}
## The move classes of the types, in turn.
const CLASSES: Array[int] = [World.MoveClass.TRACKED, World.MoveClass.FOOT, World.MoveClass.WHEELED]
const SHIPPED: Dictionary[StringName, int] = {
	&"separation_neighbours": 8,
	&"separation_scan": 16,
	&"separation_idle_share": 75,
	&"separation_push_max": 60,
	&"separation_coincident_divisor": 4
}


func test_random_states_match_after_one_phase() -> void:
	var total: Dictionary[StringName, int] = _empty_tally()
	for index: int in PHASE_STATES:
		var rig: RefCounted = Rig.new().setup(_random_world.bind(index), _mask(index))
		assert_array(rig.problems).is_empty()
		var found: String = rig.once(index % 2 == 1)
		assert_str(found).override_failure_message("state %d" % index).is_empty()
		_add(total, rig.tally())
	_assert_reached(total)


func test_random_states_match_after_every_tick_of_a_short_run() -> void:
	var total: Dictionary[StringName, int] = _empty_tally()
	for index: int in RUN_STATES:
		var state: int = 20000 + index
		var rig: RefCounted = Rig.new().setup(_random_world.bind(state), _mask(index))
		assert_array(rig.problems).is_empty()
		var found: String = rig.run(RUN_TICKS, _random_orders.bind(state))
		assert_str(found).override_failure_message("state %d" % state).is_empty()
		_add(total, rig.tally())
	_assert_reached(total)


## Dense crowds of tiny units: radii of 1 to 6 milli (a reach of 2 to 12) and 10 to 80 units in a
## box of 6 to 30 milli, so that pairs stand at every squared distance up to the reach, exactly at
## reach * reach - 1 (an overlap with a push of 0, which still takes a place among the neighbours)
## and at reach * reach (no overlap), and on one point by the dozen, under caps of 1 to 8 hits and
## 2 to 24 looks. The caps cut the scan at those boundary pairs. The phase is compared on each
## state, and the tick after it on every fourth.
func test_dense_crowds_of_tiny_units_on_the_overlap_boundary_match() -> void:
	var total: Dictionary[StringName, int] = _empty_tally()
	for index: int in TINY_STATES:
		var rig: RefCounted = Rig.new().setup(_tiny_world.bind(index), _mask(index))
		assert_array(rig.problems).is_empty()
		var found: String = rig.once(index % 2 == 1)
		assert_str(found).override_failure_message("state %d" % index).is_empty()
		if index % 4 == 0:
			found = rig.run(4)
			assert_str(found).override_failure_message("state %d" % index).is_empty()
		_add(total, rig.tally())
	for name: StringName in REACHED_TINY:
		assert_int(total[name]).override_failure_message("reached %s" % name).is_greater(
			REACHED_TINY[name] - 1
		)


## Crowds with a reach far above the square root of 2^31 (46,341): radii of 400 to 1,048,575 milli
## (a reach up to 2,097,150, the top of the range core/separation.h records) for 6 to 14 units in a
## map of one tile, so that all stand in one list and positions are up to 2,000,000 apart; a push
## cap up to 2 * 10^9 and a divisor up to 1000 (reach * divisor stays inside the range). The
## squares, the weight, the products with the distance and with the divisor do not fit 32 bits
## there, and a pass that narrows any of them gives other pushes than the twin.
func test_random_crowds_with_a_reach_above_the_square_of_an_int32_match() -> void:
	var total: Dictionary[StringName, int] = _empty_tally()
	for index: int in WIDE_STATES:
		var rig: RefCounted = Rig.new().setup(_wide_world.bind(index), _mask(index))
		assert_array(rig.problems).is_empty()
		var found: String = rig.once(index % 2 == 1)
		assert_str(found).override_failure_message("state %d" % index).is_empty()
		_add(total, rig.tally())
	assert_int(total[&"hits"]).is_greater(1000)
	assert_int(total[&"fixed"]).is_greater(100)
	assert_int(total[&"pushed"]).is_greater(1000)


## Which phases the kernels' World runs in C++: SEPARATION alone, or with INTEGRATE (the pushes
## then move the units in C++ too).
func _mask(index: int) -> int:
	return Rig.WITH_INTEGRATE if index % 3 == 2 else Rig.ONLY


func _empty_tally() -> Dictionary[StringName, int]:
	var total: Dictionary[StringName, int] = {}
	for name: StringName in TallyProbe.NAMES:
		total[name] = 0
	return total


func _add(total: Dictionary[StringName, int], tally: Dictionary[StringName, int]) -> void:
	for name: StringName in TallyProbe.NAMES:
		total[name] += tally[name]


func _assert_reached(total: Dictionary[StringName, int]) -> void:
	for name: StringName in REACHED:
		assert_int(total[name]).override_failure_message("reached %s" % name).is_greater(
			REACHED[name] - 1
		)


## State number `index`: see the header. The same World each call.
@warning_ignore("integer_division")
func _random_world(index: int) -> World:
	var rng: DetRandom = DetRandom.create(39, 7000 + index)
	var cols: int = 1 + rng.next_int(13)
	var rows: int = 1 + rng.next_int(11)
	var radii: Array[int] = []
	for _type: int in 1 + rng.next_int(5):
		radii.append(_radius(rng))
	var classes: Array = []
	for type: int in radii.size():
		classes.append(CLASSES[type % CLASSES.size()])
	var world: World = GridWorld.from_rows(GridWorld.grass(cols, rows), classes)
	for type: int in radii.size():
		world.type_radius[type] = radii[type]
	_set_rules(world, rng)
	var spread: int = 100 + rng.next_int(cols * 500 + 1500)
	var centre: Vector2i = Vector2i(rng.next_int(cols * 1000), rng.next_int(rows * 1000))
	for _unit: int in 1 + rng.next_int(90):
		var at: Vector2i = _place(world, rng, centre, spread)
		world.add_unit(1, rng.next_int(radii.size()), at.x, at.y)
	for row: int in world.unit_count():
		if rng.next_int(2) == 0:
			world.intent_x[row] = rng.range_int(-120, 120)
			world.intent_y[row] = rng.range_int(-120, 120) if rng.next_int(2) == 0 else 0
	# Garbage in every push row, the ones past the count included, and in the work counts.
	for row: int in world.max_rows:
		world.push_x[row] = rng.range_int(-9, 9)
		world.push_y[row] = rng.range_int(-9, 9)
	world.stats[World.Stat.SEP_PAIRS] = rng.range_int(0, 100)
	if rng.next_int(3) == 0:
		world.sep_grid.configure(world.map_w, world.map_h, 100 + rng.next_int(2900), world.max_rows)
	return world


## Tiny state number `index`: see test_dense_crowds_of_tiny_units_on_the_overlap_boundary_match.
func _tiny_world(index: int) -> World:
	var rng: DetRandom = DetRandom.create(39, 15000 + index)
	var radii: Array[int] = []
	var classes: Array = []
	for type: int in 1 + rng.next_int(4):
		radii.append(rng.range_int(1, 6))
		classes.append(CLASSES[type % CLASSES.size()])
	var world: World = GridWorld.from_rows(GridWorld.grass(2, 2), classes)
	for type: int in radii.size():
		world.type_radius[type] = radii[type]
	var box: int = 6 + rng.next_int(25)
	for _unit: int in 10 + rng.next_int(71):
		var x: int = 600 + rng.next_int(box)
		var y: int = 600 + rng.next_int(box)
		world.add_unit(1, rng.next_int(radii.size()), x, y)
	for row: int in world.unit_count():
		if rng.next_int(3) == 0:
			world.intent_x[row] = rng.range_int(-120, 120)
			world.intent_y[row] = rng.range_int(-120, 120)
	world.separation_neighbours = rng.range_int(1, 8)
	world.separation_scan = rng.range_int(2, 24)
	world.separation_idle_share = rng.range_int(0, 100)
	world.separation_push_max = rng.range_int(1, 80)
	world.separation_coincident_divisor = rng.range_int(1, 8)
	world.stats[World.Stat.SEP_PAIRS] = rng.range_int(0, 100)
	return world


## Wide state number `index` (a reach above 46,341; see the case that uses it).
func _wide_world(index: int) -> World:
	var rng: DetRandom = DetRandom.create(39, 25000 + index)
	var pool: Array[int] = [400, 40000, 60000, 524287, 700000, 1048575]
	var radii: Array[int] = []
	var classes: Array = []
	for type: int in 3:
		radii.append(pool[rng.next_int(pool.size())])
		classes.append(CLASSES[type])
	var world: World = GridWorld.from_rows(GridWorld.grass(1, 1), classes)
	for type: int in radii.size():
		world.type_radius[type] = radii[type]
	var far: int = 100000 + rng.next_int(1900000)
	for _unit: int in 6 + rng.next_int(9):
		var at: Vector2i = Vector2i(rng.next_int(far), rng.next_int(far))
		world.add_unit(1, rng.next_int(radii.size()), at.x, at.y)
	for row: int in world.unit_count():
		if rng.next_int(3) == 0:
			world.intent_x[row] = rng.range_int(-120, 120)
	var caps: Array[int] = [60, 5000, 2000000000]
	var divisors: Array[int] = [1, 2, 4, 16, 1000]
	world.separation_neighbours = rng.range_int(1, 20)
	world.separation_scan = rng.range_int(1, 30)
	world.separation_idle_share = rng.range_int(0, 100)
	world.separation_push_max = caps[rng.next_int(caps.size())]
	world.separation_coincident_divisor = divisors[rng.next_int(divisors.size())]
	return world


## A radius: 0 to 50, a tank's 400, 0 to 600, 0 to 3000 or -700 to -1.
func _radius(rng: DetRandom) -> int:
	match rng.next_int(5):
		0:
			return rng.range_int(0, 50)
		1:
			return 400
		2:
			return rng.range_int(0, 600)
		3:
			return rng.range_int(0, 3000)
	return rng.range_int(-700, -1)


## The five rules: the shipped ones in one state of five, else drawn from a range that crosses
## every guard.
func _set_rules(world: World, rng: DetRandom) -> void:
	var shipped: bool = rng.next_int(5) == 0
	var drawn: Dictionary[StringName, int] = {
		&"separation_neighbours": rng.range_int(-2, 40),
		&"separation_scan": rng.range_int(-2, 40),
		&"separation_idle_share": rng.range_int(-60, 160),
		&"separation_push_max": rng.range_int(-20, 2500),
		&"separation_coincident_divisor": rng.range_int(-3, 60)
	}
	for member: StringName in drawn:
		world.set(member, SHIPPED[member] if shipped else drawn[member])


## A point for the next unit: a clump around `centre` (most of the units), a pile on or within 3
## milli of an earlier unit, a point along one edge of the map or one outside the map.
func _place(world: World, rng: DetRandom, centre: Vector2i, spread: int) -> Vector2i:
	var pick: int = rng.next_int(8)
	if pick == 0 and world.unit_count() > 0:
		var other: int = rng.next_int(world.unit_count())
		var jitter: Vector2i = Vector2i(rng.range_int(-3, 3), rng.range_int(-3, 3))
		return Vector2i(world.pos_x[other], world.pos_y[other]) + jitter
	if pick == 1:
		return _along_an_edge(world, rng)
	if pick == 2:
		var margin: int = 1500
		return Vector2i(
			rng.range_int(-margin, world.map_w + margin),
			rng.range_int(-margin, world.map_h + margin)
		)
	return centre + Vector2i(rng.range_int(-spread, spread), rng.range_int(-spread, spread))


## A point within 40 milli of one of the four edges of the map.
func _along_an_edge(world: World, rng: DetRandom) -> Vector2i:
	var along: Vector2i = Vector2i(rng.next_int(world.map_w), rng.next_int(world.map_h))
	var depth: int = rng.next_int(40)
	match rng.next_int(4):
		0:
			return Vector2i(depth, along.y)
		1:
			return Vector2i(world.map_w - 1 - depth, along.y)
		2:
			return Vector2i(along.x, depth)
	return Vector2i(along.x, world.map_h - 1 - depth)


## The orders of state number `state` at ticks 0 and 6: a random third of the units to a random
## point of the map. The same for both Worlds of a pair (drawn from the state and the tick).
func _random_orders(world: World, tick: int, state: int) -> Array[Command]:
	var out: Array[Command] = []
	if tick == 0 or tick == 6:
		var rng: DetRandom = DetRandom.create(39, 9000 + state * 16 + tick)
		var ids: PackedInt32Array = PackedInt32Array()
		for row: int in world.unit_count():
			if rng.next_int(3) == 0:
				ids.append(world.unit_id[row])
		out.append(Command.move(1, ids, rng.next_int(world.map_w), rng.next_int(world.map_h)))
	return out
