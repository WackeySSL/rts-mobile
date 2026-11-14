extends GdUnitTestSuite
## The TARGETING kernel against its GDScript twin with hold position (plan row P298, ADR 0037
## section 15; ADR 0013 section 4), compared like test_targeting_lockstep.gd
## (targeting_lockstep_rig.gd).
## - Crafted pairs, one TARGETING phase each: a held attack-mover takes a target at weapon range
##   (HOLD) but not at acquire range, and never takes CHASE; an unheld one does both; a held ATTACK
##   whose target is gone goes IDLE where it stands (an unheld one attack-moves on); a held row that
##   was chasing goes back to its path.
## - 300 seeded states with a random stance per row, one phase each, and 12 fields stepped 90 ticks
##   under random waves: the twin and the kernel end in the same state after every tick.
## The floors are measured on the twin and set at about two thirds of the figure.

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
## The 300 states together, measured: FLOOR_FALLBACKS of the held kind.
const FLOOR_HELD_FALLBACKS: int = 1
const FLOOR_RUN_SCANS: int = 1


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
	assert_str(rig.run(20)).is_empty()
	for world: World in rig.worlds:
		assert_int(world.nav_mode[0]).is_not_equal(CHASE)
		assert_int(world.order[0]).is_equal(ATTACK_MOVE)


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


func test_states_with_random_stances_match_after_one_phase() -> void:
	var held_fallbacks: int = 0
	for salt: int in STATES:
		var rig: RefCounted = Rig.new().setup(_field.bind(3000 + salt, 60), Rig.ONLY)
		assert_array(rig.problems).is_empty()
		var before: World = _field(3000 + salt, 60)
		assert_str(rig.once()).override_failure_message("state %d" % salt).is_empty()
		for row: int in before.unit_count():
			held_fallbacks += int(
				(
					before.order[row] == ATTACK
					and before.stance[row] == 1
					and rig.worlds[0].order[row] == IDLE
				)
			)
	assert_int(held_fallbacks).is_greater(FLOOR_HELD_FALLBACKS)


func test_fields_with_random_stances_match_under_random_waves() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for salt: int in FIELDS:
		var rig: RefCounted = Rig.new().setup(_field.bind(4000 + salt, 90), Rig.ONLY)
		assert_array(rig.problems).is_empty()
		var found: String = rig.run(FIELD_TICKS, Orders.random_waves.bind(salt, 4))
		assert_str(found).override_failure_message("field %d" % salt).is_empty()
		Rig.add_to(total, rig.tally())
	assert_int(total[&"scans"]).is_greater(FLOOR_RUN_SCANS)


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
