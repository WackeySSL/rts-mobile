extends GdUnitTestSuite
## The edges of engagement (P41b, fix round 1; ADR 0009 section 3, ADR 0007 section 2): the rules
## that the cadence of the shipped data hides from test_engagement.gd, and the cost counter. The
## shipped `retarget_period_ticks` and `line_check_period_ticks` are both 5, so a unit scans and
## checks its lines on the same ticks, and acquisition has always dropped a target that is out of
## reach on the tick engagement meets it. A case that needs the two apart sets the scan period to a
## value no tick reaches (the unit keeps the target the test gave it by hand). Worlds: the shipped
## unit types (TargetingRig.data_world): rifle squad 0 (range 4000, acquire 5000, sight 6000, speed
## 67), light tank 2 (range 4500, sight 7000, speed 120) on an open 20 x 12 tile map, as in
## test_engagement.gd. A unit's turn is the tick where `(tick + id) % 5 == 0`.

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const RIFLE: int = 0
const TANK: int = 2
const IDLE: int = World.Order.IDLE
const ATTACK_MOVE: int = World.Order.ATTACK_MOVE
const NONE: int = World.NavMode.NONE
const DIRECT: int = World.NavMode.DIRECT
const HOLD: int = World.NavMode.HOLD
const CHASE: int = World.NavMode.CHASE
## A `retarget_period_ticks` that no tick of a test reaches: nobody scans.
const NEVER_DUE: int = 1000000


## The engagement's line checks are counted in `stats[LINE_CHECKS]` with the movement's, one for
## each `FixedMath.line_clear` call: the squad's first scan is tick 4, its turn, and it chases after
## one check; ticks 5 to 8 are not its turn; tick 9 is its turn and it is still out of weapon range
## (4532 away, the range is 4000), so one more. Movement checks nothing meanwhile (the unit is in
## `CHASE`).
func test_an_attack_moving_chaser_counts_its_line_checks_on_its_turns() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, RIFLE, 6000, 6000)
	world.add_unit(2, RIFLE, 10800, 6000)
	var counted: PackedInt32Array = PackedInt32Array()
	Sim.step(world, [_order(Command.attack_move(1, PackedInt32Array([1]), 14000, 6000), world)])
	counted.append(world.stats[World.Stat.LINE_CHECKS])
	for _tick: int in 9:
		Sim.step(world, [])
		counted.append(world.stats[World.Stat.LINE_CHECKS])
	assert_array(counted).is_equal([0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
	assert_int(world.nav_mode[0]).is_equal(CHASE)


## An `ATTACK` unit on a clear line tests it again on its turns, because its goal walks: tank 1
## drives at idle tank 2 (6500 away, inside its sight). Its first check is Movement's, at tick 4
## (the order's line is unchecked, `nav_cell` -1); from then on the line is marked clear, and the
## check of tick 9 is the engagement's. One count each, none on the ticks between.
func test_an_attack_unit_on_a_clear_line_tests_it_again_on_its_turns() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, TANK, 2000, 6000)
	world.add_unit(2, TANK, 8500, 6000)
	var counted: PackedInt32Array = PackedInt32Array()
	Sim.step(world, [_order(Command.attack(1, PackedInt32Array([1]), 2), world)])
	counted.append(world.stats[World.Stat.LINE_CHECKS])
	for _tick: int in 9:
		Sim.step(world, [])
		counted.append(world.stats[World.Stat.LINE_CHECKS])
	assert_array(counted).is_equal([0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
	assert_array([world.nav_mode[0], world.nav_cell[0] >= 0]).is_equal([DIRECT, true])


## An idle unit never chases, however its target and its turn fall: rifle squad 1 holds enemy 2 from
## a scan it will not repeat, 4300 away (out of its range of 4000, inside the 5000 an attack-moving
## squad chases within, and the line is clear), and stays `NONE` where it stands through two of its
## turns (ticks 4 and 9). With the shipped periods the scan on the same tick drops such a target
## first, so only a scan period apart from the line-check period reaches this rule.
func test_an_idle_unit_never_chases_a_target_it_holds_out_of_range() -> void:
	var world: World = Rig.data_world()
	world.retarget_period_ticks = NEVER_DUE
	world.add_unit(1, RIFLE, 6000, 6000)
	world.add_unit(2, RIFLE, 10300, 6000)
	world.target[0] = 2
	for _tick: int in 12:
		Sim.step(world, [])
		assert_int(world.nav_mode[0]).override_failure_message("tick %d" % world.tick).is_not_equal(
			CHASE
		)
	assert_array([world.nav_mode[0], world.order[0], world.target[0]]).is_equal([NONE, IDLE, 2])
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([6000, 6000])


## An attack-moving unit chases only inside its reach (ADR 0009 section 3: out of weapon range but
## inside reach, the acquire range of 5000 for a rifle squad): the squad holds enemy 2 by hand from
## a scan it will not repeat, and walks north to its goal (67 a tick, so 4807 or 5207 away at its
## turns of ticks 4 and 9, from 4800 or 5200). At 4800 it chases at tick 4; at 5200 it never does,
## and stays on the path of its order.
func test_an_attack_moving_unit_chases_only_a_target_inside_its_acquire_range() -> void:
	for gap: int in [4800, 5200]:
		var world: World = Rig.data_world()
		world.retarget_period_ticks = NEVER_DUE
		world.add_unit(1, RIFLE, 6000, 6000)
		world.add_unit(2, RIFLE, 6000 + gap, 6000)
		world.order[0] = ATTACK_MOVE
		world.goal_x[0] = 6000
		world.goal_y[0] = 600
		world.target[0] = 2
		var chased_at: int = -1
		for _tick: int in 10:
			Sim.step(world, [])
			if chased_at < 0 and world.nav_mode[0] == CHASE:
				chased_at = world.tick - 1
		var label: String = "enemy %d away" % gap
		assert_int(chased_at).override_failure_message(label).is_equal(4 if gap == 4800 else -1)
		if gap == 5200:
			assert_int(world.nav_mode[0]).override_failure_message(label).is_equal(DIRECT)
			assert_int(world.intent_y[0]).override_failure_message(label).is_equal(-67)


## A new ground tap does not move a unit that holds an enemy in weapon range: the attack-move
## order keeps the unit's target (the order's tick resets the navigation, `DIRECT`), the scan keeps
## the target it holds, and the same tick's engagement puts the unit back in `HOLD` before
## Movement steers it, so it never takes a step, whichever way the tap points. This is what the
## attack-move row of docs/HOW_TO_PLAY.md says.
func test_a_new_ground_tap_does_not_move_a_unit_that_holds_an_enemy_in_range() -> void:
	for goal: Vector2i in [Vector2i(14000, 6000), Vector2i(2000, 6000), Vector2i(6000, 600)]:
		var world: World = Rig.data_world()
		world.add_unit(1, RIFLE, 6000, 6000)
		world.add_unit(2, RIFLE, 9000, 6000)
		for _tick: int in 10:
			Sim.step(world, [])
		assert_array([world.nav_mode[0], world.target[0]]).is_equal([HOLD, 2])
		var taps: Array[Command] = [
			_order(Command.attack_move(1, PackedInt32Array([1]), goal.x, goal.y), world)
		]
		for tick: int in 12:
			Sim.step(world, taps)
			taps.clear()
			var label: String = "goal %s tick %d" % [goal, tick]
			assert_array([world.pos_x[0], world.pos_y[0]]).override_failure_message(label).is_equal(
				[6000, 6000]
			)
			assert_int(world.nav_mode[0]).override_failure_message(label).is_equal(HOLD)
		assert_array([world.order[0], world.goal_x[0], world.goal_y[0]]).is_equal(
			[ATTACK_MOVE, goal.x, goal.y]
		)


## A target that was removed is not read as the next unit up: rifle squad 1 holds enemy 2 (3000
## away), enemy 3 stands 3162 away, in range too, and 2 is removed. Rows stay in ascending id order,
## so the lookup of id 2 now lands on id 3's row, which is not id 2. Squad 1 resumes its path
## (`DIRECT`, still holding the id it will replace) on the tick after the removal, which is not its
## turn, instead of holding against the wrong unit until its next scan; at its turn, tick 14, it
## picks the unit that is there and holds against it. Every other gone-target case removes the
## last id, where the lookup runs off the end of the ids.
func test_a_removed_target_is_not_read_as_the_next_higher_id() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, RIFLE, 6000, 6000)
	world.add_unit(2, RIFLE, 9000, 6000)
	world.add_unit(2, RIFLE, 9000, 7000)
	Sim.step(world, [_order(Command.attack_move(1, PackedInt32Array([1]), 14000, 6000), world)])
	while world.tick < 11:
		Sim.step(world, [])
	assert_array([world.nav_mode[0], world.target[0]]).is_equal([HOLD, 2])
	world.hp[1] = 0
	Sim.step(world, [])
	assert_int(world.unit_count()).is_equal(2)
	assert_array([world.nav_mode[0], world.target[0]]).is_equal([HOLD, 2])
	Sim.step(world, [])
	assert_int(world.tick).is_equal(13)
	assert_int((world.tick - 1 + world.unit_id[0]) % 5).is_not_equal(0)
	assert_array([world.nav_mode[0], world.target[0], world.nav_cell[0]]).is_equal([DIRECT, 2, -1])
	while world.tick < 15:
		Sim.step(world, [])
	assert_array([world.nav_mode[0], world.target[0]]).is_equal([HOLD, 3])


## A period of 0 in either cadence rule (a bare World, or a rules file set to 0) is read as 1, as
## `Movement.run` reads it: no modulo by zero in `Targeting.run` (the scan) or in the engagement
## (the line-check turn). With the scan period at 0 every unit is due on every tick; with the
## line-check period at 0 an attack-moving squad is on its turn on every tick. The squad chases the
## enemy 4800 away and then holds, as it does with a period of 5.
func test_a_cadence_of_zero_is_read_as_one() -> void:
	for scan: int in [0, 5]:
		for check: int in [0, 5]:
			var world: World = Rig.data_world()
			world.retarget_period_ticks = scan
			world.line_check_period_ticks = check
			world.add_unit(1, RIFLE, 6000, 6000)
			world.add_unit(2, RIFLE, 10800, 6000)
			Sim.step(
				world, [_order(Command.attack_move(1, PackedInt32Array([1]), 14000, 6000), world)]
			)
			var chased: bool = false
			for _tick: int in 40:
				Sim.step(world, [])
				chased = chased or world.nav_mode[0] == CHASE
			var label: String = "scan period %d, line-check period %d" % [scan, check]
			var ended: Array = [world.nav_mode[0], world.target[0]]
			assert_bool(chased).override_failure_message(label).is_true()
			assert_array(ended).override_failure_message(label).is_equal([HOLD, 2])


## The reach of a chase is inclusive, as acquisition's is (a held target is kept at exactly the
## reach): a squad that holds enemy 2 by hand and attack-moves north chases it at exactly 5000
## away, its acquire range, on its turn (tick 4), and does not at 5001.
func test_an_attack_moving_unit_chases_a_target_at_exactly_its_acquire_range() -> void:
	for gap: int in [5000, 5001]:
		var world: World = Rig.data_world()
		world.retarget_period_ticks = NEVER_DUE
		world.add_unit(1, RIFLE, 6000, 6000)
		world.add_unit(2, RIFLE, 6000 + gap, 6000)
		world.order[0] = ATTACK_MOVE
		world.goal_x[0] = 6000
		world.goal_y[0] = 600
		world.target[0] = 2
		world.tick = 4
		Sim.step(world, [])
		assert_int(world.nav_mode[0]).override_failure_message("enemy %d away" % gap).is_equal(
			CHASE if gap == 5000 else DIRECT
		)


## `command` for the World's current tick.
func _order(command: Command, world: World) -> Command:
	command.tick = world.tick
	return command
