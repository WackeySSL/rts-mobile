extends GdUnitTestSuite
## The TARGETING kernel against its GDScript twin with hold position (plan row P298, ADR 0037
## section 15; ADR 0013 section 4), compared like test_targeting_lockstep.gd
## (targeting_lockstep_rig.gd).
## - Crafted pairs, one TARGETING phase each: a held attack-mover takes a target at weapon range
##   (HOLD) but not at acquire range, and never takes CHASE; an unheld one does both; a held ATTACK
##   whose target is gone goes IDLE where it stands (an unheld one attack-moves on); a held row that
##   was chasing goes back to its path.
## - The engagement branch of a held row: retarget period 5 (so the row is not due, and `run`
##   keeps its out-of-range target and `_engage` sees it): a chaser put on hold goes back to its
##   path, an unheld one keeps chasing; the unheld twin at period 1 is the case above.
## - A held ATTACK whose target is out of sight goes IDLE; an idle duel plays the same with either
##   stance; a held attack-mover walks on, tick by tick, with no CHASE.
## - 300 seeded states with a random stance per row, one phase each, and 12 fields stepped 90 ticks
##   under random waves: the twin and the kernel end in the same state after every tick, and no held
##   row is ever in CHASE.
## The floors are measured on the twin and set at about two thirds of the figure; the
## measurements are beside each one.

const Rig: GDScript = preload("res://tests/sim/support/targeting_lockstep_rig.gd")
const Orders: GDScript = preload("res://tests/sim/support/targeting_orders.gd")
const Layers: GDScript = preload("res://tests/sim/support/layer_worlds.gd")
const STATES: int = 300
const FIELDS: int = 12
const FIELD_TICKS: int = 90
const ATTACK_MOVE: int = World.Order.ATTACK_MOVE
const ATTACK: int = World.Order.ATTACK
const IDLE: int = World.Order.IDLE
const DIRECT: int = World.NavMode.DIRECT
const HOLD: int = World.NavMode.HOLD
const CHASE: int = World.NavMode.CHASE
const NONE: int = World.NavMode.NONE
## The 300 states together, measured (held rows only): 1034 ATTACK rows that went IDLE, 209 due
## ATTACK_MOVE rows that took a target at weapon range, and 203 that had an enemy between weapon
## range and acquire range and did not take it.
const FLOOR_HELD_FALLBACKS: int = 690
const FLOOR_HELD_TAKEN: int = 139
const FLOOR_HELD_REFUSED: int = 135
## The 12 fields together, measured: 132 held ATTACK rows that went IDLE.
const FLOOR_RUN_HELD_IDLE: int = 88


func test_a_held_attack_mover_acquires_at_weapon_range_only() -> void:
	# The shipped roster: every weapon reaches 4000, every type acquires at 5000.
	for gap: int in [3500, 4000, 4500, 5000]:
		for stance: int in [0, 1]:
			var rig: RefCounted = Rig.new().setup(_mover.bind(gap, stance), Rig.ONLY)
			assert_array(rig.problems).is_empty()
			var label: String = "gap %d stance %d" % [gap, stance]
			assert_str(rig.once()).override_failure_message(label).is_empty()
			for world: World in rig.worlds:
				var in_range: bool = gap <= 4000
				var takes: bool = in_range or stance == 0
				assert_bool(world.target[0] != 0).override_failure_message(label).is_equal(takes)
				var want: int = HOLD if in_range else (CHASE if takes else DIRECT)
				assert_int(world.nav_mode[0]).override_failure_message(label).is_equal(want)


func test_a_held_attack_mover_never_chases_and_walks_on() -> void:
	var rig: RefCounted = Rig.new().setup(_mover.bind(4500, 1), Rig.ONLY)
	assert_array(rig.problems).is_empty()
	var start: int = rig.worlds[0].pos_x[0]
	for tick: int in 20:
		assert_str(rig.step()).override_failure_message("tick %d" % tick).is_empty()
		for world: World in rig.worlds:
			assert_int(world.nav_mode[0]).is_not_equal(CHASE)
			assert_int(world.order[0]).is_equal(ATTACK_MOVE)
	for world: World in rig.worlds:
		assert_int(world.pos_x[0]).is_greater(start)


func test_a_row_held_while_chasing_goes_back_to_its_path() -> void:
	var rig: RefCounted = Rig.new().setup(_chaser, Rig.ONLY)
	assert_array(rig.problems).is_empty()
	assert_str(rig.once()).is_empty()
	for world: World in rig.worlds:
		assert_int(world.nav_mode[0]).is_equal(DIRECT)


func test_a_held_attack_goes_idle_when_its_target_is_gone() -> void:
	for stance: int in [0, 1]:
		var rig: RefCounted = Rig.new().setup(_attacker.bind(stance), Rig.ONLY)
		assert_array(rig.problems).is_empty()
		assert_str(rig.once()).is_empty()
		for world: World in rig.worlds:
			var held: bool = stance == 1
			assert_int(world.order[0]).is_equal(IDLE if held else ATTACK_MOVE)
			assert_int(world.order_target[0]).is_equal(0)
			assert_int(world.nav_mode[0]).is_equal(NONE if held else DIRECT)
			if held:
				assert_array([world.goal_x[0], world.goal_y[0]]).is_equal(
					[world.pos_x[0], world.pos_y[0]]
				)


## Period 5 and tick 0: the row (id 1) is not due, so `run` keeps its target and `_engage` meets a
## target out of weapon range. The held row leaves CHASE, the unheld one stays in it.
func test_a_chaser_held_on_a_tick_it_is_not_due_goes_back_to_its_path() -> void:
	for stance: int in [0, 1]:
		var rig: RefCounted = Rig.new().setup(_late_chaser.bind(stance), Rig.ONLY)
		assert_array(rig.problems).is_empty()
		assert_str(rig.once()).is_empty()
		for world: World in rig.worlds:
			assert_int(world.target[0]).is_equal(2)
			assert_int(world.nav_mode[0]).is_equal(DIRECT if stance == 1 else CHASE)


## The same on 20 ticks of the full step: no CHASE appears in the held row, and the two agree.
func test_a_held_row_with_a_slow_retarget_never_chases_in_a_run() -> void:
	var rig: RefCounted = Rig.new().setup(_late_chaser.bind(1), Rig.ONLY)
	assert_array(rig.problems).is_empty()
	for tick: int in 20:
		assert_str(rig.step()).override_failure_message("tick %d" % tick).is_empty()
		assert_int(rig.worlds[1].nav_mode[0]).is_not_equal(CHASE)


func test_a_held_attack_whose_target_is_out_of_sight_goes_idle() -> void:
	for stance: int in [0, 1]:
		var rig: RefCounted = Rig.new().setup(_unseen.bind(stance), Rig.ONLY)
		assert_array(rig.problems).is_empty()
		assert_str(rig.once()).is_empty()
		for world: World in rig.worlds:
			assert_int(world.order[0]).is_equal(IDLE if stance == 1 else ATTACK_MOVE)


func test_an_idle_duel_plays_the_same_with_either_stance() -> void:
	var worlds: Array[World] = []
	for stance: int in [0, 1]:
		var rig: RefCounted = Rig.new().setup(_idle_duel.bind(stance), Rig.ONLY)
		assert_array(rig.problems).is_empty()
		assert_str(rig.run(30)).is_empty()
		worlds.append(rig.worlds[1])
	for column: StringName in [&"pos_x", &"pos_y", &"hp", &"target", &"order", &"nav_mode"]:
		assert_array(Array(worlds[0].get(column))).override_failure_message(column).is_equal(
			Array(worlds[1].get(column))
		)


func test_states_with_random_stances_match_after_one_phase() -> void:
	var held_fallbacks: int = 0
	var taken: int = 0
	var refused: int = 0
	for salt: int in STATES:
		var rig: RefCounted = Rig.new().setup(_field.bind(3000 + salt, 60), Rig.ONLY)
		assert_array(rig.problems).is_empty()
		var before: World = _field(3000 + salt, 60)
		assert_str(rig.once()).override_failure_message("state %d" % salt).is_empty()
		var after: World = rig.worlds[0]
		for row: int in before.unit_count():
			if before.stance[row] != 1:
				continue
			held_fallbacks += int(before.order[row] == ATTACK and after.order[row] == IDLE)
			if before.order[row] != ATTACK_MOVE or not _due(before, row):
				continue
			taken += int(after.target[row] != 0)
			refused += _in_acquire_only(before, after, row)
	assert_int(held_fallbacks).is_greater(FLOOR_HELD_FALLBACKS)
	assert_int(taken).is_greater(FLOOR_HELD_TAKEN)
	assert_int(refused).is_greater(FLOOR_HELD_REFUSED)


func test_fields_with_random_stances_match_under_random_waves() -> void:
	var held_idle: int = 0
	for salt: int in FIELDS:
		var rig: RefCounted = Rig.new().setup(_field.bind(4000 + salt, 90), Rig.ONLY)
		assert_array(rig.problems).is_empty()
		for tick: int in FIELD_TICKS:
			var world: World = rig.worlds[0]
			var was: Dictionary[int, int] = {}
			for row: int in world.unit_count():
				if world.stance[row] == 1 and world.order[row] == ATTACK:
					was[world.unit_id[row]] = 1
			var found: String = rig.step(Orders.random_waves.bind(salt, 4))
			assert_str(found).override_failure_message("field %d tick %d" % [salt, tick]).is_empty()
			world = rig.worlds[0]
			for row: int in world.unit_count():
				if world.stance[row] != 1:
					continue
				assert_int(world.nav_mode[row]).is_not_equal(CHASE)
				held_idle += int(was.has(world.unit_id[row]) and world.order[row] == IDLE)
	assert_int(held_idle).is_greater(FLOOR_RUN_HELD_IDLE)


## Whether `row` scans on this state's tick.
func _due(world: World, row: int) -> bool:
	return (world.tick + world.unit_id[row]) % maxi(world.retarget_period_ticks, 1) == 0


## 1 when the held attack-mover `row` has an enemy in its acquire range but beyond its weapon range
## (so an unheld row would see it) that it did not take as its target.
func _in_acquire_only(before: World, after: World, row: int) -> int:
	var type: int = before.type_index[row]
	var weapon: int = before.type_weapon[type]
	if weapon < 0 or weapon >= before.weapon_range.size():
		return 0
	var reach: int = before.weapon_range[weapon]
	var acquire: int = before.type_acquire[type]
	for other: int in before.unit_count():
		if before.owner[other] == before.owner[row] or before.owner[other] == 0:
			continue
		var dx: int = before.pos_x[other] - before.pos_x[row]
		var dy: int = before.pos_y[other] - before.pos_y[row]
		var d2: int = dx * dx + dy * dy
		if d2 > reach * reach and d2 <= acquire * acquire:
			return int(after.target[row] != before.unit_id[other])
	return 0


## A gun (owner 1, id 1) attack-moving east with an enemy gun `gap` milli east of it, both
## cadences at 1.
func _mover(gap: int, stance: int) -> World:
	var world: World = Layers.duel(Layers.GUN, Layers.GUN, gap)
	world.retarget_period_ticks = 1
	world.line_check_period_ticks = 1
	world.order[0] = ATTACK_MOVE
	world.nav_mode[0] = DIRECT
	world.goal_x[0] = 19000
	world.goal_y[0] = 6000
	world.stance[0] = stance
	return world


## A held row that holds the target it took while chasing, now at 4500 (out of weapon range).
func _chaser() -> World:
	var world: World = _mover(4500, 1)
	world.target[0] = 2
	world.nav_mode[0] = CHASE
	return world


## A gun with an ATTACK on a unit that does not exist (id 99), at some goal.
func _attacker(stance: int) -> World:
	var world: World = Layers.duel(Layers.GUN, Layers.GUN, 7000)
	world.retarget_period_ticks = 1
	world.order[0] = ATTACK
	world.order_target[0] = 99
	world.nav_mode[0] = DIRECT
	world.goal_x[0] = 9000
	world.goal_y[0] = 6000
	world.stance[0] = stance
	return world


## Layers.field with a random stance on about a third of the rows.
func _field(salt: int, count: int) -> World:
	var world: World = Layers.field(salt, count)
	var rng: DetRandom = DetRandom.create(salt, 298)
	for row: int in world.unit_count():
		world.stance[row] = 1 if rng.next_int(3) == 0 else 0
	return world


## `_chaser` with a retarget period of 5 at tick 0: id 1 is not due, and holds target 2 in CHASE.
func _late_chaser(stance: int) -> World:
	var world: World = _mover(4500, stance)
	world.retarget_period_ticks = 5
	world.target[0] = 2
	world.nav_mode[0] = CHASE
	return world


## An unrevealed world (nobody sees anybody) with an ATTACK on the enemy gun of id 2.
func _unseen(stance: int) -> World:
	var world: World = Layers.empty(false)
	world.add_unit(1, Layers.GUN, 4000, 6000)
	world.add_unit(2, Layers.GUN, 7000, 6000)
	world.retarget_period_ticks = 1
	world.order[0] = ATTACK
	world.order_target[0] = 2
	world.nav_mode[0] = DIRECT
	world.goal_x[0] = 7000
	world.goal_y[0] = 6000
	world.stance[0] = stance
	return world


## Two idle guns 3000 apart, both cadences at 1: they shoot each other, whatever the stance.
func _idle_duel(stance: int) -> World:
	var world: World = Layers.duel(Layers.GUN, Layers.GUN, 3000)
	world.retarget_period_ticks = 1
	world.stance[0] = stance
	world.stance[1] = stance
	return world
