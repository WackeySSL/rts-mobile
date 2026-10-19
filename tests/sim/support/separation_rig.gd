extends RefCounted
## The separation part of the tick for the tests of P39 (`Sim.step` does not separate until
## P39b): the phases in the pipeline order of ADR 0007 section 4, without the ones that do not
## touch positions. Not a test suite.


## The grid rebuild and `Separation.run`, as the GRIDS and SEPARATION phases will do them: the
## pushes of the units as they stand.
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
