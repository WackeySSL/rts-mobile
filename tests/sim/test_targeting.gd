extends GdUnitTestSuite
## Target acquisition (P41; ADR 0009 section 2, ADR 0007 section 4): `Targeting.run` in the
## TARGETING phase, after the targeting grid is rebuilt in GRIDS. The cases here pin the priority
## (damage percent, then distance, then id), the stagger, stickiness, the reach by order, the
## position in the tick, idle units staying put, and the hashes. Cell borders, the range edges,
## minimum range, armour percents, owners, unarmed types and the work count are in
## test_targeting_edges.gd. The engagement part (the ATTACK lock, chasing, holding) is P41b's.
##
## The worlds are the shipped unit types (TargetingRig.data_world): rifle squad 0, rocket squad 1,
## light tank 2 on a 20 x 12 tile map. Rifle: range 4000, acquire 5000, 100 / 10 percent against
## infantry / light. Rocket: 5000, 5500, 20 / 100. Tank: 4500, 5500, 70 / 60. Every target stands
## inside its unit's sight (6000, 6000, 7000), the authoring rule of the fog PR (P46b): each case
## asserts it through `outside_sight`. A unit is due on the ticks where `(tick + id) % 5 == 0`;
## `target_of(world, id)` moves the tick to the unit's next due tick, runs the GRIDS and TARGETING
## phases and returns its target.

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const ViewProbe: GDScript = preload("res://tests/sim/support/targeting_view_probe.gd")
const SightProbe: GDScript = preload("res://tests/sim/support/targeting_sight_probe.gd")
const MatchScript: GDScript = preload("res://tests/sim/support/match_script.gd")
const RIFLE: int = 0
const ROCKET: int = 1
const TANK: int = 2
const IDLE: int = World.Order.IDLE
const ATTACK_MOVE: int = World.Order.ATTACK_MOVE
const MOVE: int = World.Order.MOVE
const ATTACK: int = World.Order.ATTACK
## The arena match of the hash and sight cases: the sides meet in the first 100 ticks.
const ARENA_TICKS: int = 300


## A rocket squad prefers the tank (100%) to the rifle squad (20%) that stands closer, and a rifle
## squad prefers infantry (100%) to the tank (10%) that stands closer. The percent comes first, and
## a candidate out of range is not considered at all: with the tank 5500 away (rocket range 5000)
## the rocket squad takes the rifle squad.
func test_the_highest_damage_percent_comes_before_the_distance() -> void:
	var rocket: World = Rig.data_world()
	rocket.add_unit(1, ROCKET, 10000, 6000)
	rocket.add_unit(2, RIFLE, 12000, 6000)
	rocket.add_unit(2, TANK, 14500, 6000)
	assert_int(Rig.target_of(rocket, 1)).is_equal(3)
	assert_array(Rig.outside_sight(rocket)).is_empty()
	rocket.pos_x[2] = 15500
	assert_int(Rig.target_of(rocket, 1)).is_equal(2)
	var rifle: World = Rig.data_world()
	rifle.add_unit(1, RIFLE, 10000, 6000)
	rifle.add_unit(2, TANK, 12000, 6000)
	rifle.add_unit(2, RIFLE, 13500, 6000)
	assert_int(Rig.target_of(rifle, 1)).is_equal(3)
	assert_array(Rig.outside_sight(rifle)).is_empty()


## Equal percents go to the smaller distance, whichever has the lower id: the rocket squad (20% on
## both rifle squads) takes the one 2000 away, in either order of ids.
func test_equal_percents_go_to_the_smaller_distance() -> void:
	for near_first: bool in [true, false]:
		var world: World = Rig.data_world()
		world.add_unit(1, ROCKET, 10000, 6000)
		world.add_unit(2, RIFLE, 12000 if near_first else 14000, 6000)
		world.add_unit(2, RIFLE, 14000 if near_first else 12000, 6000)
		assert_int(Rig.target_of(world, 1)).is_equal(2 if near_first else 3)
		assert_array(Rig.outside_sight(world)).is_empty()


## Equal percents and equal distances go to the lower id, wherever it stands. The grid is visited
## cell by cell, west to east and north to south, not in id order, and a cell lists its rows in
## ascending order. The first three arrangements put the lower id in the cell that is visited last:
## east of the west one, south of the north one, and a 3-4-5 triangle (all three 5000 away, the
## rocket's range) where the lowest id stands in the last line of cells. The last three put it in
## the cell that is visited first (west of the east one, north of the south one) and have two units
## on one point, where the lower id is also listed first: a later candidate that ties does not win.
func test_equal_percents_and_distances_go_to_the_lower_id() -> void:
	var cases: Array[Array] = [
		[Vector2i(13000, 6000), Vector2i(7000, 6000), Vector2i(10000, 3000)],
		[Vector2i(10000, 9000), Vector2i(10000, 3000), Vector2i(10000, 3000)],
		[Vector2i(13000, 10000), Vector2i(15000, 6000), Vector2i(7000, 2000)],
		[Vector2i(7000, 6000), Vector2i(13000, 6000)],
		[Vector2i(10000, 3000), Vector2i(10000, 9000)],
		[Vector2i(12000, 6000), Vector2i(12000, 6000)],
	]
	for item: Array in cases:
		var world: World = Rig.data_world()
		world.add_unit(1, ROCKET, 10000, 6000)
		for at: Vector2i in item:
			world.add_unit(2, RIFLE, at.x, at.y)
		var picked: int = Rig.target_of(world, 1)
		assert_int(picked).override_failure_message(str(item)).is_equal(2)
		assert_array(Rig.outside_sight(world)).is_empty()


## A unit scans only on the ticks where `(tick + id) % 5 == 0`. The target is cleared before every
## tick of 15, so it shows when the unit looked: unit 3 on ticks 2, 7 and 12, its enemy unit 4 on 1,
## 6 and 11. The other two units are far away and look at nothing.
func test_a_unit_scans_only_on_the_ticks_its_id_makes_due() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, RIFLE, 1000, 11000)
	world.add_unit(1, RIFLE, 1000, 9000)
	world.add_unit(1, RIFLE, 5000, 3000)
	world.add_unit(2, RIFLE, 8000, 3000)
	var due: Dictionary[int, Array] = {3: [], 4: []}
	for tick: int in 15:
		world.target.fill(0)
		world.tick = tick
		Rig.acquire(world)
		for id: int in [3, 4]:
			if world.target[world.index_of(id)] != 0:
				due[id].append(tick)
	assert_array(due[3]).is_equal([2, 7, 12])
	assert_array(due[4]).is_equal([1, 6, 11])
	assert_array(world.target.slice(0, 2)).is_equal([0, 0])


## The period is the rules' `retarget_period_ticks` (5 in data/rules.tres), read from the World:
## a period of 3 makes unit 3 due on ticks 0, 3, 6, 9 and 12, and a period below 1 is read as 1
## (every tick, no division by zero).
func test_the_period_comes_from_the_rules() -> void:
	var world: World = Rig.data_world()
	assert_int(world.retarget_period_ticks).is_equal(5)
	world.add_unit(1, RIFLE, 1000, 11000)
	world.add_unit(1, RIFLE, 1000, 9000)
	world.add_unit(1, RIFLE, 5000, 3000)
	world.add_unit(2, RIFLE, 8000, 3000)
	var cases: Dictionary[int, Array] = {3: [0, 3, 6, 9, 12], 1: range(13), 0: range(13)}
	for period: int in cases:
		world.retarget_period_ticks = period
		var due: Array[int] = []
		for tick: int in 13:
			world.target.fill(0)
			world.tick = tick
			Rig.acquire(world)
			if world.target[2] != 0:
				due.append(tick)
		assert_array(due).override_failure_message("period %d" % period).is_equal(cases[period])


## A valid target in reach is kept over a nearer new one, and over a better one (a tank, 100%
## against the rocket squad's 20% for rifle squads). The rocket squad takes the rifle squad 3000
## away at tick 4; a rifle squad appears 1500 away and a tank 3606 away, and at tick 9 and 14 the
## target is still the first. When that one walks out of reach (6000 against 5000), the target is
## still it until the squad's next due tick, 19, and then it is the tank.
func test_a_valid_target_in_reach_is_kept_over_a_nearer_or_better_new_one() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, ROCKET, 10000, 6000)
	world.add_unit(2, RIFLE, 13000, 6000)
	assert_int(Rig.target_of(world, 1)).is_equal(2)
	assert_int(world.tick).is_equal(4)
	world.add_unit(2, RIFLE, 11500, 6000)
	assert_int(Rig.retarget(world, 1)).is_equal(2)
	world.add_unit(2, TANK, 12000, 9000)
	assert_int(Rig.retarget(world, 1)).is_equal(2)
	assert_int(world.tick).is_equal(14)
	world.pos_x[1] = 16000
	for tick: int in range(15, 19):
		world.tick = tick
		Rig.acquire(world)
		assert_int(world.target[0]).override_failure_message("tick %d" % tick).is_equal(2)
	assert_int(Rig.retarget(world, 1)).is_equal(4)
	assert_int(world.tick).is_equal(19)
	assert_array(Rig.outside_sight(world)).is_empty()


## A target that is gone (its row removed), or no longer an enemy (it became a friend or neutral),
## is not valid: the next scan replaces it, with 0 when nothing else is in reach. The gone one is
## first an id between two others (the lookup lands on a row of another id), then the highest id
## (the lookup lands past the last row, the first death of a match to be the newest unit).
func test_a_target_that_is_gone_is_replaced_at_the_next_due_tick() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, RIFLE, 10000, 6000)
	world.add_unit(2, RIFLE, 12000, 6000)
	world.add_unit(2, RIFLE, 8000, 6000)
	assert_int(Rig.target_of(world, 1)).is_equal(2)
	world.hp[1] = 0
	world.remove_dead()
	assert_int(world.index_of(2)).is_equal(-1)
	assert_int(Rig.retarget(world, 1)).is_equal(3)
	world.owner[1] = 1
	assert_int(Rig.retarget(world, 1)).is_equal(0)
	world.owner[1] = 2
	assert_int(Rig.retarget(world, 1)).is_equal(3)
	world.owner[1] = 0
	assert_int(Rig.retarget(world, 1)).is_equal(0)
	var newest: World = Rig.data_world()
	newest.add_unit(1, RIFLE, 10000, 6000)
	newest.add_unit(2, RIFLE, 12000, 6000)
	assert_int(Rig.target_of(newest, 1)).is_equal(2)
	newest.hp[1] = 0
	newest.remove_dead()
	assert_int(newest.unit_count()).is_equal(1)
	assert_int(Rig.retarget(newest, 1)).is_equal(0)


## The reach depends on the order: an attack-moving unit looks as far as its acquire range, an idle
## one as far as its weapon's range. Per type, an enemy just inside the weapon range is taken in
## both, one just inside the acquire range only when attack-moving, and one just outside the acquire
## range in neither: rifle squad (4000 / 5000), rocket squad (5000 / 5500), tank (4500 / 5500).
func test_attack_move_reaches_as_far_as_acquire_range_and_idle_as_far_as_weapon_range() -> void:
	var cases: Array[Array] = [[RIFLE, 4000, 5000], [ROCKET, 5000, 5500], [TANK, 4500, 5500]]
	for item: Array in cases:
		var weapon_range: int = item[1]
		var acquire_range: int = item[2]
		for gap: Array in [
			[0, true, true], [1, false, true], [acquire_range - weapon_range, false, true]
		]:
			var distance: int = weapon_range + int(gap[0])
			var world: World = Rig.data_world()
			world.add_unit(1, int(item[0]), 6000, 6000)
			world.add_unit(2, RIFLE, 6000 + distance, 6000)
			var label: String = "type %d at %d" % [item[0], distance]
			world.order[0] = IDLE
			var idle_target: int = Rig.target_of(world, 1)
			assert_bool(idle_target == 2).override_failure_message(label).is_equal(gap[1])
			world.target[0] = 0
			world.order[0] = ATTACK_MOVE
			var moving_target: int = Rig.target_of(world, 1)
			assert_bool(moving_target == 2).override_failure_message(label).is_equal(gap[2])
			assert_array(Rig.outside_sight(world)).is_empty()
		var outside: World = Rig.data_world()
		outside.add_unit(1, int(item[0]), 6000, 6000)
		outside.add_unit(2, RIFLE, 6000 + acquire_range + 1, 6000)
		outside.order[0] = ATTACK_MOVE
		assert_int(Rig.target_of(outside, 1)).override_failure_message(str(item)).is_equal(0)


## A MOVE order never acquires, and a unit that gets one drops the target it had on the very next
## pass (not only on its due tick): a unit that moves does not fire. The same unit, idle again,
## takes the enemy 1000 away on its next due tick.
func test_a_move_order_never_acquires_and_drops_its_target() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, RIFLE, 10000, 6000)
	world.add_unit(2, RIFLE, 11000, 6000)
	assert_int(Rig.target_of(world, 1)).is_equal(2)
	world.order[0] = MOVE
	world.tick += 1
	Rig.acquire(world)
	assert_int(world.target[0]).is_equal(0)
	assert_int(Rig.target_of(world, 1)).is_equal(0)
	world.order[0] = IDLE
	assert_int(Rig.retarget(world, 1)).is_equal(2)


## The ATTACK order is the engagement part's (P41b), which locks the row to its `order_target`.
## Until then an ATTACK row acquires nothing and holds no target, whatever stands 1000 away and
## whatever it held before the order (here a stale id); `order_target` stays as the command set it.
## P41b replaces this case with the lock.
func test_an_attack_row_acquires_nothing_and_holds_no_target_until_the_lock() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, RIFLE, 10000, 6000)
	world.add_unit(1, RIFLE, 10000, 8000)
	world.add_unit(2, RIFLE, 11000, 6000)
	world.order[0] = ATTACK
	world.order_target[0] = 3
	world.order[1] = ATTACK
	world.order_target[1] = 3
	world.target[1] = 3
	for id: int in [1, 2]:
		assert_int(Rig.target_of(world, id)).override_failure_message(str(id)).is_equal(0)
	assert_array([world.order_target[0], world.order_target[1]]).is_equal([3, 3])
	assert_array([world.order[0], world.order[1]]).is_equal([ATTACK, ATTACK])


## The marks of the tick, with the grid and the targets at each: the targeting grid holds the rows
## from GRIDS on (two cells for the two units), the subject's target is set at TARGETING and not
## before, and so are the candidates it looked at. Unit 1 is due at tick 4.
func test_the_grid_is_rebuilt_in_grids_and_targeting_follows_it() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, RIFLE, 5000, 3000)
	world.add_unit(2, RIFLE, 8000, 3000)
	world.tick = 4
	var probe: ViewProbe = ViewProbe.new(world)
	Sim.step(world, [], probe)
	var phases: Array[int] = [SimProbe.Phase.COMMANDS, SimProbe.Phase.FLOW, SimProbe.Phase.GRIDS]
	phases.append_array([SimProbe.Phase.TARGETING, SimProbe.Phase.INTENTS])
	phases.append_array(
		[SimProbe.Phase.SEPARATION, SimProbe.Phase.INTEGRATE, SimProbe.Phase.REMOVE]
	)
	assert_array(probe.phases).is_equal(phases)
	assert_array(probe.occupied).is_equal([0, 0, 2, 2, 2, 2, 2, 2])
	assert_array(probe.targets).is_equal([0, 0, 0, 2, 2, 2, 2, 2])
	assert_array(probe.candidates).is_equal([0, 0, 0, 1, 1, 1, 1, 1])


## The grid the scan reads is the one built in the same tick: unit 2 stands far away at tick 3 and
## is moved next to unit 1 between the ticks, and unit 1 (due at tick 4) takes it in that step. A
## grid from the tick before would list it in the far cell.
func test_the_scan_reads_the_grid_of_its_own_tick() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, RIFLE, 5000, 3000)
	world.add_unit(2, RIFLE, 15000, 3000)
	world.tick = 3
	Sim.step(world, [])
	assert_int(world.target[0]).is_equal(0)
	world.pos_x[1] = 8000
	Sim.step(world, [])
	assert_array([world.tick, world.target[0]]).is_equal([5, 2])


## The grid is rebuilt on every tick, odd or even. The case above scans at an even tick only, so a
## rebuild that skips the odd ticks (when the rows only moved) would pass it. With a period of 1
## every unit is due every tick, so the parity is free: unit 2 stands far away at the first step and
## is moved next to unit 1 before the second, which runs at the other parity. The first tick is 2
## (second step at 3) and 3 (second step at 4).
func test_the_grid_is_rebuilt_on_every_tick_odd_or_even() -> void:
	for first_tick: int in [2, 3]:
		var world: World = Rig.data_world()
		world.retarget_period_ticks = 1
		world.add_unit(1, RIFLE, 5000, 3000)
		world.add_unit(2, RIFLE, 15000, 3000)
		world.tick = first_tick
		Sim.step(world, [])
		assert_int(world.target[0]).override_failure_message("far at %d" % first_tick).is_equal(0)
		world.pos_x[1] = 8000
		Sim.step(world, [])
		var label: String = "scan at tick %d" % (first_tick + 1)
		assert_int(world.target[0]).override_failure_message(label).is_equal(2)


## `_follow_targets` (the ATTACK stand-in until P41b) runs after the TARGETING mark, inside INTENTS:
## an ATTACK row's goal is still where it was at the TARGETING mark and is its target's position at
## the INTENTS mark. Row 0 stands at x 10000 with its goal there and attacks unit 2 at x 12000.
func test_the_attack_stand_in_follows_its_target_after_the_targeting_mark() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, RIFLE, 10000, 6000)
	world.add_unit(2, RIFLE, 12000, 6000)
	world.order[0] = ATTACK
	world.order_target[0] = 2
	world.goal_x[0] = 10000
	var probe: ViewProbe = ViewProbe.new(world)
	Sim.step(world, [], probe)
	assert_int(probe.goals[probe.phases.find(SimProbe.Phase.GRIDS)]).is_equal(10000)
	assert_int(probe.goals[probe.phases.find(SimProbe.Phase.TARGETING)]).is_equal(10000)
	assert_int(probe.goals[probe.phases.find(SimProbe.Phase.INTENTS)]).is_equal(12000)


## An ATTACK row whose target is gone becomes an attack-move in `_follow_targets`, after Targeting
## has cleared the row: it is still ATTACK at the TARGETING mark and ATTACK_MOVE at the INTENTS
## mark, and it takes no target in that step although it is due (tick 4 for unit 1) with an enemy
## 2000 away. At its next due tick, 9, it does.
func test_an_attack_row_with_a_gone_target_acquires_at_its_next_due_tick() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, RIFLE, 10000, 6000)
	world.add_unit(2, RIFLE, 12000, 6000)
	world.order[0] = ATTACK
	world.order_target[0] = 99
	world.tick = 4
	var probe: ViewProbe = ViewProbe.new(world)
	Sim.step(world, [], probe)
	assert_int(probe.orders[probe.phases.find(SimProbe.Phase.TARGETING)]).is_equal(ATTACK)
	assert_int(probe.orders[probe.phases.find(SimProbe.Phase.INTENTS)]).is_equal(ATTACK_MOVE)
	assert_array(probe.targets).is_equal([0, 0, 0, 0, 0, 0, 0, 0])
	assert_int(world.target[0]).is_equal(0)
	for _tick: int in range(5, 9):
		Sim.step(world, [])
	assert_int(world.target[0]).is_equal(0)
	Sim.step(world, [])
	assert_array([world.tick, world.target[0]]).is_equal([10, 2])


## An idle unit never moves on its own. Two pairs of enemies, each inside the weapons' ranges of
## the other (rifle squad and rocket squad 3000 apart, tank and rifle squad 3500 apart), stand idle
## for 150 ticks: they all take their enemy as the target, and nobody's position, goal, order or
## intent changes, and nobody chases. The navigation mode is P41b's (it holds an idle unit that has
## a target in weapon range), so only CHASE is excluded here.
func test_idle_units_never_move_on_their_own() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, RIFLE, 3000, 3000)
	world.add_unit(2, ROCKET, 6000, 3000)
	world.add_unit(1, TANK, 14000, 9000)
	world.add_unit(2, RIFLE, 14000, 5500)
	var before: Array[PackedInt32Array] = [
		world.pos_x.duplicate(),
		world.pos_y.duplicate(),
		world.goal_x.duplicate(),
		world.goal_y.duplicate()
	]
	for _tick: int in 150:
		Sim.step(world, [])
	assert_array(world.target).is_equal([2, 1, 4, 3])
	assert_array(Rig.outside_sight(world)).is_empty()
	var after: Array[PackedInt32Array] = [world.pos_x, world.pos_y, world.goal_x, world.goal_y]
	for k: int in 4:
		assert_array(after[k]).is_equal(before[k])
	assert_array(world.order).is_equal([IDLE, IDLE, IDLE, IDLE])
	for mode: int in world.nav_mode:
		assert_int(mode).is_not_equal(World.NavMode.CHASE)
	assert_array(world.intent_x.slice(0, 4)).is_equal([0, 0, 0, 0])
	assert_array(world.intent_y.slice(0, 4)).is_equal([0, 0, 0, 0])


## Two runs of the arena match (the same seed and commands) give the same state hash at every
## checkpoint, and the hashes are not those of a run where nobody is ever due (a period of a
## million ticks): the targets are part of the state. The sides meet at about tick 15, so the
## hashes of the two differ from the first checkpoint on.
func test_two_runs_give_the_same_hashes() -> void:
	var first: PackedInt64Array = _arena_hashes(0)
	var second: PackedInt64Array = _arena_hashes(0)
	assert_int(first.size()).is_equal(ARENA_TICKS / Replay.CHECKPOINT_PERIOD)
	assert_array(second).is_equal(first)
	var silent: PackedInt64Array = _arena_hashes(1000000)
	assert_int(silent.size()).is_equal(first.size())
	for k: int in first.size():
		assert_int(silent[k]).override_failure_message("checkpoint %d" % k).is_not_equal(first[k])


## The authoring rule of the fog PR on the shipped units: through the arena match, every target
## chosen at a scan stands inside the sight of the unit that chose it (acquire never exceeds sight
## in data/), and a good number are chosen. A SightProbe looks at the TARGETING mark of each tick.
func test_every_target_of_the_arena_match_is_chosen_inside_its_acquirers_sight() -> void:
	var world: World = MatchScript.world(42)
	var match_loop: MatchLoop = MatchScript.loop(world, 42)
	var probe: SightProbe = SightProbe.new(world)
	for _tick: int in ARENA_TICKS:
		match_loop.step(world, MatchScript.commands_at(world.tick), probe)
	assert_array(probe.outside).is_empty()
	assert_int(probe.checked).is_greater(500)


## The checkpoint hashes of the arena match with `retarget_period_ticks` set to `period` (0 keeps
## the rules' own).
func _arena_hashes(period: int) -> PackedInt64Array:
	var world: World = MatchScript.world(42)
	if period > 0:
		world.retarget_period_ticks = period
	var match_loop: MatchLoop = MatchScript.loop(world, 42)
	MatchScript.play(world, match_loop, ARENA_TICKS)
	return match_loop.replay.checkpoint_hashes
