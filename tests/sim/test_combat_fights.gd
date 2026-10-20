extends GdUnitTestSuite
## Weapons, part 1 (P42a), the fights: what the FIRE phase changes in the engagement of P41b. Units
## that held at weapon range and stood there for good (the interim of P41b, while nothing could
## die) now shoot, lose hp and leave: a standoff ends, an `ATTACK` goes on until its target is gone,
## and a ground tap that a held unit ignored is followed once the enemy it was fighting is dead. The
## phase itself (cooldown, damage, the SHOT record, firing in the tick of death) is test_combat.gd.
##
## The worlds are the shipped unit types (TargetingRig.data_world): rifle squad 0, rocket squad 1,
## light tank 2 (300 hp, range 4500, acquire 5500, sight 7000, 21 damage to infantry and 18 to a
## light tank every 25 ticks; in P42a the cannon also hits at once). Every `ATTACK` target stands
## inside its attacker's sight, the authoring rule of the fog PR (P46b).

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const RIFLE: int = 0
const TANK: int = 2
const IDLE: int = World.Order.IDLE
const ATTACK_MOVE: int = World.Order.ATTACK_MOVE
const ATTACK: int = World.Order.ATTACK
const NONE: int = World.NavMode.NONE
const HOLD: int = World.NavMode.HOLD
const SHOT: int = World.Event.SHOT
const DIED: int = World.Event.DIED
const STRIDE: int = World.EVENT_STRIDE
## The meeting: three tanks a side on a 24 x 14 tile map, 14000 apart on one row, 1200 between the
## tanks of a side (a tank's formation spacing), each side attack-moving to the other's start.
const MEETING_TICKS: int = 700
## Before this tick of the meeting nobody has died: the first death is at tick 439.
const BEFORE_DEATHS: int = 300


## Opposing groups no longer hold for ever (the interim of P41b ends with P42a): three tanks a side
## attack-move at each other, stop at weapon range and trade cannon fire; at tick 300 nobody has
## died but all six hold and both sides are damaged; by tick 700 two blue tanks and all three red
## ones are gone, the survivor is a blue tank that has gone on to its goal and is idle, and every
## tank that left did so with one DIED record in the tick it was removed (the ids removed from the
## rows are the ids in the records, so the selection and the groups can follow them, P43a).
func test_two_groups_that_meet_hold_and_fight_until_one_side_is_gone() -> void:
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
		if not left.is_empty() and first_death < 0:
			first_death = tick
		if tick == BEFORE_DEATHS - 1:
			assert_int(world.unit_count()).is_equal(6)
			assert_int(world.nav_mode.count(HOLD)).is_equal(6)
			assert_bool(world.hp.slice(0, 3) != PackedInt32Array([300, 300, 300])).is_true()
			assert_bool(world.hp.slice(3, 6) != PackedInt32Array([300, 300, 300])).is_true()
	assert_int(first_death).is_equal(439)
	var lost_blue: int = gone.values().count(1)
	assert_array([lost_blue, gone.values().count(2)]).is_equal([2, 3])
	assert_int(world.unit_count()).is_equal(1)
	assert_int(world.owner[0]).is_equal(1)
	assert_array([world.order[0], world.nav_mode[0], world.target[0]]).is_equal([IDLE, NONE, 0])
	assert_array(Rig.outside_sight(world)).is_empty()


## Two runs of the meeting give the same state hash after every tick, deaths and compaction
## included, and the fight is part of the state: the hash at tick 300 (all alive, hp lowered) is not
## the hash of the same run with the cannons silenced (a damage percent of 0 against light armour).
func test_a_fight_gives_the_same_hash_twice_and_the_hp_is_part_of_it() -> void:
	var first: PackedInt64Array = _meeting_hashes(false)
	var second: PackedInt64Array = _meeting_hashes(false)
	assert_int(first.size()).is_equal(MEETING_TICKS)
	assert_array(second).is_equal(first)
	var silent: PackedInt64Array = _meeting_hashes(true)
	assert_int(silent[BEFORE_DEATHS - 1]).is_not_equal(first[BEFORE_DEATHS - 1])
	assert_int(silent[-1]).is_not_equal(first[-1])


## An `ATTACK` goes on until its target is dead (the P43b tap, "chase that enemy and fire until it
## dies"): a tank ordered to attack an idle rifle squad drives to 4400 of it (the squad's own reach
## is 4000, so it cannot answer), fires every 25 ticks, 21 hp each (100 to 79, 58, 37, 16, -5), and
## on the fifth shot the squad is removed in that tick. The order falls back to an attack-move to
## the place the squad stood, which the tank reaches and goes idle on. The tank is unhurt.
func test_an_attack_order_fires_until_the_target_dies_and_then_goes_to_where_it_stood() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, TANK, 3000, 6000)
	world.add_unit(2, RIFLE, 11000, 6000)
	var order: Command = Command.attack(1, PackedInt32Array([1]), 2)
	order.tick = 0
	var commands: Array[Command] = [order]
	var shots: Array[int] = []
	var squad_hp: Array[int] = []
	for tick: int in 400:
		Sim.step(world, commands)
		commands.clear()
		if not _records(world, SHOT).is_empty():
			shots.append(tick)
			squad_hp.append(world.hp[1] if world.unit_count() > 1 else -5)
			assert_int(world.order[0]).is_equal(ATTACK)
		if world.unit_count() == 1 and world.order[0] == IDLE:
			break
	assert_int(shots.size()).is_equal(5)
	for k: int in 4:
		assert_int(shots[k + 1] - shots[k]).is_equal(25)
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


## Three tanks of each side on a 24 x 14 tile map: blue at x 3000, red at x 17000, in a column of
## 1200 between tanks around y 6000. With `silenced` the cannon has a percent of 0 against light
## armour.
func _meeting(silenced: bool = false) -> World:
	var world: World = Rig.data_world(24, 14)
	if silenced:
		world.weapon_vs_armour[2 * World.Armour.size() + World.Armour.LIGHT] = 0
	for k: int in 3:
		world.add_unit(1, TANK, 3000, 4800 + 1200 * k)
	for k: int in 3:
		world.add_unit(2, TANK, 17000, 4800 + 1200 * k)
	return world


## The two attack-moves of the meeting for the World's tick: blue to red's start, red to blue's.
func _meeting_orders(world: World) -> Array[Command]:
	var orders: Array[Command] = [
		Command.attack_move(1, PackedInt32Array([1, 2, 3]), 17000, 6000),
		Command.attack_move(2, PackedInt32Array([4, 5, 6]), 3000, 6000),
	]
	for order: Command in orders:
		order.tick = world.tick
	return orders


## The state hash after each tick of the meeting; with `silenced` the cannon does no damage to light
## armour (its percent is 0), so the tanks hold and shoot for nothing.
func _meeting_hashes(silenced: bool) -> PackedInt64Array:
	var world: World = _meeting(silenced)
	var commands: Array[Command] = _meeting_orders(world)
	var hashes: PackedInt64Array = PackedInt64Array()
	for _tick: int in MEETING_TICKS:
		Sim.step(world, commands)
		commands.clear()
		hashes.append(world.state_hash())
	return hashes


## The records of `kind` in the events of the last tick, each as the 8 ints.
func _records(world: World, kind: int) -> Array[Array]:
	var found: Array[Array] = []
	for at: int in range(0, world.events.size(), STRIDE):
		if world.events[at] == kind:
			found.append(Array(world.events.slice(at, at + STRIDE)))
	return found
