extends GdUnitTestSuite
## Weapons, part 2 (P42b; ADR 0009 section 4, ADR 0007 sections 3, 4 and 10): the projectile slots
## and `Combat.advance_projectiles` in the PROJECTILES phase of `Sim.step`, between INTEGRATE and
## FIRE. A weapon with a projectile speed takes the top slot of the free stack when it fires and
## hits a flight time later, `max(1, ceil(dist / speed))` ticks; the shell homes on its target; one
## whose target is gone comes down at the last aim point with an `IMPACT` of target 0; a full pool
## turns a shot into a hitscan and counts `projectile_overflow`; slots go back on the stack. The
## phase pair is also driven by hand (`_fly`: `Combat.fire`, then `advance_projectiles` and `fire`
## per pass) where a case needs no other phase. The hitscan side (cooldown, damage, the SHOT
## record) is test_combat.gd, the fights between groups are test_combat_fights.gd and the duels of
## the counter triangle are test_counter_triangle.gd.
##
## The worlds are test-built types on the open 20 x 12 tile map: a shooter (type 0, infantry,
## 100000 hp) with the shell weapon the case builds and an unarmed mark (type 1) of the armour class
## and hp the case names, owners 1 and 2, sight 9000 (every target stands inside the shooter's
## sight: the authoring rule of the fog PR, P46b) and a weapon range of 8000. The shooter's cooldown
## is 100, so one shot is fired in the first tick and none in the ticks that follow. A case that
## needs a smaller pool builds the World with its own `max_projectiles`.

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const RecordingProbe: GDScript = preload("res://tests/sim/recording_probe.gd")
const RULES_PATH: String = "res://data/rules.tres"
const INFANTRY: int = World.Armour.INFANTRY
const LIGHT: int = World.Armour.LIGHT
const HEAVY: int = World.Armour.HEAVY
const BUILDING: int = World.Armour.BUILDING
const SHOT: int = World.Event.SHOT
const IMPACT: int = World.Event.IMPACT
const DIED: int = World.Event.DIED
const STRIDE: int = World.EVENT_STRIDE
const PROJ_STEPS: int = World.Stat.PROJ_STEPS
## The hp of a unit that no case means to kill.
const TOUGH: int = 100000
## The weapon range of the test types: every case stands inside it.
const REACH: int = 8000
## The shooter's cooldown: longer than any flight of these cases.
const SLOW: int = 100
## Where the shooter stands unless a case says otherwise.
const SHOOTER_AT: Vector2i = Vector2i(8000, 6000)
## A mark this far off the shooter's row in y: the SHOT and IMPACT records' two y fields differ.
const SIDE: int = 500
## 30 damage against (70, 60, 35, 40) percent: 18 against a light target, as in test_combat.gd.
const GUN_VS: Array[int] = [70, 60, 35, 40]
## The pool of the shipped rules (`max_projectiles`).
const POOL: int = 512


## A shell takes the top slot of the free stack in the tick it is fired, where the shooter stands,
## aimed at where the target stands, and does no damage yet: the shooter fires in tick 0 at a mark
## 3000 west and 500 north of it (3041.4 away: 6 ticks at 600 a tick). The SHOT record is the
## hitscan one; the cooldown is set; the slot holds the next projectile id (1), the shooter's owner
## and its weapon, the target's id, both points and the flight time; the stack is one shorter. The
## shell flies for 5 more ticks with the target's hp untouched (`stats[PROJ_STEPS]` 1 in each) and
## lands in the 6th with its IMPACT record and the damage of the weapon (18); the slot comes back,
## zeroed. With the owners swapped the slot holds owner 2.
func test_a_shell_takes_the_top_slot_and_hits_a_flight_time_later() -> void:
	for swapped: bool in [false, true]:
		var world: World = _duel(_shell(600), LIGHT, Vector2i(-3000, -SIDE))
		var owner_of_shooter: int = 2 if swapped else 1
		world.owner[0] = owner_of_shooter
		world.owner[1] = 3 - owner_of_shooter
		world.target[0] = 2
		var label: String = "owners swapped" if swapped else "owners 1 and 2"
		assert_int(world.proj_free_top).is_equal(POOL)
		Sim.step(world, [])
		assert_array(world.events).override_failure_message(label).is_equal(
			[SHOT, 1, 8000, 6000, 2, 0, 5000, 6000 - SIDE]
		)
		assert_int(world.hp[1]).override_failure_message(label).is_equal(TOUGH)
		assert_int(world.cooldown[0]).is_equal(SLOW)
		assert_int(world.proj_free_top).is_equal(POOL - 1)
		assert_int(world.next_projectile_id).is_equal(2)
		assert_array(_slot(world, 0)).override_failure_message(label).is_equal(
			[1, owner_of_shooter, 0, 2, 8000, 6000, 5000, 6000 - SIDE, 6]
		)
		assert_int(world.stats[PROJ_STEPS]).is_equal(0)
		assert_int(world.projectile_overflow).is_equal(0)
		for tick: int in range(1, 6):
			Sim.step(world, [])
			assert_array(world.events).override_failure_message("tick %d" % tick).is_empty()
			assert_int(world.hp[1]).is_equal(TOUGH)
			assert_int(world.stats[PROJ_STEPS]).is_equal(1)
			assert_int(world.proj_ticks[0]).is_equal(6 - tick)
		Sim.step(world, [])
		assert_array(world.events).override_failure_message(label).is_equal(
			[IMPACT, 1, 5000, 6000 - SIDE, 2, 0, 0, 0]
		)
		assert_int(world.hp[1]).is_equal(TOUGH - 18)
		assert_array(_slot(world, 0)).is_equal([0, 0, 0, 0, 0, 0, 0, 0, 0])
		assert_int(world.proj_free_top).is_equal(POOL)
		assert_int(world.stats[PROJ_STEPS]).is_equal(1)
		assert_array(Rig.outside_sight(world)).is_empty()


## The flight time is exactly `max(1, ceil(dist / speed))` of the real distance, shooter to target
## at the moment of the shot, and the shell arrives in that many PROJECTILES passes. Along an axis
## 600 at 600 is 1, 601 is 2, 1200 is 2, 1201 is 3; a distance under one tick and a mark on the
## shooter's own point are 1 (the ceiling of 0 is raised to 1); a point 600 east and 1 south is
## 600.0008 away and takes 2, which an integer root rounded down would call 1; the same at 5000
## (4000 east, 3001 south) takes 11 at 500 a tick where 4000 and 3000 take 10; 3-4-5 triangles
## (2700, 3600 at 600 is 8; 3000, 4000 at 300 is 17) and an axis (4500 at 600 is 8; 5000 at 300 is
## 17, the longest flight of the shipped data).
func test_the_flight_time_is_the_ceiling_of_the_distance_over_the_speed_and_at_least_1() -> void:
	var cases: Array[Array] = [
		[600, 0, 600, 1],
		[601, 0, 600, 2],
		[1200, 0, 600, 2],
		[1201, 0, 600, 3],
		[100, 0, 600, 1],
		[0, 0, 600, 1],
		[600, 1, 600, 2],
		[4000, 3000, 500, 10],
		[4000, 3001, 500, 11],
		[2700, 3600, 600, 8],
		[3000, 4000, 300, 17],
		[4500, 0, 600, 8],
		[5000, 0, 300, 17],
		[-1201, 0, 600, 3],
		[0, -4000, 1000, 4],
		[0, -4001, 1000, 5],
	]
	for case: Array in cases:
		var label: String = "offset (%d, %d) at %d" % [case[0], case[1], case[2]]
		var world: World = _duel(_shell(case[2]), LIGHT, Vector2i(case[0], case[1]))
		world.target[0] = 2
		var flight: Array[int] = _fly(world)
		assert_int(flight[0]).override_failure_message(label).is_equal(case[3])
		assert_int(flight[1]).override_failure_message(label).is_equal(case[3])
		assert_int(world.hp[1]).override_failure_message(label).is_equal(TOUGH - 18)


## The shell steps `(aim - pos) / proj_ticks` on each axis, the division truncating toward zero,
## and lands on the aim point exactly. From (8000, 6000) to (4997, 7001), 3003 west and 1001 south
## (6 ticks at 600), the x steps are -500, -499, -499, -499, -500, -500 (a floor would make the
## first -501), so the points are (7500, 6166), (7000, 6333), (6500, 6500), (5999, 6667),
## (5498, 6834) and (4997, 7001); from (4000, 7001) to (7003, 6000) the mirror image (x up, y down).
func test_the_shell_steps_a_share_of_the_rest_truncating_toward_zero_and_lands_on_the_aim() -> void:
	var cases: Array[Array] = [
		[
			Vector2i(8000, 6000),
			Vector2i(4997, 7001),
			[
				Vector2i(7500, 6166),
				Vector2i(7000, 6333),
				Vector2i(6500, 6500),
				Vector2i(5999, 6667),
				Vector2i(5498, 6834),
				Vector2i(4997, 7001)
			]
		],
		[
			Vector2i(4000, 7001),
			Vector2i(7003, 6000),
			[
				Vector2i(4500, 6835),
				Vector2i(5000, 6668),
				Vector2i(5500, 6501),
				Vector2i(6001, 6334),
				Vector2i(6502, 6167),
				Vector2i(7003, 6000)
			]
		],
	]
	for case: Array in cases:
		var world: World = _duel_at(_shell(600), LIGHT, case[0], case[1])
		world.target[0] = 2
		Combat.fire(world)
		var points: Array[Vector2i] = []
		var landed: Array[Vector2i] = []
		for _pass: int in 6:
			world.events.clear()
			Combat.advance_projectiles(world)
			if _records(world, IMPACT).is_empty():
				points.append(Vector2i(world.proj_x[0], world.proj_y[0]))
			else:
				var record: Array = _records(world, IMPACT)[0]
				landed.append(Vector2i(record[2], record[3]))
		assert_array(points + landed).is_equal(case[2])
		assert_array(landed).is_equal([case[1]])


## A shell homes: while its target has a row, the aim is the target's position as it stands in the
## PROJECTILES phase, after INTEGRATE moved it. The mark walks east at 120 a tick (it takes its
## first step in the tick of the shot, 12800 to 12920, 4920 from the shooter: 17 ticks at 300);
## after every tick the shell flies, `proj_aim_x` is the mark's x, the shell is further east than
## the tick before, and in the 17th tick it lands where the mark then stands (12800 + 18 * 120 =
## 14960), 2040 east of the point it was aimed at, and hits: 18 hp.
func test_a_shell_follows_a_target_that_walks_away() -> void:
	var world: World = _duel(_shell(300), LIGHT, Vector2i(4800, 0))
	world.target[0] = 2
	var walk: Command = _order(Command.move(2, PackedInt32Array([2]), 19000, 6000), world)
	var commands: Array[Command] = [walk]
	Sim.step(world, commands)
	commands.clear()
	assert_array(world.events).is_equal([SHOT, 1, 8000, 6000, 2, 0, 12920, 6000])
	assert_array(_slot(world, 0)).is_equal([1, 1, 0, 2, 8000, 6000, 12920, 6000, 17])
	var shell_x: int = world.proj_x[0]
	var landed: int = -1
	for tick: int in range(1, 40):
		Sim.step(world, commands)
		var label: String = "tick %d" % tick
		if not _records(world, IMPACT).is_empty():
			landed = tick
			assert_array(world.events).override_failure_message(label).is_equal(
				[IMPACT, 1, 14960, 6000, 2, 0, 0, 0]
			)
			break
		assert_int(world.proj_aim_x[0]).override_failure_message(label).is_equal(world.pos_x[1])
		assert_int(world.proj_aim_y[0]).override_failure_message(label).is_equal(world.pos_y[1])
		assert_int(world.proj_x[0]).override_failure_message(label).is_greater(shell_x)
		shell_x = world.proj_x[0]
	assert_int(landed).is_equal(17)
	assert_int(world.pos_x[1]).is_equal(14960)
	assert_int(world.hp[1]).is_equal(TOUGH - 18)


## A shell homes on the y axis as well: the mark walks south, across the line from the shooter, at
## 120 a tick (it takes its first step in the tick of the shot, 6000 to 6120, 3002.4 from the
## shooter, which stands 3000 west of its column: 11 ticks at 300). After every tick the shell
## flies, `proj_aim_x` and `proj_aim_y` are the mark's position, the aim is 120 further south than
## the tick before, and the shell is further east and further south than the tick before. In the
## 11th tick it lands where the mark then stands (6000 + 12 * 120 = 7440), 1320 south of the point
## it was aimed at, and hits: 18 hp.
func test_a_shell_follows_a_target_that_walks_across_its_line_of_fire() -> void:
	var world: World = _duel(_shell(300), LIGHT, Vector2i(3000, 0))
	world.target[0] = 2
	var walk: Command = _order(Command.move(2, PackedInt32Array([2]), 11000, 11000), world)
	var commands: Array[Command] = [walk]
	Sim.step(world, commands)
	commands.clear()
	assert_array(world.events).is_equal([SHOT, 1, 8000, 6000, 2, 0, 11000, 6120])
	assert_array(_slot(world, 0)).is_equal([1, 1, 0, 2, 8000, 6000, 11000, 6120, 11])
	var shell_x: int = world.proj_x[0]
	var shell_y: int = world.proj_y[0]
	var aim_y: int = world.proj_aim_y[0]
	var landed: int = -1
	for tick: int in range(1, 20):
		Sim.step(world, commands)
		var label: String = "tick %d" % tick
		if not _records(world, IMPACT).is_empty():
			landed = tick
			assert_array(world.events).override_failure_message(label).is_equal(
				[IMPACT, 1, 11000, 7440, 2, 0, 0, 0]
			)
			break
		(
			assert_array([world.proj_aim_x[0], world.proj_aim_y[0]])
			. override_failure_message(label)
			. is_equal([world.pos_x[1], world.pos_y[1]])
		)
		assert_int(world.proj_aim_y[0]).override_failure_message(label).is_equal(aim_y + 120)
		aim_y = world.proj_aim_y[0]
		assert_int(world.proj_x[0]).override_failure_message(label).is_greater(shell_x)
		assert_int(world.proj_y[0]).override_failure_message(label).is_greater(shell_y)
		shell_x = world.proj_x[0]
		shell_y = world.proj_y[0]
	assert_int(landed).is_equal(11)
	assert_array([world.pos_x[1], world.pos_y[1]]).is_equal([11000, 7440])
	assert_int(world.hp[1]).is_equal(TOUGH - 18)


## A target that dies mid-flight gives an IMPACT with target 0 at the aim point, and hits nothing.
## The shell is fired in tick 0 at a mark 4800 east (16 ticks at 300); a rifleman 3000 north of the
## mark, with a cooldown that makes it fire in tick 4, kills the mark (50 hp) and REMOVE takes the
## row away at the end of that tick. The shell flies on with its target id and the aim point where
## the mark last stood (it counts down 1 a tick), lands in tick 16 with `[IMPACT, 1, 8800, 6000, 0,
## 0, 0, 0]` (target 0), the bystander of the mark's side 3000 south of the aim point keeps every hp
## it had, and the slot comes back.
func test_a_target_that_dies_mid_flight_gives_an_impact_with_target_0_at_the_aim_point() -> void:
	var rifle: WeaponDef = _weapon(&"rifle", 100, 15, [100, 100, 100, 100], 0)
	var defs: Array[UnitDef] = [
		_def(&"gun", INFANTRY, TOUGH, _shell(300)),
		_def(&"mark", LIGHT, 50),
		_def(&"rifleman", INFANTRY, TOUGH, rifle),
	]
	var world: World = _world(defs)
	world.add_unit(1, 0, 4000, 6000)
	world.add_unit(2, 1, 8800, 6000)
	world.add_unit(1, 2, 8800, 3000)
	world.add_unit(2, 1, 8800, 9000)
	world.hp[3] = TOUGH
	world.target[0] = 2
	world.target[2] = 2
	world.cooldown[2] = 5
	var shell_x: int = 4000
	for tick: int in 17:
		Sim.step(world, [])
		var label: String = "tick %d" % tick
		if tick == 4:
			assert_array(world.events).override_failure_message(label).is_equal(
				[SHOT, 3, 8800, 3000, 2, 1, 8800, 6000, DIED, 2, 8800, 6000, 1, 2, 0, 0]
			)
			assert_array(world.unit_id).is_equal([1, 3, 4])
		if tick >= 1 and tick < 16:
			assert_array(_slot(world, 0).slice(0, 4)).override_failure_message(label).is_equal(
				[1, 1, 0, 2]
			)
			assert_array([world.proj_aim_x[0], world.proj_aim_y[0]]).is_equal([8800, 6000])
			assert_int(world.proj_ticks[0]).override_failure_message(label).is_equal(16 - tick)
			assert_int(world.proj_x[0]).override_failure_message(label).is_greater(shell_x)
			shell_x = world.proj_x[0]
	assert_array(world.events).is_equal([IMPACT, 1, 8800, 6000, 0, 0, 0, 0])
	assert_array(world.hp).is_equal([TOUGH, TOUGH, TOUGH])
	assert_array(_slot(world, 0)).is_equal([0, 0, 0, 0, 0, 0, 0, 0, 0])
	assert_int(world.proj_free_top).is_equal(POOL)


## A live slot with no flight time left lands in the pass that finds it, as the whole rest of the
## step and not as a division by 0: `Combat.fire` never writes a flight time under 1, but the
## columns allow 0 (a slot placed by hand, a snapshot or a port that counts down differently). The
## slot is taken off the stack by hand the way `fire` takes it, aimed at the mark 4800 east, which
## is 12800 where it stands; one pass of `advance_projectiles` gives the IMPACT at the mark's point
## with its id, the 18 hp of the weapon, a zeroed slot back on top of a full stack and one slot
## stepped in `stats[PROJ_STEPS]`.
func test_a_slot_with_no_flight_time_left_lands_in_the_pass_that_finds_it() -> void:
	var world: World = _duel(_shell(300), LIGHT, Vector2i(4800, 0))
	world.proj_free_top -= 1
	var slot: int = world.proj_free[world.proj_free_top]
	assert_int(slot).is_equal(0)
	world.proj_id[slot] = 1
	world.next_projectile_id = 2
	world.proj_owner[slot] = 1
	world.proj_weapon[slot] = 0
	world.proj_target[slot] = 2
	world.proj_x[slot] = 8000
	world.proj_y[slot] = 6000
	world.proj_aim_x[slot] = 9000
	world.proj_aim_y[slot] = 7000
	world.proj_ticks[slot] = 0
	world.events.clear()
	Combat.advance_projectiles(world)
	assert_array(world.events).is_equal([IMPACT, 1, 12800, 6000, 2, 0, 0, 0])
	assert_int(world.hp[1]).is_equal(TOUGH - 18)
	assert_array(_slot(world, slot)).is_equal([0, 0, 0, 0, 0, 0, 0, 0, 0])
	assert_int(world.proj_free_top).is_equal(POOL)
	assert_int(world.proj_free[POOL - 1]).is_equal(slot)
	assert_int(world.stats[PROJ_STEPS]).is_equal(1)


## A shell outlives its shooter and finds its target by id after the rows have moved: the shooter
## (row 0) is brought to 0 hp in tick 1 and removed, so the mark (id 2) moves from row 1 to row 0;
## the shell, fired at it in tick 0 (16 ticks), lands in tick 16 on the mark with the weapon's 18,
## the IMPACT naming target 2.
func test_a_shell_outlives_its_shooter_and_finds_its_target_by_id() -> void:
	var world: World = _duel(_shell(300), LIGHT, Vector2i(4800, 0))
	world.target[0] = 2
	Sim.step(world, [])
	world.hp[0] = 0
	Sim.step(world, [])
	assert_array(world.unit_id).is_equal([2])
	for _tick: int in 14:
		Sim.step(world, [])
		assert_array(world.events).is_empty()
	Sim.step(world, [])
	assert_array(world.events).is_equal([IMPACT, 1, 12800, 6000, 2, 0, 0, 0])
	assert_int(world.hp[0]).is_equal(TOUGH - 18)


## Every shell that arrives in a tick hits a target another shell has already brought to 0 or less
## in that tick (the rule of the shooters, test_combat.gd): two shooters 4123 away from one mark of
## 10 hp (7 ticks at 600) fire in tick 0; in tick 7 both land, the mark goes to -8 and then -26,
## the IMPACTs come in slot order (slot 0, then 1), both naming the mark, and REMOVE writes its DIED
## after them.
func test_every_shell_that_arrives_in_the_tick_hits_a_target_an_earlier_one_has_killed() -> void:
	var defs: Array[UnitDef] = [
		_def(&"gun", INFANTRY, TOUGH, _shell(600)), _def(&"mark", LIGHT, 10)
	]
	var world: World = _world(defs)
	world.add_unit(1, 0, 4000, 6000)
	world.add_unit(1, 0, 4000, 8000)
	world.add_unit(2, 1, 8000, 7000)
	world.target[0] = 3
	world.target[1] = 3
	for tick: int in 7:
		Sim.step(world, [])
		assert_int(world.hp[2]).override_failure_message("tick %d" % tick).is_equal(10)
	Sim.step(world, [])
	assert_array(world.events).is_equal(
		[
			IMPACT,
			1,
			8000,
			7000,
			3,
			0,
			0,
			0,
			IMPACT,
			2,
			8000,
			7000,
			3,
			0,
			0,
			0,
			DIED,
			3,
			8000,
			7000,
			1,
			2,
			0,
			0
		]
	)
	assert_int(world.unit_count()).is_equal(2)
	var direct: World = _world(defs)
	direct.add_unit(1, 0, 4000, 6000)
	direct.add_unit(1, 0, 4000, 8000)
	direct.add_unit(2, 1, 8000, 7000)
	direct.hp[2] = 10
	direct.proj_free_top -= 2
	direct.proj_id[0] = 1
	direct.proj_id[1] = 2
	for slot: int in 2:
		direct.proj_target[slot] = 3
		direct.proj_ticks[slot] = 1
		direct.proj_x[slot] = 7000
		direct.proj_y[slot] = 7000
		direct.proj_aim_x[slot] = 8000
		direct.proj_aim_y[slot] = 7000
	Combat.advance_projectiles(direct)
	assert_int(direct.hp[2]).is_equal(10 - 2 * 18)


## A full pool turns a shot into a hitscan and counts `projectile_overflow`: with 2 slots, three
## shooters fire in tick 0 at three marks 4000 east; the first two take slots 0 and 1 (ids 1 and 2:
## the stack is empty, the next id is 3) and the third hits at once (its mark loses 18 in tick 0,
## the other two nothing), with its SHOT written like the others and `projectile_overflow` 1, and
## no IMPACT for it: tick 0 has none and tick 7 has the two of the shells (a view that draws a hit
## from an IMPACT shows none for the overflowed shot). The two shells land in tick 7 (4000 at 600),
## the stack has 2 slots again, the counter stays 1, and a shot fired after that takes a slot again
## (id 3) without counting.
func test_a_full_pool_turns_a_shot_into_a_hitscan_and_counts_the_overflow() -> void:
	var defs: Array[UnitDef] = [
		_def(&"gun", INFANTRY, TOUGH, _shell(600)), _def(&"mark", LIGHT, TOUGH)
	]
	var world: World = _world(defs, 2)
	for k: int in 3:
		world.add_unit(1, 0, 4000, 2000 + 3000 * k)
	for k: int in 3:
		world.add_unit(2, 1, 8000, 2000 + 3000 * k)
		world.target[k] = 4 + k
	assert_int(world.proj_free_top).is_equal(2)
	Sim.step(world, [])
	assert_int(world.proj_free_top).is_equal(0)
	assert_int(world.next_projectile_id).is_equal(3)
	assert_int(world.projectile_overflow).is_equal(1)
	assert_array(world.proj_id).is_equal([1, 2])
	assert_array(world.hp.slice(3)).is_equal([TOUGH, TOUGH, TOUGH - 18])
	assert_array(world.cooldown.slice(0, 3)).is_equal([SLOW, SLOW, SLOW])
	var shooters: Array[int] = []
	for record: Array in _records(world, SHOT):
		shooters.append(record[1])
	assert_array(shooters).is_equal([1, 2, 3])
	assert_array(_records(world, IMPACT)).is_empty()
	for tick: int in range(1, 7):
		Sim.step(world, [])
		assert_array(world.hp.slice(3, 5)).override_failure_message("tick %d" % tick).is_equal(
			[TOUGH, TOUGH]
		)
	Sim.step(world, [])
	assert_array(world.hp.slice(3)).is_equal([TOUGH - 18, TOUGH - 18, TOUGH - 18])
	var landed: Array[int] = []
	for record: Array in _records(world, IMPACT):
		landed.append(record[1])
	assert_array(landed).is_equal([1, 2])
	assert_int(world.proj_free_top).is_equal(2)
	assert_int(world.projectile_overflow).is_equal(1)
	world.cooldown[2] = 1
	Sim.step(world, [])
	assert_int(world.projectile_overflow).is_equal(1)
	assert_int(world.next_projectile_id).is_equal(4)
	assert_int(world.proj_free_top).is_equal(1)
	assert_int(world.proj_id[1]).is_equal(3)


## Every shot that finds the pool full adds 1 to `projectile_overflow`, however many there are in
## the tick and in whatever tick (the lockstep of the C++ twin and the performance test's
## `projectile_overflow` of 0 read the counter). A pool of 1 and three shooters fire in tick 0 at
## three marks 4000 east: shooter 1 takes the slot (7 ticks at 600), the other two hit at once, so
## the counter is 2 after tick 0 (not 1): three SHOTs, no IMPACT, 18 off marks 5 and 6, and the
## overflowed shots take no projectile id. Nothing is added in the two ticks that follow. Shooters 2
## and 3 get a cooldown of 3, so both fire again in tick 3, with the shell still in the air and the
## pool still full: the counter is 4 (neither 3, one shot of the two, nor 2, tick 0 only), the marks
## have lost 36, and the shell's landing in tick 7 leaves the counter at 4.
func test_every_overflowed_shot_adds_one_to_the_counter_in_the_tick_it_is_fired() -> void:
	var defs: Array[UnitDef] = [
		_def(&"gun", INFANTRY, TOUGH, _shell(600)), _def(&"mark", LIGHT, TOUGH)
	]
	var world: World = _world(defs, 1)
	for k: int in 3:
		world.add_unit(1, 0, 4000, 2000 + 3000 * k)
	for k: int in 3:
		world.add_unit(2, 1, 8000, 2000 + 3000 * k)
		world.target[k] = 4 + k
	Sim.step(world, [])
	assert_int(world.projectile_overflow).is_equal(2)
	assert_array(world.proj_id).is_equal([1])
	assert_int(world.next_projectile_id).is_equal(2)
	assert_int(world.proj_free_top).is_equal(0)
	assert_array(world.hp.slice(3)).is_equal([TOUGH, TOUGH - 18, TOUGH - 18])
	assert_array(_records(world, SHOT)).has_size(3)
	assert_array(_records(world, IMPACT)).is_empty()
	world.cooldown[1] = 3
	world.cooldown[2] = 3
	for tick: int in range(1, 3):
		Sim.step(world, [])
		assert_int(world.projectile_overflow).override_failure_message("tick %d" % tick).is_equal(2)
		assert_array(world.events).override_failure_message("tick %d" % tick).is_empty()
	Sim.step(world, [])
	assert_int(world.projectile_overflow).is_equal(4)
	var shooters: Array[int] = []
	for record: Array in _records(world, SHOT):
		shooters.append(record[1])
	assert_array(shooters).is_equal([2, 3])
	assert_array(_records(world, IMPACT)).is_empty()
	assert_array(world.hp.slice(3)).is_equal([TOUGH, TOUGH - 36, TOUGH - 36])
	assert_int(world.next_projectile_id).is_equal(2)
	assert_int(world.proj_free_top).is_equal(0)
	for _tick: int in range(4, 7):
		Sim.step(world, [])
		assert_int(world.projectile_overflow).is_equal(4)
	Sim.step(world, [])
	assert_array(_records(world, IMPACT)).has_size(1)
	assert_int(world.hp[3]).is_equal(TOUGH - 18)
	assert_int(world.proj_free_top).is_equal(1)
	assert_int(world.projectile_overflow).is_equal(4)


## Slots are reused from the free stack, last in first out, through `proj_free_top`, and shells are
## processed in slot order, not in id order. Three shooters (ids 1 to 3) fire in tick 0 into slots
## 0, 1, 2 (shells 1, 2, 3; flights 1, 3 and 1 ticks at 1000 a tick); in tick 1 shells 1 and 3
## land (slot 0 then slot 2 go back: the top is slot 2) and two more shooters (ids 4 and 5, a
## cooldown of 2) fire into slot 2 (shell 4) and slot 0 (shell 5); in tick 2 the IMPACTs come in
## slot order, shell 5 (slot 0) before shell 4 (slot 2); in tick 3 shell 2 lands. At the end the
## stack holds all 512 slots once each, the last pushed on top. `stats[PROJ_STEPS]` is the live
## slots at the start of each tick: 0, 3, 3, 1.
func test_slots_go_back_on_the_stack_and_the_next_shots_take_them_last_in_first_out() -> void:
	var world: World = _slot_world()
	var seen: Array[Array] = []
	var steps: Array[int] = []
	var impacts: Array[Array] = []
	for _tick: int in 4:
		Sim.step(world, [])
		seen.append(Array(world.proj_id.slice(0, 3)))
		steps.append(world.stats[PROJ_STEPS])
		impacts.append(_records(world, IMPACT).map(func(record: Array) -> int: return record[1]))
		if seen.size() == 2:
			assert_int(world.proj_free_top).is_equal(POOL - 3 + 2 - 2)
	assert_array(seen).is_equal([[1, 2, 3], [5, 2, 4], [0, 2, 0], [0, 0, 0]])
	assert_array(steps).is_equal([0, 3, 3, 1])
	assert_array(impacts).is_equal([[], [1, 3], [5, 4], [2]])
	assert_int(world.proj_free_top).is_equal(POOL)
	assert_array(world.proj_free.slice(POOL - 3)).is_equal([0, 2, 1])
	var once: Array[int] = []
	for slot: int in POOL:
		once.append(slot)
	var stack: Array[int] = []
	stack.assign(world.proj_free)
	stack.sort()
	assert_array(stack).is_equal(once)
	assert_int(world.next_projectile_id).is_equal(6)


## A slot that lands on an EMPTY stack is written at the bottom of it, whatever stood there before
## (the lockstep of the C++ twin compares `proj_free` below the top, and a full pool is the path a
## small-pool run takes). A pool of 3 has the stack [2, 1, 0] (slot 0 on top); three shooters at
## x 4000 fire in tick 0 at marks 4800, 1200 and 3000 east of them (speed 600: flights of 8, 2 and 5
## ticks), take slots 0, 1 and 2, and leave the stack empty with the old bytes [2, 1, 0] in place.
## Slot 1 lands in tick 2 onto the empty stack: top 1 and `proj_free[0]` 1 (not the stale 2, so a
## write skipped on an empty stack shows, and the slot, so a zero written there shows). Slot 2 lands
## in tick 5: top 2 and [1, 2] below it. Slot 0 lands in tick 8: top 3 and [1, 2, 0]. A pool of 2
## would not tell the cases apart: the stale value under its bottom is the slot that lands.
func test_a_slot_pushed_onto_an_empty_stack_is_written_at_the_bottom_of_it() -> void:
	var defs: Array[UnitDef] = [
		_def(&"gun", INFANTRY, TOUGH, _shell(600)), _def(&"mark", LIGHT, TOUGH)
	]
	var world: World = _world(defs, 3)
	var gaps: Array[int] = [4800, 1200, 3000]
	for k: int in 3:
		world.add_unit(1, 0, 4000, 1000 + 3000 * k)
	for k: int in 3:
		world.add_unit(2, 1, 4000 + gaps[k], 1000 + 3000 * k)
		world.target[k] = 4 + k
	Sim.step(world, [])
	assert_array(world.proj_ticks).is_equal([8, 2, 5])
	assert_int(world.proj_free_top).is_equal(0)
	assert_array(world.proj_free).is_equal([2, 1, 0])
	for _tick: int in 2:
		Sim.step(world, [])
	assert_int(world.proj_free_top).is_equal(1)
	assert_int(world.proj_free[0]).is_equal(1)
	for _tick: int in 3:
		Sim.step(world, [])
	assert_int(world.proj_free_top).is_equal(2)
	assert_array(world.proj_free.slice(0, 2)).is_equal([1, 2])
	for _tick: int in 3:
		Sim.step(world, [])
	assert_int(world.proj_free_top).is_equal(3)
	assert_array(world.proj_free).is_equal([1, 2, 0])


## The phase sits between INTEGRATE and FIRE: a probe sees the marks INTEGRATE, PROJECTILES, FIRE,
## REMOVE in that order, and the hash after a tick with shells in flight differs from the hash of
## the same state with one live slot's flight time one tick longer (the live slots are in the
## hash), while a freed slot's columns are not (a slot zeroed by hand but already free hashes as
## before).
func test_the_phase_is_marked_between_integrate_and_fire_and_the_slots_are_in_the_hash() -> void:
	var world: World = _slot_world()
	var probe: RecordingProbe = RecordingProbe.new()
	Sim.step(world, [], probe)
	var calls: Array[int] = []
	calls.assign(probe.calls)
	assert_array(calls.slice(calls.find(SimProbe.Phase.INTEGRATE))).is_equal(
		[
			SimProbe.Phase.INTEGRATE,
			SimProbe.Phase.PROJECTILES,
			SimProbe.Phase.FIRE,
			SimProbe.Phase.REMOVE
		]
	)
	Sim.step(world, [])
	var before: int = world.state_hash()
	world.proj_ticks[1] += 1
	assert_int(world.state_hash()).is_not_equal(before)
	world.proj_ticks[1] -= 1
	assert_int(world.state_hash()).is_equal(before)
	world.proj_ticks[20] = 7
	assert_int(world.state_hash()).is_equal(before)


## The same fight twice gives the same state hash after every tick with shells in flight, and the
## ticks differ from one another: the 5-pair slot case above, 4 ticks.
func test_shells_in_flight_give_the_same_hash_twice() -> void:
	var runs: Array[PackedInt64Array] = []
	for _run: int in 2:
		var world: World = _slot_world()
		var hashes: PackedInt64Array = PackedInt64Array()
		for _tick: int in 4:
			Sim.step(world, [])
			hashes.append(world.state_hash())
		runs.append(hashes)
	assert_array(runs[1]).is_equal(runs[0])
	var distinct: Dictionary[int, bool] = {}
	for value: int in runs[0]:
		distinct[value] = true
	assert_int(distinct.size()).is_equal(4)


## The damage of a shell is the percent rule of a hit (test_combat.gd) for the four armour classes
## of the target, with the weapon the shell was fired from (slot weapon, not the first weapon of
## the tables): 30 against (70, 60, 35, 40) loses 21, 18, 10 and 12; 12 against (100, 10, 5, 0)
## loses 12, 1, 1 (0.6 raised to 1) and 0, and the percent of 0 still writes the IMPACT, naming the
## target. The weapon of the shot is index 1 (the second type) behind a decoy weapon of index 0, so
## the landing slot, which must come back as nine zeros, shows a weapon column it did not zero (a
## stale 1; the other cases' weapon is index 0, which a stale column cannot be told from zero).
func test_a_shell_does_the_percent_damage_of_its_own_weapon_for_each_armour_class() -> void:
	var lost: Array[Array] = [[21, 18, 10, 12], [12, 1, 1, 0]]
	var weapons: Array[WeaponDef] = [
		_shell(600, 30, SLOW, GUN_VS),
		_shell(450, 12, SLOW, [100, 10, 5, 0]),
	]
	for armour: int in [INFANTRY, LIGHT, HEAVY, BUILDING]:
		for k: int in 2:
			var decoy: WeaponDef = _weapon(&"decoy", 5, 3, [100, 100, 100, 100], 900)
			var defs: Array[UnitDef] = [_def(&"decoy", INFANTRY, TOUGH, decoy)]
			defs.append_array(
				[_def(&"gun", INFANTRY, TOUGH, weapons[k]), _def(&"mark", armour, TOUGH)]
			)
			var world: World = _world(defs)
			world.add_unit(1, 1, 5000, 6000)
			world.add_unit(2, 2, 8000, 6000)
			world.target[0] = 2
			var label: String = "weapon %d against armour %d" % [k, armour]
			var flight: Array[int] = _fly(world)
			assert_int(TOUGH - world.hp[1]).override_failure_message(label).is_equal(
				lost[k][armour]
			)
			assert_int(flight[1]).override_failure_message(label).is_greater(0)
			var impact: Array = _records(world, IMPACT)[0]
			assert_array(impact).override_failure_message(label).is_equal(
				[IMPACT, 1, 8000, 6000, 2, 1, 0, 0]
			)
			assert_array(_slot(world, 0)).override_failure_message(label).is_equal(
				[0, 0, 0, 0, 0, 0, 0, 0, 0]
			)


## The shipped weapons: the tank cannon (600 a tick) at its full range of 4500 flies 8 ticks, the
## rocket (300) at 5000 flies 17, the longest flight there is (`proj_ticks` is at most 17 with the
## shipped data: the comment of the World's column), and the rifle is a hitscan that takes no slot:
## its hit lands in the tick of the shot and the stack stays full. The first hits are the data's
## numbers: 21 hp from a cannon shell on a rifle squad (30 * 70 / 100) and 50 from a rocket on a
## tank (50 * 100 / 100).
func test_the_shipped_weapons_fly_8_and_17_ticks_at_full_range_and_the_rifle_takes_no_slot(
) -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, Rig.TANK, 4000, 6000)
	world.add_unit(2, Rig.RIFLE, 8500, 6000)
	world.target[0] = 2
	var cannon: Array[int] = _fly(world)
	assert_array(cannon).is_equal([8, 8])
	assert_int(world.hp[1]).is_equal(100 - 21)
	var rocket_world: World = Rig.data_world()
	rocket_world.add_unit(1, Rig.ROCKET, 3000, 6000)
	rocket_world.add_unit(2, Rig.TANK, 8000, 6000)
	rocket_world.target[0] = 2
	assert_array(_fly(rocket_world)).is_equal([17, 17])
	assert_int(rocket_world.hp[1]).is_equal(300 - 50)
	var longest: int = 0
	for weapon: int in rocket_world.weapon_range.size():
		var speed: int = rocket_world.weapon_projectile_speed[weapon]
		if speed > 0:
			longest = maxi(
				longest, maxi(1, (rocket_world.weapon_range[weapon] + speed - 1) / speed)
			)
	assert_int(longest).is_equal(17)
	var rifles: World = Rig.data_world()
	rifles.add_unit(1, Rig.RIFLE, 4000, 6000)
	rifles.add_unit(2, Rig.RIFLE, 7000, 6000)
	rifles.target[0] = 2
	Combat.fire(rifles)
	assert_int(rifles.proj_free_top).is_equal(POOL)
	assert_int(rifles.next_projectile_id).is_equal(1)
	assert_int(rifles.hp[1]).is_equal(100 - 12)
	assert_int(rifles.projectile_overflow).is_equal(0)


## A World with five shooters (ids 1 to 5, type 0, owner 1) and five marks (ids 6 to 10, type 1,
## owner 2, 100000 hp), each pair on a row of its own 1000 apart; the shell weapon flies 1000 a
## tick, so a pair 1000 apart is a flight of 1 tick and one 2500 apart of 3. Shooter k aims at mark
## 6 + k. Pairs 1 and 3 are 1000 apart, pair 2 is 2500 apart (shells fired in tick 0), pairs 4 and
## 5 are 1000 apart and fire in tick 1 (their cooldown is 2).
func _slot_world() -> World:
	var defs: Array[UnitDef] = [
		_def(&"gun", INFANTRY, TOUGH, _shell(1000)), _def(&"mark", LIGHT, TOUGH)
	]
	var world: World = _world(defs)
	var gaps: Array[int] = [1000, 2500, 1000, 1000, 1000]
	for k: int in 5:
		world.add_unit(1, 0, 4000, 1000 + 2000 * k)
	for k: int in 5:
		world.add_unit(2, 1, 4000 + gaps[k], 1000 + 2000 * k)
		world.target[k] = 6 + k
	world.cooldown[3] = 2
	world.cooldown[4] = 2
	return world


## A World with the shipped rules but `pool` projectile slots, on the open 20 x 12 tile map.
func _world(defs: Array[UnitDef], pool: int = POOL) -> World:
	var rules: RulesDef = (load(RULES_PATH) as RulesDef).duplicate() as RulesDef
	rules.max_projectiles = pool
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(20, 12)
	scenario.player_count = 2
	scenario.rules = rules
	scenario.roster.assign(defs)
	return World.from_scenario(scenario)


## The shooter (type 0, owner 1, id 1) at `shooter` and a mark (type 1, owner 2, id 2, of `armour`
## and `mark_hp`) at `mark`.
func _duel_at(
	weapon: WeaponDef,
	armour: int,
	shooter: Vector2i,
	mark: Vector2i,
	mark_hp: int = TOUGH,
	pool: int = POOL
) -> World:
	var defs: Array[UnitDef] = [
		_def(&"gun", INFANTRY, TOUGH, weapon), _def(&"mark", armour, mark_hp)
	]
	var world: World = _world(defs, pool)
	world.add_unit(1, 0, shooter.x, shooter.y)
	world.add_unit(2, 1, mark.x, mark.y)
	return world


## `_duel_at` with the shooter at SHOOTER_AT and the mark `offset` from it.
func _duel(weapon: WeaponDef, armour: int, offset: Vector2i, mark_hp: int = TOUGH) -> World:
	return _duel_at(weapon, armour, SHOOTER_AT, SHOOTER_AT + offset, mark_hp)


## Fires the shot of row 0 with `Combat.fire` and runs the two phases (PROJECTILES, then FIRE) until
## the IMPACT: returns the flight time written to the slot and the number of passes it took (-1 if
## none in 60). The records of the last pass stay in the World's events.
func _fly(world: World) -> Array[int]:
	Combat.fire(world)
	var launched: int = world.proj_ticks[world.proj_id.find(1)]
	for pass_number: int in range(1, 60):
		world.events.clear()
		Combat.advance_projectiles(world)
		if not _records(world, IMPACT).is_empty():
			return [launched, pass_number]
		Combat.fire(world)
	return [launched, -1]


## A slot's columns: id, owner, weapon, target, x, y, aim x, aim y, ticks left.
func _slot(world: World, slot: int) -> Array[int]:
	return [
		world.proj_id[slot],
		world.proj_owner[slot],
		world.proj_weapon[slot],
		world.proj_target[slot],
		world.proj_x[slot],
		world.proj_y[slot],
		world.proj_aim_x[slot],
		world.proj_aim_y[slot],
		world.proj_ticks[slot],
	]


## A weapon with a projectile of `speed` a tick, `damage` against `vs`, a range of REACH and no
## minimum range; its cooldown makes it fire once in a case.
func _shell(speed: int, damage: int = 30, cooldown: int = SLOW, vs: Array = GUN_VS) -> WeaponDef:
	return _weapon(&"shell", damage, cooldown, vs, speed)


func _weapon(id: StringName, damage: int, cooldown: int, vs: Array, speed: int) -> WeaponDef:
	var weapon: WeaponDef = WeaponDef.new()
	weapon.id = id
	weapon.range = REACH
	weapon.min_range = 0
	weapon.damage = damage
	weapon.cooldown_ticks = cooldown
	weapon.projectile_speed = speed
	weapon.vs_armour = PackedInt32Array(vs)
	return weapon


## A unit type of `armour` and `hp` that walks 120 a tick, sees 9000 and acquires at 5500.
func _def(id: StringName, armour: int, hp: int, weapon: WeaponDef = null) -> UnitDef:
	var def: UnitDef = UnitDef.new()
	def.type_id = id
	def.speed = 120
	def.radius = 300
	def.selection_radius = 350
	def.formation_spacing = 900
	def.max_hp = hp
	def.armour = armour
	def.sight_range = 9000
	def.acquire_range = 5500
	def.weapon = weapon
	return def


## The records of `kind` in the events of the last tick, each as the 8 ints.
func _records(world: World, kind: int) -> Array[Array]:
	var found: Array[Array] = []
	for at: int in range(0, world.events.size(), STRIDE):
		if world.events[at] == kind:
			found.append(Array(world.events.slice(at, at + STRIDE)))
	return found


func _order(command: Command, world: World) -> Command:
	command.tick = world.tick
	return command
