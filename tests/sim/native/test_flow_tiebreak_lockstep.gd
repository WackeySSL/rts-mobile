extends GdUnitTestSuite
## The equal-cost tie-break of best_neighbour (seat symmetry, ADR 0033) in the C++ kernel against
## its GDScript twin (ADR 0013 section 4). A 24 x 24 map of random rock (a fifth of the tiles, so
## many open tiles have several equal steps), the same map turned by a half turn with its goal, and
## a unit on every open tile looking up its next tile in one pass of Movement.integrate. The two
## implementations agree on both Worlds (the state hash and the full state), and on each
## implementation the next tile of every unit of the turned World is the half turn of the next tile
## of its twin on the original.

const LockstepRig: GDScript = preload("res://tests/sim/support/lockstep_rig.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const TRACKED: int = World.MoveClass.TRACKED
const MOVE: int = World.Order.MOVE
const FIELD: int = World.NavMode.FIELD
const SIDE: int = 24
const SEEDS: Array[int] = [5, 17, 71]
const BIG: int = 100000


func test_the_kernel_breaks_equal_cost_ties_like_the_twin_and_turns_with_the_map() -> void:
	for seed: int in SEEDS:
		var rock: Array[Vector2i] = _rock(seed)
		var goal: Vector2i = Vector2i(seed % SIDE, (seed * 3) % SIDE)
		rock.erase(goal)
		var turned_rock: Array[Vector2i] = []
		for tile: Vector2i in rock:
			turned_rock.append(_half(tile))
		var pair: Array[World] = _pair(rock, goal)
		var turned: Array[World] = _pair(turned_rock, _half(goal))
		for index: int in pair.size():
			Movement.integrate(pair[index])
			Movement.integrate(turned[index])
		for both: Array[World] in [pair, turned]:
			var found: String = LockstepRig.difference(both[0], both[1])
			assert_str(found).override_failure_message("seed %d" % seed).is_empty()
		for index: int in pair.size():
			_assert_turned(pair[index], turned[index], "seed %d, impl %d" % [seed, index])
		# Not vacuous: most open tiles named a next tile.
		assert_int(pair[1].nav_next.count(-2)).is_less(3)


## About a fifth of the tiles, rock, from `seed`.
func _rock(seed: int) -> Array[Vector2i]:
	var rng: DetRandom = DetRandom.create(seed, 1)
	var found: Array[Vector2i] = []
	for cell: int in SIDE * SIDE:
		if rng.next_int(5) == 0:
			found.append(Vector2i(cell % SIDE, cell / SIDE))
	return found


func _half(tile: Vector2i) -> Vector2i:
	return Vector2i(SIDE - 1 - tile.x, SIDE - 1 - tile.y)


## The twin's and the kernel's World for `rock` and the field of `goal`.
func _pair(rock: Array[Vector2i], goal: Vector2i) -> Array[World]:
	var problems: Array[String] = []
	var build: Callable = func() -> World: return _world(rock, goal)
	var found: Array[World] = LockstepRig.pair(build, false, problems)
	assert_array(problems).is_empty()
	return found


## The tank field of `goal` integrated, and a unit on every open tile following it (tick 9).
func _world(rock: Array[Vector2i], goal: Vector2i) -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(SIDE, SIDE, rock), [TRACKED])
	var key: int = goal.y * SIDE + goal.x
	assert_int(world.flow.acquire(key, TRACKED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	for cell: int in SIDE * SIDE:
		if not world.is_passable(cell, TRACKED):
			continue
		var row: int = world.add_unit(1, 0, cell % SIDE * 1000 + 500, cell / SIDE * 1000 + 500) - 1
		world.order[row] = MOVE
		world.nav_mode[row] = FIELD
		world.field[row] = 0
		world.goal_x[row] = goal.x * 1000 + 500
		world.goal_y[row] = goal.y * 1000 + 800
	FlowCache.run(world, 0)
	world.tick = 9
	return world


## The next tile of the unit on each tile.
func _next_by_tile(world: World) -> Dictionary[int, int]:
	var found: Dictionary[int, int] = {}
	for row: int in world.unit_count():
		found[world.pos_y[row] / 1000 * SIDE + world.pos_x[row] / 1000] = world.nav_next[row]
	return found


func _assert_turned(world: World, turned: World, label: String) -> void:
	var original: Dictionary[int, int] = _next_by_tile(world)
	var mirrored: Dictionary[int, int] = _next_by_tile(turned)
	var cells: int = SIDE * SIDE
	assert_int(mirrored.size()).override_failure_message(label).is_equal(original.size())
	for cell: int in original:
		var next: int = original[cell]
		var expected: int = next if next < 0 else cells - 1 - next
		(
			assert_int(mirrored[cells - 1 - cell])
			. override_failure_message("%s, tile %d" % [label, cell])
			. is_equal(expected)
		)
