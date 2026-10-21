extends GdUnitTestSuite
## What the Command v1 orders do to units before P37 and P41 (ADR 0007 section 5): MOVE, STOP and
## ATTACK with the Phase 1 movement. Literal stats: type 0 has speed 120, type 1 speed 60, both
## armed in the duel world.

const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
## The radii sum of two tanks in the duel world (400 each): closer than this they overlap.
const REACH: int = 800
## The sight of both duel types: the map's width, so that the target of an ATTACK stays in sight
## wherever it runs (the authoring rule of the fog PR, P46b: an ATTACK on an unseen enemy is
## dropped, and a target that leaves sight ends the order).
const SIGHT: int = 48000


## MOVE only differs by its order, so both groups reach the same slots on the same ticks.
func test_move_reaches_the_slots_attack_move_reaches() -> void:
	var ids: PackedInt32Array = PackedInt32Array(range(1, 31))
	var by_attack_move: World = _scenario_world()
	var by_move: World = _scenario_world()
	var start: PackedInt32Array = by_move.pos_x.duplicate()
	Sim.step(by_attack_move, [_stamp(Command.attack_move(1, ids, 22250, 22250), 0)])
	Sim.step(by_move, [_stamp(Command.move(1, ids, 22250, 22250), 0)])
	assert_int(by_attack_move.order.count(World.Order.ATTACK_MOVE)).is_equal(30)
	assert_int(by_move.order.count(World.Order.MOVE)).is_equal(30)
	# All idle by tick 152 with the pushes of the crowd (150 before P39b): tick 165, a multiple of 15.
	for _t: int in 164:
		Sim.step(by_attack_move, [])
		Sim.step(by_move, [])
	assert_int(by_move.order.count(World.Order.IDLE)).is_equal(40)
	assert_array(by_move.pos_x).is_equal(by_attack_move.pos_x)
	assert_array(by_move.pos_y).is_equal(by_attack_move.pos_y)
	assert_array(by_move.goal_x).is_equal(by_attack_move.goal_x)
	assert_bool(by_move.pos_x == start).is_false()  # Not vacuous: the tanks walked.


func test_stop_makes_moving_units_idle_where_they_are() -> void:
	var world: World = _scenario_world()
	Sim.step(world, [_stamp(Command.move(1, PackedInt32Array(range(1, 31)), 40000, 22000), 0)])
	for _t: int in 4:
		Sim.step(world, [])
	world.target[0] = 31
	world.order_target[0] = 31
	world.field[0] = 2
	world.field[10] = 2
	var halted: PackedInt32Array = world.pos_x.slice(0, 10) + world.pos_y.slice(0, 10)
	var going: int = world.pos_x[10]
	Sim.step(world, [_stamp(Command.stop(1, PackedInt32Array(range(1, 11))), world.tick)])
	assert_int(world.dropped_commands).is_equal(0)
	assert_int(world.order.slice(0, 10).count(World.Order.IDLE)).is_equal(10)
	assert_array(world.goal_x.slice(0, 10) + world.goal_y.slice(0, 10)).is_equal(halted)
	assert_array([world.target[0], world.order_target[0], world.field[0]]).is_equal([0, 0, -1])
	# The others are not stopped: they keep their order, their field and their way.
	assert_int(world.order.slice(10, 30).count(World.Order.MOVE)).is_equal(20)
	assert_array([world.field[10], world.pos_x[10] != going]).is_equal([2, true])
	for _t: int in 10:
		Sim.step(world, [])
	assert_array(world.pos_x.slice(0, 10) + world.pos_y.slice(0, 10)).is_equal(halted)


## The attacker (id 2, row 1) is slower than its target (id 1, row 0, player 2), which flees north
## east: it never catches up, and its goal is still the target's position at the start of the tick.
func test_attack_follows_a_moving_target_by_its_position_at_the_start_of_the_tick() -> void:
	assert_int(_chase(1, 0)).is_equal(0)


## A faster attacker catches the target. On arrival it keeps the ATTACK order, so it goes on
## following the target instead of idling next to it. Since P39b it cannot snap onto the target's
## point: SEPARATION holds the two 640 apart, inside the radii sum (800) that counts as caught.
func test_a_faster_attacker_catches_the_target_and_keeps_following_it() -> void:
	assert_int(_chase(0, 1)).is_greater(50)


## A target within one step: the attacker steps onto it at once and stays on ATTACK. Since P39b the
## two overlap, 50 apart, so SEPARATION pushes the pair by the fixed 60 and the moving attacker
## takes the 25% share: it ends 15 short of the target (10035, not 10050).
func test_an_attack_on_a_target_within_one_step_keeps_its_order() -> void:
	var world: World = _duel_world()
	world.add_unit(1, 0, 10000, 10000)
	world.add_unit(2, 1, 10050, 10000)
	Sim.step(world, [_stamp(Command.attack(1, PackedInt32Array([1]), 2), 0)])
	assert_array([world.order[0], world.pos_x[0], world.order_target[0]]).is_equal(
		[World.Order.ATTACK, 10035, 2]
	)


## MOVE, ATTACK_MOVE and STOP need no weapon (only ATTACK does), so an unarmed unit takes them.
func test_an_unarmed_unit_takes_move_attack_move_and_stop() -> void:
	var world: World = _duel_world()
	world.type_weapon[0] = -1
	world.add_unit(1, 0, 10000, 10000)
	var ids: PackedInt32Array = PackedInt32Array([1])
	var commands: Array[Command] = [
		Command.attack_move(1, ids, 20000, 10000), Command.move(1, ids, 20000, 10000)
	]
	var expected: Array[int] = [World.Order.ATTACK_MOVE, World.Order.MOVE]
	for k: int in 2:
		Sim.step(world, [_stamp(commands[k], world.tick)])
		assert_array([world.dropped_commands, world.order[0]]).is_equal([0, expected[k]])
	Sim.step(world, [_stamp(Command.stop(1, ids), world.tick)])
	assert_array([world.dropped_commands, world.order[0]]).is_equal([0, World.Order.IDLE])
	assert_array([world.goal_x[0], world.goal_y[0]]).is_equal([world.pos_x[0], world.pos_y[0]])


## A target that is gone leaves the units on attack-move to where it was last seen (ADR 0009).
func test_attack_on_a_removed_target_becomes_attack_move_to_its_last_position() -> void:
	var world: World = _duel_world()
	world.add_unit(1, 0, 10000, 10000)
	world.add_unit(2, 0, 11000, 10000)
	Sim.step(world, [_stamp(Command.attack(1, PackedInt32Array([1]), 2), 0)])
	assert_array([world.goal_x[0], world.order[0]]).is_equal([11000, World.Order.ATTACK])
	world.hp[1] = 0
	Sim.step(world, [])
	assert_array([world.unit_count(), world.order[0]]).is_equal([1, World.Order.ATTACK])
	Sim.step(world, [])
	assert_array([world.order[0], world.goal_x[0], world.goal_y[0]]).is_equal(
		[World.Order.ATTACK_MOVE, 11000, 10000]
	)
	for _t: int in 20:
		Sim.step(world, [])
	assert_array([world.order[0], world.pos_x[0]]).is_equal([World.Order.IDLE, 11000])


func _scenario_world() -> World:
	return World.from_scenario(load(SCENARIO_PATH) as ScenarioDef)


## No units yet: type 0 (speed 120) and type 1 (speed 60), both with a weapon and SIGHT.
func _duel_world() -> World:
	var world: World = World.new()
	world.map_w = 48000
	world.map_h = 48000
	for speed: int in [120, 60]:
		world.type_ids.append(&"type")
		world.type_speed.append(speed)
		world.type_radius.append(400)
		world.type_selection_radius.append(500)
		world.type_spacing.append(1200)
		world.type_weapon.append(0)
		world.type_sight.append(SIGHT)
	return world


## Player 1's attacker of `attacker_type` (id 2, row 1) chases player 2's target of `target_type`
## (id 1, row 0), which is ordered north east. The target has the lower row, so its move this tick
## would show if the goal were read after the movement. Each tick the goal must be the target's
## position at the start of the tick, on both axes, and the order must stay ATTACK. Returns the
## number of ticks the attacker ended within REACH of that goal (it ended on it before P39b).
func _chase(attacker_type: int, target_type: int) -> int:
	var world: World = _duel_world()
	world.add_unit(2, target_type, 20000, 10000)
	world.add_unit(1, attacker_type, 16000, 13000)
	var commands: Array[Command] = [
		_stamp(Command.attack(1, PackedInt32Array([2]), 1), 0),
		_stamp(Command.move(2, PackedInt32Array([1]), 40000, 3000), 0),
	]
	var caught: int = 0
	for _t: int in 160:
		var seen: Vector2i = Vector2i(world.pos_x[0], world.pos_y[0])
		Sim.step(world, commands)
		commands.clear()
		assert_array([world.goal_x[1], world.goal_y[1]]).is_equal([seen.x, seen.y])
		assert_array([world.order[1], world.order_target[1]]).is_equal([World.Order.ATTACK, 1])
		var gap: Vector2i = Vector2i(
			world.pos_x[1] - world.goal_x[1], world.pos_y[1] - world.goal_y[1]
		)
		if gap.x * gap.x + gap.y * gap.y < REACH * REACH:
			caught += 1
	assert_array([world.dropped_commands, world.pos_y[0] < 10000]).is_equal([0, true])
	return caught


func _stamp(command: Command, tick: int) -> Command:
	command.tick = tick
	return command
