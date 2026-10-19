extends RefCounted
## The separation part of the tick for the tests of P39: the phases in the pipeline order of ADR
## 0007 section 4, without the ones that do not touch positions (`Sim.step` has run them too since
## P39b; the single-phase cases here call `Separation.run` on the units as they stand). Not a test
## suite.


## The grid rebuild and `Separation.run`, as the GRIDS and SEPARATION phases do them in `Sim.step`
## since P39b: the pushes of the units as they stand.
static func separate(world: World) -> void:
	world.sep_grid.rebuild(world.pos_x, world.pos_y, world.unit_count())
	Separation.run(world)


## One tick: clear the work counts, `Movement.run`, the grid, `Separation.run`,
## `Movement.integrate`, then count the tick.
static func tick(world: World) -> void:
	world.stats.fill(0)
	Movement.run(world)
	separate(world)
	Movement.integrate(world)
	world.tick += 1


## `count` ticks.
static func ticks(world: World, count: int) -> void:
	for _tick: int in count:
		tick(world)


## The squared distance between rows `a` and `b`.
static func distance2(world: World, a: int, b: int) -> int:
	var dx: int = world.pos_x[a] - world.pos_x[b]
	var dy: int = world.pos_y[a] - world.pos_y[b]
	return dx * dx + dy * dy


## The pairs of rows (a, b), a < b, that stand closer than `percent` percent of the sum of their two
## radii, in ascending order: a test asserts the list is empty, so a failure names the pairs.
static func pairs_closer_than(world: World, percent: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var count: int = world.unit_count()
	for a: int in count:
		var radius: int = world.type_radius[world.type_index[a]]
		for b: int in range(a + 1, count):
			var reach: int = (radius + world.type_radius[world.type_index[b]]) * percent
			# d < sum * percent / 100 is d2 * 10000 < (sum * percent) squared.
			if distance2(world, a, b) * 10000 < reach * reach:
				found.append(Vector2i(a, b))
	return found


## How long pairs stay overlapped. `runs` holds one counter per pair of rows (index a * count + b,
## a < b; `count * count` zeros at the start). Call it after each step: a pair that stands closer
## than `percent` percent of its radii sum gets its counter raised by one, any other pair's counter
## goes back to 0. Returns the longest run of any pair after this update, so a test keeps the
## maximum over a drive.
static func track_overlaps(world: World, percent: int, runs: PackedInt32Array) -> int:
	var longest: int = 0
	var count: int = world.unit_count()
	for a: int in count:
		var radius: int = world.type_radius[world.type_index[a]]
		for b: int in range(a + 1, count):
			var reach: int = (radius + world.type_radius[world.type_index[b]]) * percent
			var index: int = a * count + b
			if distance2(world, a, b) * 10000 < reach * reach:
				runs[index] += 1
				longest = maxi(longest, runs[index])
			else:
				runs[index] = 0
	return longest
