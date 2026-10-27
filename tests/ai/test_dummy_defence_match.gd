extends GdUnitTestSuite
## A scripted attacker against the dummy (plan row P83b, ADR 0020 section 5): player 1 is no AI but
## a test command, eight light tanks sent with one ATTACK_MOVE at the dummy's Headquarters on the
## skirmish-like start of `ai_rig.gd`; player 2 is the dummy on the shipped def, which has two rifle
## squads and builds as it goes. The match is run once for the suite, tick by tick as the headless
## loop does it, and every order the dummy sends is audited against the World as it stands when the
## dummy thinks: it ends in the attacker's victory, the dummy met the tanks with ATTACK_MOVE at
## them, no order sent a unit farther than `defend_radius_tiles` from a building of the dummy, and
## the sim dropped nothing.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const Audit: GDScript = preload("res://tests/ai/support/defence_audit.gd")
## The attackers, and the most ticks the match may take (the attack ends it far sooner).
const TANKS: int = 8
const BOUND: int = 4500
## The ticks of the raid below.
const RAID_TICKS: int = 900
## The guard point of player 2 (the centre of its Headquarters at (27,500, 27,500) plus 2 tiles).
const GUARD: Vector2i = Vector2i(29500, 29500)

var _world: World
var _radius: int = 0
## The target of the dummy's first order, and the count of its orders, of those at a row of the
## attacker and of those that went beyond the radius.
var _first: Vector2i = Vector2i(-1, -1)
var _orders: int = 0
var _at_attackers: int = 0
var _beyond: int = 0


func before() -> void:
	_world = Rig.start()
	_radius = Rig.dummy_def().defend_radius_tiles
	var loop: MatchLoop = Rig.loop_of(_world)
	var ai: DummyAi = Rig.dummy(2)
	var tanks: PackedInt32Array = PackedInt32Array()
	for index: int in TANKS:
		tanks.append(
			Rig.add_unit_of(
				_world, 1, "light_tank", 11500 + index % 4 * 1500, 12500 + index / 4 * 1500
			)
		)
	Rig.step(_world, loop, [Command.attack_move(1, tanks, 27500, 27500)])
	for _tick: int in BOUND:
		if _world.match_end_tick > 0:
			break
		var sent: Array[Command] = []
		if (_world.tick + ai.think_offset) % ai.think_period == 0:
			ai.think(PlayerView.of(_world, 2), sent)
		_audit(sent)
		Rig.step(_world, loop, sent)


func test_the_attacker_wins_the_match() -> void:
	assert_int(_world.match_end_tick).is_greater(0)
	assert_int(_world.winner).is_equal(1)
	assert_int(_world.defeated_tick[2]).is_greater(0)
	assert_int(_world.defeated_tick[1]).is_equal(0)


func test_the_dummy_met_the_tanks_with_attack_move_at_them() -> void:
	assert_int(_at_attackers).is_greater(0)


func test_before_the_attack_arrived_the_squads_were_at_the_guard_point() -> void:
	assert_vector(_first).is_equal(GUARD)


func test_no_order_sent_a_unit_beyond_the_radius_of_a_building() -> void:
	assert_int(_orders).is_greater(1)
	assert_int(_beyond).is_equal(0)


func test_the_sim_dropped_nothing_the_dummy_sent() -> void:
	assert_int(_world.dropped_commands).is_equal(0)


func test_the_squads_return_to_the_guard_point_after_a_raid() -> void:
	# One idle rifle squad of player 1, 5 tiles west of the dummy's Headquarters, inside the radius
	# and its sight; the dummy's squads go and kill it, then go back to the guard point.
	var world: World = Rig.start()
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: DummyAi = Rig.dummy(2)
	var raider: int = Rig.add_unit_of(world, 1, "rifle_squad", 22500, 27500)
	var targets: Array[Vector2i] = []
	for _tick: int in RAID_TICKS:
		for command: Command in Rig.tick(world, loop, [ai]):
			if command.type == Command.Type.ATTACK_MOVE:
				targets.append(Vector2i(command.target_x, command.target_y))
	assert_int(world.dropped_commands).is_equal(0)
	# The raider is dead, the squads were sent at it once (it was seen at the first think) and back
	# once; they are idle at the guard point, within two tiles of it.
	assert_int(world.index_of(raider)).is_less(0)
	assert_array(targets).is_equal([Vector2i(22500, 27500), GUARD])
	assert_int(Rig.count_of(world, 2, "rifle_squad")).is_greater(0)
	for id: int in Rig.ids_of(world, 2, "rifle_squad"):
		var row: int = world.index_of(id)
		assert_int(world.order[row]).is_equal(World.Order.IDLE)
		var gap: Vector2i = Vector2i(world.pos_x[row], world.pos_y[row]) - GUARD
		assert_int(gap.x * gap.x + gap.y * gap.y).is_less_equal(2000 * 2000)


## Counts the ATTACK_MOVE commands of `sent` (the dummy's, player 2) as the header says.
func _audit(sent: Array[Command]) -> void:
	for command: Command in sent:
		if command.type != Command.Type.ATTACK_MOVE:
			continue
		if _orders == 0:
			_first = Vector2i(command.target_x, command.target_y)
		_orders += 1
		if Audit.meets(_world, command, 1):
			_at_attackers += 1
		if not Audit.within(_world, command, _radius):
			_beyond += 1
