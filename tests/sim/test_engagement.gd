extends GdUnitTestSuite
## Engagement (P41b; ADR 0009 sections 2 and 3, ADR 0007 section 4): what a unit does with the
## target that `Targeting.run` gives it, through `Sim.step`. The `ATTACK` order locks its target and
## falls back to an attack-move to the target's last position when the target is gone; a unit with
## a target in weapon range holds (`HOLD`), an attack-moving unit with a target out of range chases
## it (`CHASE`) while the line is clear, and a unit that loses its target resumes its path. The
## rock cases (a line that is blocked) are in test_engagement_rock.gd; acquisition is in
## test_targeting.gd.
## Units in range fire since P42a (FIRE), and none of these cases runs long enough for anyone to
## die: the cases assert range, mode and position, not damage (the fights: test_combat_fights.gd).
##
## The worlds are the shipped unit types (TargetingRig.data_world): rifle squad 0 (range 4000,
## acquire 5000, sight 6000, speed 67), rocket squad 1, light tank 2 (range 4500, acquire 5500,
## sight 7000, speed 120) on an open 20 x 12 tile map. Every `ATTACK` target stands inside its
## attacker's sight, the authoring rule of the fog PR (P46b). A unit scans on the ticks where
## `(tick + id) % 5 == 0`, and checks its lines on the same ticks.
##
## Every case runs under both implementations (ADR 0013 section 3, P41n): the GDScript phase and the
## C++ kernel, through `_both()` and `_in()`. The kernel-only cases are in
## tests/sim/native/test_targeting_kernel*.gd.

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const ViewProbe: GDScript = preload("res://tests/sim/support/targeting_view_probe.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const TARGETING: int = SimProbe.Phase.TARGETING
const RIFLE: int = 0
const TANK: int = 2
const IDLE: int = World.Order.IDLE
const ATTACK_MOVE: int = World.Order.ATTACK_MOVE
const MOVE: int = World.Order.MOVE
const ATTACK: int = World.Order.ATTACK
const NONE: int = World.NavMode.NONE
const DIRECT: int = World.NavMode.DIRECT
const HOLD: int = World.NavMode.HOLD
const CHASE: int = World.NavMode.CHASE


## The row of an `ATTACK` order keeps the target it was given, past the acquire range (6500 away,
## the tank's is 5500) and over an enemy that stands nearer (id 3, 3606 away, which an attack-moving
## tank would take), on every tick, the due ones included. Its order and `order_target` stay.
func test_an_attack_row_locks_its_target_beyond_acquire_range_and_over_a_nearer_enemy(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(Rig.data_world(), impl)
	world.add_unit(1, TANK, 4000, 6000)
	world.add_unit(2, RIFLE, 10500, 6000)
	world.add_unit(2, RIFLE, 6000, 9000)
	Sim.step(world, [_order(Command.attack(1, PackedInt32Array([1]), 2), world)])
	var due_ticks: int = 0
	for _tick: int in 40:
		assert_int(world.target[0]).override_failure_message("tick %d" % world.tick).is_equal(2)
		assert_array([world.order[0], world.order_target[0]]).is_equal([ATTACK, 2])
		due_ticks += 1 if Rig.is_due(world, 0) else 0
		Sim.step(world, [])
	assert_int(due_ticks).is_equal(8)
	assert_array(Rig.outside_sight(world)).is_empty()


## An `ATTACK` row's goal is its target's position as it stands at the start of the tick, already at
## the TARGETING mark (P33's stand-in set it after that mark, inside INTENTS): the goal is the
## unit's own position at the GRIDS mark, the target's at the TARGETING mark, and the target's new
## position the tick after the target was moved by hand.
func test_the_goal_of_an_attack_row_is_its_targets_position_at_the_targeting_mark(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(Rig.data_world(), impl)
	world.add_unit(1, TANK, 4000, 6000)
	world.add_unit(2, RIFLE, 10500, 6000)
	var probe: ViewProbe = ViewProbe.new(world)
	Sim.step(world, [_order(Command.attack(1, PackedInt32Array([1]), 2), world)], probe)
	assert_int(probe.goals[probe.phases.find(SimProbe.Phase.GRIDS)]).is_equal(4000)
	assert_int(probe.goals[probe.phases.find(SimProbe.Phase.TARGETING)]).is_equal(10500)
	assert_int(probe.targets[probe.phases.find(SimProbe.Phase.TARGETING)]).is_equal(2)
	world.pos_x[1] = 10000
	world.pos_y[1] = 8000
	Sim.step(world, [])
	assert_array([world.goal_x[0], world.goal_y[0]]).is_equal([10000, 8000])


## When the target is gone the order becomes an attack-move to the target's last position: the
## target is removed at the end of one tick (it was alive, and locked, during that tick), and the
## next tick finds it missing. The order is `ATTACK_MOVE`, `order_target` and `target` are 0 and the
## goal is where the target stood at the start of its last tick (it was walking east, 67 a tick).
## The tank then drives there and arrives: idle on the goal.
func test_a_target_that_is_gone_makes_the_attack_an_attack_move_to_its_last_position(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(Rig.data_world(), impl)
	world.add_unit(1, TANK, 2000, 6000)
	world.add_unit(2, RIFLE, 9000, 6000)
	var go: Command = Command.move(2, PackedInt32Array([2]), 15000, 6000)
	Sim.step(world, [_order(Command.attack(1, PackedInt32Array([1]), 2), world), _order(go, world)])
	for _tick: int in 5:
		Sim.step(world, [])
	var last: Vector2i = Vector2i(world.pos_x[1], world.pos_y[1])
	assert_int(last.x).is_greater(9000)
	world.hp[1] = 0
	Sim.step(world, [])
	assert_int(world.unit_count()).is_equal(1)
	assert_array([world.order[0], world.target[0]]).is_equal([ATTACK, 2])
	assert_array([world.goal_x[0], world.goal_y[0]]).is_equal([last.x, last.y])
	Sim.step(world, [])
	assert_array([world.order[0], world.order_target[0], world.target[0]]).is_equal(
		[ATTACK_MOVE, 0, 0]
	)
	assert_array([world.goal_x[0], world.goal_y[0]]).is_equal([last.x, last.y])
	for _tick: int in 200:
		if world.order[0] == IDLE:
			break
		Sim.step(world, [])
	assert_array([world.order[0], world.pos_x[0], world.pos_y[0]]).is_equal([IDLE, last.x, last.y])
	assert_int(world.nav_mode[0]).is_equal(NONE)


## The fallback row is an attack-moving row from the tick it falls back: it scans on its next due
## tick (id 1 is due at tick 4), and takes the enemy 3000 away (id 3) then, not before. Starting
## the fallback at tick 0, which is not due, the row has no target until tick 4; starting it at tick
## 4, the same tick that makes it an attack-moving row takes the enemy.
func test_the_fallback_row_scans_on_its_next_due_tick(
	impl: int, _test_parameters := _both()
) -> void:
	for start: int in [0, 4]:
		var world: World = _in(Rig.data_world(), impl)
		world.add_unit(1, TANK, 6000, 6000)
		world.add_unit(2, RIFLE, 12000, 6000)
		world.add_unit(2, RIFLE, 9000, 6000)
		world.order[0] = ATTACK
		world.order_target[0] = 2
		world.goal_x[0] = 12000
		world.hp[1] = 0
		world.remove_dead()
		world.tick = start
		var label: String = "fallback at tick %d" % start
		for tick: int in range(start, 5):
			Sim.step(world, [])
			var scanned: bool = tick == 4
			assert_array([world.order[0], world.order_target[0]]).is_equal([ATTACK_MOVE, 0])
			assert_int(world.target[0]).override_failure_message(label).is_equal(
				3 if scanned else 0
			)
		assert_int(world.tick).is_equal(5)


## The lock is on an enemy: an `ATTACK` row whose order target is a unit of its own side (id 2) or a
## neutral one (id 3, owner 0), which no command gives it, falls back to an attack-move at once.
func test_an_order_target_that_is_not_an_enemy_falls_back(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(Rig.data_world(), impl)
	world.add_unit(1, TANK, 4000, 6000)
	world.add_unit(1, RIFLE, 6000, 6000)
	world.add_unit(0, RIFLE, 6000, 8000)
	world.goal_x[0] = 12000
	for friend_or_neutral: int in [2, 3]:
		world.order[0] = ATTACK
		world.order_target[0] = friend_or_neutral
		Sim.step(world, [])
		var label: String = "order target %d" % friend_or_neutral
		(
			assert_array([world.order[0], world.order_target[0]])
			. override_failure_message(label)
			. is_equal([ATTACK_MOVE, 0])
		)


## The line to the target is checked on the unit's line-check turn, whatever the scan period: with
## `line_check_period_ticks` 3 and a scan every tick, the squad (id 1: turns at ticks 2, 5, 8) has
## its target from tick 0 and starts to chase at tick 2, not before; with a line-check period of 1
## it chases from tick 0.
func test_the_chase_line_is_checked_on_the_line_check_period_not_the_scan_period(
	impl: int, _test_parameters := _both()
) -> void:
	for period: int in [3, 1]:
		var world: World = _in(Rig.data_world(), impl)
		world.retarget_period_ticks = 5 if period == 1 else 1
		world.line_check_period_ticks = period
		world.add_unit(1, RIFLE, 6000, 6000)
		world.add_unit(2, RIFLE, 10800, 6000)
		world.order[0] = ATTACK_MOVE
		world.goal_x[0] = 14000
		world.tick = 0 if period == 3 else 4
		var first: int = world.tick
		var chased_at: int = -1
		for _tick: int in 6:
			Sim.step(world, [])
			if chased_at < 0 and world.nav_mode[0] == CHASE:
				chased_at = world.tick - 1
		assert_int(chased_at).override_failure_message("period %d" % period).is_equal(
			2 if period == 3 else first
		)


## An `ATTACK` unit drives at its target and holds in weapon range, and the idle target is not
## shoved: tank 1 starts 6500 from idle tank 2 and holds 4500 or less (and more than 4500 minus a
## step of 120) from it, `HOLD`, intent 0, order `ATTACK`. It was never `CHASE` on the way (an
## `ATTACK` unit steers by the navigation of its order). The target stays where it stood, also with
## the pushes of the tick on (the units never come within the radii sum), and holds too.
func test_an_attack_unit_drives_to_weapon_range_and_holds_and_the_target_stays_put(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(Rig.data_world(), impl)
	world.add_unit(1, TANK, 2000, 6000)
	world.add_unit(2, TANK, 8500, 6000)
	var chased: bool = false
	Sim.step(world, [_order(Command.attack(1, PackedInt32Array([1]), 2), world)])
	for _tick: int in 60:
		Sim.step(world, [])
		chased = chased or world.nav_mode[0] == CHASE
	assert_bool(chased).is_false()
	var gap: int = world.pos_x[1] - world.pos_x[0]
	assert_int(gap).is_between(4500 - 120 + 1, 4500)
	assert_array([world.nav_mode[0], world.order[0], world.intent_x[0]]).is_equal([HOLD, ATTACK, 0])
	assert_array([world.pos_x[1], world.pos_y[1]]).is_equal([8500, 6000])
	assert_array([world.nav_mode[1], world.target[1]]).is_equal([HOLD, 1])
	var held: Vector2i = Vector2i(world.pos_x[0], world.pos_y[0])
	for _tick: int in 30:
		Sim.step(world, [])
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([held.x, held.y])
	assert_array(Rig.outside_sight(world)).is_empty()


## An `ATTACK` unit leaves `HOLD` when its target steps out of weapon range, as an attack-moving
## one does: tank 1 holds at 4500 or less from idle tank 2, the target is moved by hand to 4800
## from it (inside the 7000 of its sight), and on the next tick the tank is `DIRECT` with the
## navigation of a new order (no field, line unchecked) and steps towards the target, then holds
## again once it is back in range, still on its `ATTACK` order and target.
func test_an_attack_unit_leaves_hold_when_its_target_steps_out_of_range(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(Rig.data_world(), impl)
	world.add_unit(1, TANK, 2000, 6000)
	world.add_unit(2, TANK, 8500, 6000)
	Sim.step(world, [_order(Command.attack(1, PackedInt32Array([1]), 2), world)])
	for _tick: int in 60:
		Sim.step(world, [])
	assert_int(world.nav_mode[0]).is_equal(HOLD)
	var held_x: int = world.pos_x[0]
	world.pos_x[1] = held_x + 4800
	Sim.step(world, [])
	assert_array([world.nav_mode[0], world.field[0], world.order[0]]).is_equal([DIRECT, -1, ATTACK])
	assert_int(world.intent_x[0]).is_equal(120)
	assert_int(world.pos_x[0]).is_equal(held_x + 120)
	for _tick: int in 4:
		Sim.step(world, [])
	assert_array([world.nav_mode[0], world.target[0], world.intent_x[0]]).is_equal([HOLD, 2, 0])
	assert_int(world.pos_x[1] - world.pos_x[0]).is_between(4500 - 120 + 1, 4500)
	assert_array(Rig.outside_sight(world)).is_empty()


## An attack-moving rifle squad that acquires an enemy out of weapon range (4800 away, acquire is
## 5000, range 4000) chases it: `CHASE` from the acquiring tick (4, which is also its line-check
## turn), then `HOLD` the first tick the enemy is within 4000, and it stays there: its position and
## intent do not change, its order and goal are the attack-move's, and the enemy, idle, holds as
## well once the squad is in its range.
func test_an_attack_moving_unit_chases_a_target_out_of_range_then_holds(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(Rig.data_world(), impl)
	world.add_unit(1, RIFLE, 6000, 6000)
	world.add_unit(2, RIFLE, 10800, 6000)
	Sim.step(world, [_order(Command.attack_move(1, PackedInt32Array([1]), 14000, 6000), world)])
	var goal: Vector2i = Vector2i(world.goal_x[0], world.goal_y[0])
	var chased_ticks: int = 0
	var held_at: int = -1
	for _tick: int in 60:
		Sim.step(world, [])
		if world.nav_mode[0] == CHASE:
			chased_ticks += 1
			assert_int(world.tick).is_greater(4)
			assert_int(world.target[0]).is_equal(2)
		elif world.nav_mode[0] == HOLD and held_at < 0:
			held_at = world.tick
	assert_int(chased_ticks).is_greater(5)
	assert_int(held_at).is_greater(0)
	var gap: int = world.pos_x[1] - world.pos_x[0]
	assert_int(gap).is_between(4000 - 67 + 1, 4000)
	assert_array([world.nav_mode[0], world.order[0], world.intent_x[0]]).is_equal(
		[HOLD, ATTACK_MOVE, 0]
	)
	assert_array([world.goal_x[0], world.goal_y[0]]).is_equal([goal.x, goal.y])
	assert_array([world.nav_mode[1], world.target[1]]).is_equal([HOLD, 1])
	assert_array([world.pos_x[1], world.pos_y[1]]).is_equal([10800, 6000])


## A holding unit whose target leaves its weapon range (moved by hand to 4600, still inside the
## acquire range of 5000 that an attack-moving unit keeps a target within) leaves `HOLD` the next
## tick with the navigation of a new order: on a tick that is not its line-check turn it is
## `DIRECT` with the line unchecked, on its turn it chases (the line is clear).
func test_a_held_unit_leaves_hold_when_the_target_steps_out_of_range(
	impl: int, _test_parameters := _both()
) -> void:
	for tick: int in [10, 14]:
		var world: World = _holding_pair(impl)
		world.nav_cell[0] = 77
		world.nav_next[0] = 55
		world.best_dist[0] = 5
		world.stall[0] = 3
		world.pos_x[1] = world.pos_x[0] + 4600
		world.tick = tick
		Sim.step(world, [])
		var label: String = "tick %d" % tick
		var turn: bool = (tick + 1) % 5 == 0
		assert_int(world.nav_mode[0]).override_failure_message(label).is_equal(
			CHASE if turn else DIRECT
		)
		assert_int(world.target[0]).is_equal(2)
		assert_array([world.field[0], world.nav_next[0], world.stall[0]]).is_equal([-1, -1, 0])
		assert_int(world.best_dist[0]).is_equal(FlowField.UNREACHED)
		assert_int(world.nav_cell[0]).override_failure_message(label).is_equal(-1)
		assert_bool(world.intent_x[0] != 0).override_failure_message(label).is_true()


## A unit that loses its target while it holds resumes its path to its goal, with the navigation of
## a new order, and arrives: the target is removed, the next tick has the unit `DIRECT` (line
## unchecked, `HOLD` gone), and the rifle squad drives on to its goal, where it arrives idle.
func test_a_unit_that_loses_its_target_resumes_its_path_and_arrives(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _holding_pair(impl)
	var goal: Vector2i = Vector2i(world.goal_x[0], world.goal_y[0])
	assert_int(world.nav_mode[0]).is_equal(HOLD)
	world.hp[1] = 0
	Sim.step(world, [])
	assert_int(world.unit_count()).is_equal(1)
	Sim.step(world, [])
	assert_array([world.nav_mode[0], world.order[0]]).is_equal([DIRECT, ATTACK_MOVE])
	assert_int(world.intent_x[0]).is_not_equal(0)
	for _tick: int in 300:
		if world.order[0] == IDLE:
			break
		Sim.step(world, [])
	assert_array([world.order[0], world.pos_x[0], world.pos_y[0]]).is_equal([IDLE, goal.x, goal.y])


## A chasing unit whose target is gone leaves `CHASE` on the next tick, which `Movement.run` alone
## does not do (it steers a CHASE unit with no target at its goal, for good): the squad chases the
## enemy from tick 4, the enemy is removed at the end of tick 6, and at tick 7 the squad is
## `DIRECT` with the line unchecked, steering at its goal.
func test_a_chasing_unit_whose_target_is_gone_resumes_its_path(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(Rig.data_world(), impl)
	world.add_unit(1, RIFLE, 6000, 6000)
	world.add_unit(2, RIFLE, 10800, 6000)
	Sim.step(world, [_order(Command.attack_move(1, PackedInt32Array([1]), 14000, 6000), world)])
	while world.tick < 6:
		Sim.step(world, [])
	assert_array([world.nav_mode[0], world.target[0]]).is_equal([CHASE, 2])
	world.hp[1] = 0
	Sim.step(world, [])
	assert_int(world.unit_count()).is_equal(1)
	assert_int(world.nav_mode[0]).is_equal(CHASE)
	Sim.step(world, [])
	assert_int(world.tick).is_equal(8)
	assert_array([world.nav_mode[0], world.nav_cell[0], world.order[0]]).is_equal(
		[DIRECT, -1, ATTACK_MOVE]
	)
	assert_int(world.intent_x[0]).is_equal(67)


## An idle unit that loses its target while it holds goes back to `NONE`, not `DIRECT` (it has no
## order to steer by), and stays where it is.
func test_an_idle_unit_whose_target_is_gone_goes_back_to_none(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(Rig.data_world(), impl)
	world.add_unit(1, RIFLE, 6000, 6000)
	world.add_unit(2, RIFLE, 9000, 6000)
	for _tick: int in 10:
		Sim.step(world, [])
	assert_int(world.nav_mode[0]).is_equal(HOLD)
	world.hp[1] = 0
	Sim.step(world, [])
	Sim.step(world, [])
	assert_array([world.nav_mode[0], world.order[0], world.pos_x[0]]).is_equal([NONE, IDLE, 6000])


## An idle unit holds with an enemy in weapon range and never moves on its own: rifle squad 1 holds
## at 3000, and when the enemy is moved to 4300 (out of its range of 4000, and inside the 5000 an
## attack-moving unit would chase) it goes back to `NONE` the next tick, does not chase, and drops
## the target at its next scan. It never moves.
func test_an_idle_unit_holds_in_range_and_goes_back_to_none_when_the_target_leaves(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(Rig.data_world(), impl)
	world.add_unit(1, RIFLE, 6000, 6000)
	world.add_unit(2, RIFLE, 9000, 6000)
	for _tick: int in 10:
		Sim.step(world, [])
	assert_array([world.target[0], world.nav_mode[0], world.order[0]]).is_equal([2, HOLD, IDLE])
	world.pos_x[1] = 6000 + 4300
	Sim.step(world, [])
	assert_array([world.nav_mode[0], world.order[0]]).is_equal([NONE, IDLE])
	for _tick: int in 10:
		Sim.step(world, [])
		assert_int(world.nav_mode[0]).is_not_equal(CHASE)
	assert_int(world.target[0]).is_equal(0)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([6000, 6000])


## The weapon range is inclusive at both ends: a gun with range 4000 and minimum range 1000 holds
## its target at exactly 4000 and at exactly 1000, and does not at 4001 or at 999 (a unit does not
## back away from a target inside its minimum range, it only does not hold). The target is held by
## hand and the tick is not the unit's turn, so the mode is the range's alone.
func test_the_weapon_range_is_inclusive_at_both_ends(
	impl: int, _test_parameters := _both()
) -> void:
	var gun: UnitDef = Rig.unit(&"gun", 8000, 5000, 4000, 1000, [100, 100, 100, 100])
	for case: Array in [[4000, true], [4001, false], [1000, true], [999, false]]:
		var world: World = _in(Rig.world_of([gun]), impl)
		world.add_unit(1, 0, 6000, 6000)
		world.add_unit(2, 0, 6000 + int(case[0]), 6000)
		world.order[0] = ATTACK_MOVE
		world.goal_x[0] = 14000
		world.target[0] = 2
		Sim.step(world, [])
		var label: String = "enemy %d away" % case[0]
		assert_bool(world.nav_mode[0] == HOLD).override_failure_message(label).is_equal(case[1])
		assert_int(world.target[0]).override_failure_message(label).is_equal(2)


## A `MOVE` order never holds or chases: the squad walks past an enemy that stands 1000 from its
## path (in range for a unit that could fire) without target or mode, `DIRECT` all the way, and
## one that was holding is `DIRECT` again after a new order.
func test_a_move_order_never_holds_or_chases(impl: int, _test_parameters := _both()) -> void:
	var world: World = _in(Rig.data_world(), impl)
	world.add_unit(1, RIFLE, 3000, 6000)
	world.add_unit(2, RIFLE, 8000, 7000)
	Sim.step(world, [_order(Command.move(1, PackedInt32Array([1]), 14000, 6000), world)])
	for _tick: int in 80:
		assert_array([world.target[0], world.nav_mode[0]]).is_equal([0, DIRECT])
		Sim.step(world, [])
	assert_int(world.pos_x[0]).is_greater(8000)
	var held: World = _holding_pair(impl)
	assert_int(held.nav_mode[0]).is_equal(HOLD)
	Sim.step(held, [_order(Command.move(1, PackedInt32Array([1]), 14000, 6000), held)])
	assert_array([held.target[0], held.nav_mode[0], held.order[0]]).is_equal([0, DIRECT, MOVE])


## The order target is the `ATTACK` order's: `MOVE` and `ATTACK_MOVE` leave a stale one alone (it is
## harmless, only `ATTACK` reads it, ids are never reused) through the ticks of the order, and
## `STOP` clears it, with the target.
func test_move_and_attack_move_keep_a_stale_order_target_and_stop_clears_it(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(Rig.data_world(), impl)
	for _unit: int in 3:
		world.add_unit(1, RIFLE, 3000, 6000)
	world.add_unit(2, RIFLE, 17000, 9000)
	world.order_target[0] = 4
	world.order_target[1] = 4
	world.order_target[2] = 4
	var commands: Array[Command] = [
		_order(Command.move(1, PackedInt32Array([1]), 9000, 6000), world),
		_order(Command.attack_move(1, PackedInt32Array([2]), 9000, 4000), world),
	]
	Sim.step(world, commands)
	for _tick: int in 20:
		Sim.step(world, [])
	assert_array(world.order_target.slice(0, 3)).is_equal([4, 4, 4])
	assert_array(world.order.slice(0, 3)).is_equal([MOVE, ATTACK_MOVE, IDLE])
	Sim.step(world, [_order(Command.stop(1, PackedInt32Array([1, 2, 3])), world)])
	assert_array(world.order_target.slice(0, 3)).is_equal([0, 0, 0])
	assert_array(world.order.slice(0, 3)).is_equal([IDLE, IDLE, IDLE])


## A type whose weapon index the weapon tables lack is unarmed for engagement, as for acquisition,
## and an `ATTACK` command still takes it (`Sim._own_rows` asks for an index of 0 or more): the row
## locks its target and drives at it, never holding (a tank 1000 from its target would hold if the
## weapon were real), with no script error.
func test_an_attack_row_of_a_type_with_no_weapon_table_locks_but_never_holds(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(Rig.data_world(), impl)
	world.type_weapon[TANK] = world.weapon_range.size() + 2
	world.add_unit(1, TANK, 5000, 6000)
	world.add_unit(2, RIFLE, 6000, 6000)
	Sim.step(world, [_order(Command.attack(1, PackedInt32Array([1]), 2), world)])
	assert_int(world.dropped_commands).is_equal(0)
	for _tick: int in 12:
		Sim.step(world, [])
		assert_array([world.order[0], world.target[0]]).is_equal([ATTACK, 2])
		assert_int(world.nav_mode[0]).is_not_equal(HOLD)
		assert_int(world.nav_mode[0]).is_not_equal(CHASE)
	assert_int(world.pos_x[0]).is_greater(5900)


## Two runs of one fight give the same state hash at every checkpoint, and not the hashes of a run
## where nobody is ever due to scan: holding and chasing are part of the state.
func test_two_runs_give_the_same_hashes(impl: int, _test_parameters := _both()) -> void:
	var first: PackedInt64Array = _fight_hashes(0, impl)
	var second: PackedInt64Array = _fight_hashes(0, impl)
	assert_int(first.size()).is_equal(6)
	assert_array(second).is_equal(first)
	# The implementations agree: the native run's hashes are the GDScript run's.
	assert_array(_fight_hashes(0, SimImpls.Impl.GDSCRIPT)).is_equal(first)
	var silent: PackedInt64Array = _fight_hashes(1000000, impl)
	assert_int(silent[-1]).is_not_equal(first[-1])


## The state hash after each 15th tick of a 90 tick fight of two squads (one attack-moving, one
## idle) and a tank attacking a third unit; with `period` of 1 or more, `retarget_period_ticks`
## is set to it first.
func _fight_hashes(period: int, impl: int) -> PackedInt64Array:
	var world: World = _in(Rig.data_world(), impl)
	if period > 0:
		world.retarget_period_ticks = period
	world.add_unit(1, RIFLE, 6000, 6000)
	world.add_unit(2, RIFLE, 10800, 6000)
	world.add_unit(1, TANK, 3000, 9000)
	world.add_unit(2, TANK, 9000, 10000)
	var orders: Array[Command] = [
		_order(Command.attack_move(1, PackedInt32Array([1]), 14000, 6000), world),
		_order(Command.attack(1, PackedInt32Array([3]), 4), world),
	]
	var hashes: PackedInt64Array = PackedInt64Array()
	for _tick: int in 90:
		Sim.step(world, orders)
		orders.clear()
		if world.tick % Replay.CHECKPOINT_PERIOD == 0:
			hashes.append(world.state_hash())
	return hashes


## Rifle squad 1 (player 1, attack-moving east to (14000, 6000)) holding against idle rifle squad 2
## 3000 east of it, after enough ticks to hold; the tick is 12.
func _holding_pair(impl: int) -> World:
	var world: World = _in(Rig.data_world(), impl)
	world.add_unit(1, RIFLE, 6000, 6000)
	world.add_unit(2, RIFLE, 9000, 6000)
	Sim.step(world, [_order(Command.attack_move(1, PackedInt32Array([1]), 14000, 6000), world)])
	for _tick: int in 11:
		Sim.step(world, [])
	return world


## `command` for the World's current tick.
func _order(command: Command, world: World) -> Command:
	command.tick = world.tick
	return command


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## `world` running `impl`: the kernels attached and the TARGETING phase really in the implementation
## asked for (the problems of SimImpls.attach, none).
func _in(world: World, impl: int) -> World:
	assert_array(SimImpls.attach(world, impl, TARGETING)).is_empty()
	return world
