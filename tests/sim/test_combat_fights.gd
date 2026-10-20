extends GdUnitTestSuite
## Weapons, parts 1 and 2 (P42a, P42b), the fights: what the FIRE and PROJECTILES phases change in
## the engagement of P41b. Units that held at weapon range and stood there for good (the interim of
## P41b, while nothing could die) now shoot, lose hp and leave: a standoff ends, an `ATTACK` goes on
## until its target is gone, and a ground tap that a held unit ignored is followed once the enemy it
## was fighting is dead. The phases themselves (cooldown, damage, the SHOT record, firing in the
## tick of death, the shells) are test_combat.gd and test_combat_projectiles.gd.
##
## The worlds are the shipped unit types (TargetingRig.data_world): rifle squad 0, rocket squad 1,
## light tank 2 (300 hp, range 4500, acquire 5500, sight 7000, 21 damage to infantry and 18 to a
## light tank every 25 ticks; the cannon shell flies 600 a tick, so a hit lands up to 8 ticks after
## its shot). The authoring rule of the fog PR (P46b) is kept and asserted: in the `ATTACK` case and
## in the meeting, no unit holds a target that still has a row and stands beyond its sight, on any
## tick (`_beyond_sight`).

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const FireProbe: GDScript = preload("res://tests/sim/support/fire_view_probe.gd")
const RIFLE: int = 0
const TANK: int = 2
const IDLE: int = World.Order.IDLE
const ATTACK_MOVE: int = World.Order.ATTACK_MOVE
const ATTACK: int = World.Order.ATTACK
const NONE: int = World.NavMode.NONE
const HOLD: int = World.NavMode.HOLD
const SHOT: int = World.Event.SHOT
const IMPACT: int = World.Event.IMPACT
const DIED: int = World.Event.DIED
const STRIDE: int = World.EVENT_STRIDE
## The meeting: three tanks a side on a 24 x 14 tile map, 14000 apart on one row, 1200 between the
## tanks of a side (a tank's formation spacing), each side attack-moving to the other's start.
const MEETING_TICKS: int = 700
## Before this tick of the meeting nobody has died: the first death is at tick 447.
const BEFORE_DEATHS: int = 300


## Opposing groups of equal strength no longer hold for ever (the interim of P41b ends with P42a):
## three tanks a side attack-move at each other, stop at weapon range and trade cannon fire; at tick
## 300 nobody has died but all six hold and both sides are damaged. By tick 700 all six are gone:
## the two groups are alike, so every tank has taken the same hits (102 hp at tick 300, 12 at tick
## 446) and five of them are removed in tick 447, the first death; the sixth was left with 12 hp and
## a shell of a tank that died in tick 447 lands on it in tick 448 (a shell outlives its shooter,
## P42b; with every hit at once, in P42a, one blue tank was left). Every tank that left did so with
## one DIED record in the tick it was removed (the ids removed from the rows are the ids in the
## records, so the selection and the groups can follow them, P43a). A group that outnumbers the
## other is the next test.
func test_two_equal_groups_that_meet_hold_and_fight_until_both_are_gone() -> void:
	var world: World = _meeting()
	var commands: Array[Command] = _meeting_orders(world)
	var gone: Dictionary[int, int] = {}
	var first_death: int = -1
	for tick: int in MEETING_TICKS:
		var before: PackedInt32Array = world.unit_id.duplicate()
		Sim.step(world, commands)
		commands.clear()
		var left: Array[int] = []
		for id: int in before:
			if world.index_of(id) < 0:
				left.append(id)
		var recorded: Array[int] = []
		for record: Array in _records(world, DIED):
			recorded.append(record[1])
			gone[record[1]] = record[5]
		assert_array(recorded).override_failure_message("tick %d" % tick).is_equal(left)
		assert_array(_beyond_sight(world)).override_failure_message("tick %d" % tick).is_empty()
		if not left.is_empty() and first_death < 0:
			first_death = tick
		if tick == BEFORE_DEATHS - 1:
			assert_int(world.unit_count()).is_equal(6)
			assert_int(world.nav_mode.count(HOLD)).is_equal(6)
			assert_bool(world.hp.slice(0, 3) != PackedInt32Array([300, 300, 300])).is_true()
			assert_bool(world.hp.slice(3, 6) != PackedInt32Array([300, 300, 300])).is_true()
	assert_int(first_death).is_equal(447)
	assert_array([gone.values().count(1), gone.values().count(2)]).is_equal([3, 3])
	assert_int(world.unit_count()).is_equal(0)
	assert_int(gone.size()).is_equal(6)


## The group that outnumbers the other wins and goes on (the attack-move row of HOW_TO_PLAY, "they
## stop to fight, then continue"): three blue tanks meet two red ones. The red tanks are removed in
## ticks 247 and 322, one DIED record each, and no blue tank is lost (84, 138 and 300 hp are left);
## by tick 404 the last shell has landed and each of the three has gone on to its place at the red
## start (x 17000, 17000 and 16608, far beyond the 12200 where the fight was) and is idle with no
## navigation mode and no target.
func test_the_larger_group_of_a_meeting_wins_and_goes_on_to_its_goal() -> void:
	var world: World = _meeting(2)
	var commands: Array[Command] = _meeting_orders(world, 2)
	var gone: Dictionary[int, int] = {}
	var settled_at: int = -1
	for tick: int in MEETING_TICKS:
		Sim.step(world, commands)
		commands.clear()
		for record: Array in _records(world, DIED):
			gone[record[1]] = record[5]
		assert_array(_beyond_sight(world)).override_failure_message("tick %d" % tick).is_empty()
		if world.owner.count(2) == 0 and world.order.count(IDLE) == world.unit_count():
			settled_at = tick
			break
	assert_int(settled_at).is_equal(404)
	assert_array([gone.values().count(1), gone.values().count(2)]).is_equal([0, 2])
	assert_array(world.unit_id).is_equal([1, 2, 3])
	assert_array(world.hp).is_equal([84, 138, 300])
	assert_array(world.order).is_equal([IDLE, IDLE, IDLE])
	assert_array(world.nav_mode).is_equal([NONE, NONE, NONE])
	assert_array(world.target).is_equal([0, 0, 0])
	assert_array(world.pos_x).is_equal([17000, 17000, 16608])
	assert_int(world.max_projectiles - world.proj_free_top).is_equal(0)


## Two runs of the meeting give the same state hash after every tick, deaths and compaction
## included, and the hp the fight leaves is part of that hash: two Worlds run to tick 300 (all six
## alive, hp lowered) have the same hash, and when one of them has its hp put back to the type's 300
## (every position, order, navigation mode and target the same) the hashes differ.
func test_a_fight_gives_the_same_hash_twice_and_the_hp_is_part_of_it() -> void:
	var first: PackedInt64Array = _meeting_hashes()
	var second: PackedInt64Array = _meeting_hashes()
	assert_int(first.size()).is_equal(MEETING_TICKS)
	assert_array(second).is_equal(first)
	var hurt: World = _meeting_at(BEFORE_DEATHS)
	var healed: World = _meeting_at(BEFORE_DEATHS)
	assert_int(hurt.state_hash()).is_equal(first[BEFORE_DEATHS - 1])
	assert_int(healed.state_hash()).is_equal(first[BEFORE_DEATHS - 1])
	assert_bool(hurt.hp.count(300) < hurt.unit_count()).is_true()
	healed.hp.fill(300)
	assert_array(healed.hp).is_not_equal(hurt.hp)
	for column: Array in [
		[healed.unit_id, hurt.unit_id],
		[healed.pos_x, hurt.pos_x],
		[healed.pos_y, hurt.pos_y],
		[healed.order, hurt.order],
		[healed.nav_mode, hurt.nav_mode],
		[healed.target, hurt.target],
		[healed.cooldown, hurt.cooldown],
	]:
		assert_array(column[0]).is_equal(column[1])
	assert_int(healed.state_hash()).is_not_equal(hurt.state_hash())


## An `ATTACK` goes on until its target is dead (the P43b tap, "chase that enemy and fire until it
## dies"): a tank ordered to attack an idle rifle squad 6500 away (inside the tank's sight of 7000)
## drives to 4400 of it (the squad's own reach is 4000, so it cannot answer), fires every 25 ticks,
## and each shell lands 8 ticks after its shot (4400 at 600 a tick) for 21 hp (100 to 79, 58, 37,
## 16, -5, each read at the PROJECTILES mark of the landing tick); the fifth shot is the last, since
## its shell lands before the sixth is due, and the squad is removed in that tick. The order falls
## back to an attack-move to the place the squad stood, which the tank reaches and goes idle on.
## The tank is unhurt.
func test_an_attack_order_fires_until_the_target_dies_and_then_goes_to_where_it_stood() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, TANK, 4500, 6000)
	world.add_unit(2, RIFLE, 11000, 6000)
	var order: Command = Command.attack(1, PackedInt32Array([1]), 2)
	order.tick = 0
	var commands: Array[Command] = [order]
	var shots: Array[int] = []
	var landings: Array[int] = []
	var squad_hp: Array[int] = []
	for tick: int in 400:
		var probe: FireProbe = FireProbe.new(world)
		Sim.step(world, commands, probe)
		commands.clear()
		assert_array(_beyond_sight(world)).override_failure_message("tick %d" % tick).is_empty()
		if not _records(world, SHOT).is_empty():
			shots.append(tick)
			assert_int(world.order[0]).is_equal(ATTACK)
		if not _records(world, IMPACT).is_empty():
			landings.append(tick)
			squad_hp.append(probe.hit_points[probe.phases.find(SimProbe.Phase.PROJECTILES)])
			assert_int(world.order[0]).is_equal(ATTACK)
		if world.unit_count() == 1 and world.order[0] == IDLE:
			break
	assert_int(shots.size()).is_equal(5)
	for k: int in 4:
		assert_int(shots[k + 1] - shots[k]).is_equal(25)
	assert_array(landings).is_equal(shots.map(func(tick: int) -> int: return tick + 8))
	assert_array(squad_hp).is_equal([79, 58, 37, 16, -5])
	assert_int(world.unit_count()).is_equal(1)
	assert_array([world.order[0], world.pos_x[0], world.pos_y[0]]).is_equal([IDLE, 11000, 6000])
	assert_int(world.order_target[0]).is_equal(0)
	assert_int(world.hp[0]).is_equal(300)


## A ground tap does not move a unit that holds an enemy in weapon range (the attack-move row of
## HOW_TO_PLAY), and since P42a that lasts only while the enemy lives. A rifle squad at 6000 holds a
## rifle squad 3000 east of it (the enemy has 24 hp: two hits of 12, the second in tick 19); the tap
## at tick 10 sends it to 14000 behind the enemy, and it stays on its spot, in HOLD, for as long as
## the enemy is there; the tick after the enemy is removed it takes its first step towards the tap
## and goes on to arrive on it, idle.
func test_a_ground_tap_is_followed_once_the_enemy_it_was_fighting_is_dead() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, RIFLE, 6000, 6000)
	world.add_unit(2, RIFLE, 9000, 6000)
	world.hp[1] = 24
	for _tick: int in 10:
		Sim.step(world, [])
	assert_array([world.nav_mode[0], world.target[0]]).is_equal([HOLD, 2])
	var tap: Command = Command.attack_move(1, PackedInt32Array([1]), 14000, 6000)
	tap.tick = world.tick
	var commands: Array[Command] = [tap]
	var removed_at: int = -1
	for _tick: int in 400:
		Sim.step(world, commands)
		commands.clear()
		if removed_at < 0:
			assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([6000, 6000])
			if world.unit_count() == 1:
				removed_at = world.tick
			else:
				assert_int(world.nav_mode[0]).is_equal(HOLD)
		elif world.order[0] == IDLE:
			break
	assert_int(removed_at).is_equal(20)
	assert_array([world.order[0], world.pos_x[0], world.pos_y[0]]).is_equal([IDLE, 14000, 6000])
	assert_int(world.nav_mode[0]).is_equal(NONE)


## Three blue tanks and `red_count` red ones on a 24 x 14 tile map: blue at x 3000, red at x 17000,
## in a column of 1200 between tanks from y 4800.
func _meeting(red_count: int = 3) -> World:
	var world: World = Rig.data_world(24, 14)
	for k: int in 3:
		world.add_unit(1, TANK, 3000, 4800 + 1200 * k)
	for k: int in red_count:
		world.add_unit(2, TANK, 17000, 4800 + 1200 * k)
	return world


## The two attack-moves of the meeting for the World's tick: blue (ids 1 to 3) to red's start, red
## (the `red_count` ids from 4) to blue's.
func _meeting_orders(world: World, red_count: int = 3) -> Array[Command]:
	var red: PackedInt32Array = PackedInt32Array()
	for k: int in red_count:
		red.append(4 + k)
	var orders: Array[Command] = [
		Command.attack_move(1, PackedInt32Array([1, 2, 3]), 17000, 6000),
		Command.attack_move(2, red, 3000, 6000),
	]
	for order: Command in orders:
		order.tick = world.tick
	return orders


## The meeting after `ticks` ticks.
func _meeting_at(ticks: int) -> World:
	var world: World = _meeting()
	var commands: Array[Command] = _meeting_orders(world)
	for _tick: int in ticks:
		Sim.step(world, commands)
		commands.clear()
	return world


## The state hash after each tick of the meeting.
func _meeting_hashes() -> PackedInt64Array:
	var world: World = _meeting()
	var commands: Array[Command] = _meeting_orders(world)
	var hashes: PackedInt64Array = PackedInt64Array()
	for _tick: int in MEETING_TICKS:
		Sim.step(world, commands)
		commands.clear()
		hashes.append(world.state_hash())
	return hashes


## The ids of the units whose target still has a row and stands beyond their sight. The rig's
## `outside_sight` also lists a unit whose target was removed in the tick: the unit finds that out
## at its next scan (ADR 0007 section 3), so it is not a unit that sees too little.
func _beyond_sight(world: World) -> Array[int]:
	var found: Array[int] = []
	for id: int in Rig.outside_sight(world):
		if world.index_of(world.target[world.index_of(id)]) >= 0:
			found.append(id)
	return found


## The records of `kind` in the events of the last tick, each as the 8 ints.
func _records(world: World, kind: int) -> Array[Array]:
	var found: Array[Array] = []
	for at: int in range(0, world.events.size(), STRIDE):
		if world.events[at] == kind:
			found.append(Array(world.events.slice(at, at + STRIDE)))
	return found
