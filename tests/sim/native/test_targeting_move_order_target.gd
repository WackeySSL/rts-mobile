extends GdUnitTestSuite
## P262 (ADR 0036 section 8): TARGETING, in the GDScript twin and in the C++ kernel, leaves the
## `order_target` of a MOVE row alone. LOAD marks a squad "board on arrival" with a MOVE row whose
## `order_target` is the carrier's id, and nothing may clear it on the way. Only an ATTACK row
## writes `order_target` in that phase (it falls back to attack-move and clears the lock), so the
## BOARD order value that section 8 keeps as the fallback is not needed. The squad is armed and an
## enemy stands in its range the whole time, so a phase that reset the column would show, and an
## idle row beside it does acquire that enemy (the control).

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const CARRIER: int = 3
const TICKS: int = 40


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


func test_a_move_row_keeps_its_order_target_through_targeting(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world()
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.TARGETING)).is_empty()
	var squad: int = world.add_unit(1, 0, 2500, 2500)
	var enemy: int = world.add_unit(2, 0, 4500, 2500)
	var carrier: int = world.add_unit(1, 0, 20500, 2500)
	var watcher: int = world.add_unit(1, 0, 3500, 4500)  # Idle beside the squad: the control.
	assert_int(carrier).is_equal(CARRIER)
	var order: Command = Command.move(1, PackedInt32Array([squad]), 18500, 2500)
	order.tick = world.tick
	var first: Array[Command] = [order]
	Sim.step(world, first)
	var row: int = world.index_of(squad)
	world.order_target[row] = carrier  # What Carry's LOAD writes after the MOVE.
	for tick: int in TICKS:
		Sim.step(world, [])
		row = world.index_of(squad)
		var message: String = "impl %d tick %d" % [impl, tick]
		assert_int(world.order[row]).override_failure_message(message).is_equal(World.Order.MOVE)
		assert_int(world.order_target[row]).override_failure_message(message).is_equal(carrier)
		assert_int(world.target[row]).override_failure_message(message).is_equal(0)
	# The control: the same phase did find the enemy for an idle row, so the world is live.
	assert_int(world.target[world.index_of(watcher)]).is_equal(enemy)


## The squad arrives (the MOVE ends and the row goes IDLE) with an enemy in range: TARGETING then
## acquires it, and still leaves `order_target`, the carrier a boarding squad is bound for.
func test_an_arrived_row_keeps_its_order_target_while_it_acquires(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world()
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.TARGETING)).is_empty()
	var squad: int = world.add_unit(1, 0, 2500, 2500)
	var enemy: int = world.add_unit(2, 0, 7500, 2500)
	var carrier: int = world.add_unit(1, 0, 4500, 4500)
	var order: Command = Command.move(1, PackedInt32Array([squad]), 4500, 2500)  # Two tiles.
	order.tick = world.tick
	var first: Array[Command] = [order]
	Sim.step(world, first)
	world.order_target[world.index_of(squad)] = carrier
	for _tick: int in TICKS:
		Sim.step(world, [])
	var row: int = world.index_of(squad)
	assert_int(world.order[row]).is_equal(World.Order.IDLE)
	assert_int(world.order_target[row]).is_equal(carrier)
	assert_int(world.target[row]).is_equal(enemy)


## An armed type 0 (range 6 tiles, a slow shell), players 1 and 2, a 24 x 6 map of grass.
func _world() -> World:
	var rows: PackedStringArray = GridWorld.grass(24, 6)
	var world: World = GridWorld.from_rows(rows, [World.MoveClass.FOOT])
	world.player_count = 2
	world.type_max_hp[0] = 100
	world.type_acquire[0] = 6000
	world.type_weapon[0] = 0
	world.weapon_range.append(6000)
	world.weapon_min_range.append(0)
	world.weapon_damage.append(1)
	world.weapon_cooldown.append(30)
	world.weapon_projectile_speed.append(0)
	world.weapon_targets.append(World.Layer.GROUND)
	for _armour: int in 4:
		world.weapon_vs_armour.append(100)
	return world
