extends GdUnitTestSuite
## The ATTACK goal rule on a building in the lockstep of the TARGETING kernel (plan row P71b, ADR
## 0017 section 1, ADR 0013 section 5): the lock writes the row's goal from its target's position
## only when the target's type has a speed above 0, and the line re-test of an ATTACK unit tests the
## line to its goal. Two Worlds built by one function, the first on the GDScript phases and the
## second with TARGETING in C++ (alone, with INTEGRATE alone, or with every kernel on), are stepped
## with the same orders and compared after every tick, by the state hash and the full state. The
## cases: an ATTACK on a 1x1, a 2x2 and a 3x3 building behind a wall of rock (the unit goes round
## through a gap, on a field keyed on the approach point, and holds at weapon range), and the two
## artillery cases of the plan (P68c). The tally holds what the run reached.

const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const LockstepRig: GDScript = preload("res://tests/sim/support/lockstep_rig.gd")
const TICKS: int = 700
const ALL: int = -1
const SIZES: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3)]
const MASKS: Array[int] = [SimProbe.Phase.TARGETING, SimProbe.Phase.INTEGRATE, ALL]


## One parameter set per kernel mask and footprint size.
func _sizes() -> Array[Array]:
	var sets: Array[Array] = []
	for mask: int in MASKS:
		for size: Vector2i in SIZES:
			sets.append([mask, size])
	return sets


## One parameter set per kernel mask (TARGETING alone, and every kernel).
func _masks() -> Array[Array]:
	return [[SimProbe.Phase.TARGETING], [ALL]]


## The pair of `build`: the twin, and the World with the kernels attached and `mask` on (a phase,
## or ALL).
func _pair(build: Callable, mask: int, problems: Array[String]) -> Array[World]:
	var worlds: Array[World] = []
	for impl: int in SimImpls.IMPLS:
		var world: World = build.call()
		problems.append_array(SimImpls.use(world, impl))
		if impl == SimImpls.Impl.NATIVE and mask != ALL:
			world.native_phases = 1 << mask
		worlds.append(world)
	return worlds


## Steps both Worlds `ticks` ticks (the first with `first` as the orders of each World, made by the
## Callable); returns "" or the first difference with its tick. `watch` is called with the twin
## after each tick.
func _run(worlds: Array[World], ticks: int, first: Callable, watch: Callable) -> String:
	var loops: Array[MatchLoop] = []
	for world: World in worlds:
		loops.append(MatchLoop.create(null, "", 0, world))
	for tick: int in ticks:
		for index: int in worlds.size():
			var orders: Array[Command] = []
			if tick == 0:
				orders.assign(first.call(worlds[index]))
			loops[index].step(worlds[index], orders)
		var found: String = LockstepRig.difference(worlds[0], worlds[1])
		if found != "":
			return "tick %d: %s" % [tick, found]
		watch.call(worlds[0])
	return ""


func _ids_of(world: World, player: int) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in world.unit_count():
		if world.owner[row] == player and world.type_speed[world.type_index[row]] > 0:
			ids.append(world.unit_id[row])
	return ids


func test_an_attack_on_a_building_behind_rock_agrees_in_both_implementations(
	mask: int, size: Vector2i, _test_parameters := _sizes()
) -> void:
	var problems: Array[String] = []
	var worlds: Array[World] = _pair(Worlds.behind_rock.bind(size.x, size.y), mask, problems)
	assert_array(problems).is_empty()
	var holds: Array[int] = [0, 0]  # Ticks with a unit in HOLD, ticks with a unit in FIELD.
	var watch: Callable = func(world: World) -> void:
		for row: int in world.unit_count():
			holds[0] += int(world.nav_mode[row] == World.NavMode.HOLD)
			holds[1] += int(world.nav_mode[row] == World.NavMode.FIELD)
	var orders: Callable = func(world: World) -> Array[Command]:
		return [Command.attack(1, _ids_of(world, 1), world.unit_id[0])] as Array[Command]
	assert_str(_run(worlds, TICKS, orders, watch)).is_empty()
	var twin: World = worlds[0]
	var reach: int = twin.weapon_range[twin.type_weapon[0]]
	for id: int in _ids_of(twin, 1):
		var row: int = twin.index_of(id)
		var dx: int = twin.pos_x[row] - twin.pos_x[0]
		var dy: int = twin.pos_y[row] - twin.pos_y[0]
		assert_int(twin.nav_mode[row]).is_equal(World.NavMode.HOLD)
		assert_bool(dx * dx + dy * dy <= reach * reach).is_true()
	assert_int(holds[0]).is_greater(0)
	assert_int(holds[1]).is_greater(0)  # They went round the wall on a field.
	assert_int(twin.hp[0]).is_less(twin.type_max_hp[twin.type_index[0]])


func test_the_artillery_cases_agree_in_both_implementations(
	mask: int, _test_parameters := _masks()
) -> void:
	for distance: int in [12000, 2200]:
		var problems: Array[String] = []
		var worlds: Array[World] = _pair(Worlds.artillery_range.bind(distance), mask, problems)
		assert_array(problems).is_empty()
		var shots: Array[int] = [0, 0]  # Shots seen, ticks in HOLD.
		var watch: Callable = func(world: World) -> void:
			var at: int = 0
			while at + World.EVENT_STRIDE <= world.events.size():
				shots[0] += int(world.events[at] == World.Event.SHOT)
				at += World.EVENT_STRIDE
			shots[1] += int(world.nav_mode[1] == World.NavMode.HOLD)
		var orders: Callable = func(world: World) -> Array[Command]:
			var gun: PackedInt32Array = PackedInt32Array([world.unit_id[1]])
			return [Command.attack(1, gun, world.unit_id[0])] as Array[Command]
		(
			assert_str(_run(worlds, 300, orders, watch))
			. override_failure_message("distance %d" % distance)
			. is_empty()
		)
		if distance == 12000:
			assert_int(shots[0]).is_greater(0)
			assert_int(shots[1]).is_greater(100)
		else:
			assert_int(shots[0]).is_equal(0)
			assert_int(shots[1]).is_equal(0)
