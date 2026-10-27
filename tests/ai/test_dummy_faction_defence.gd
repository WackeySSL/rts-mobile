extends GdUnitTestSuite
## A scripted attacker against the dummy of each faction (plan row P83d, ADR 0020 sections 4 and 5,
## ADR 0023 section 6): P83b's `test_dummy_defence_match.gd` run once with the Derrick League's
## dummy as the defender and once with the Lumen Accord's. Player 1 is no AI but a test command,
## eight scouts of the other faction sent with one ATTACK_MOVE at the dummy's Headquarters on the
## faction start of `faction_rig.gd`; player 2 is the dummy on its faction's def, which has two
## rifle squads and builds as it goes. Every order the dummy sends is audited against the World as
## it stands when the dummy thinks: it ends in the attacker's victory, the dummy met the scouts
## with ATTACK_MOVE at them, no order sent a unit farther than `defend_radius_tiles` from a building
## of the dummy, and the sim dropped nothing.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const Factions: GDScript = preload("res://tests/ai/support/faction_rig.gd")
const Audit: GDScript = preload("res://tests/ai/support/defence_audit.gd")
## The attackers, and the most ticks the match may take (the attack ends it far sooner).
const SCOUTS: int = 8
const BOUND: int = 4500
## The ticks of the raid below.
const RAID_TICKS: int = 900
## The guard point of player 2 (the centre of its Headquarters at (27,500, 27,500) plus 2 tiles).
const GUARD: Vector2i = Vector2i(29500, 29500)

var _runs: Dictionary[String, Run] = {}


## What the match against one defender left: the World, the radius of its def, the target of the
## dummy's first order, and the count of its orders, of those at a row of the attacker and of those
## that went beyond the radius.
class Run:
	var world: World
	var radius: int = 0
	var first: Vector2i = Vector2i(-1, -1)
	var orders: int = 0
	var at_attackers: int = 0
	var beyond: int = 0


func before() -> void:
	for faction: String in Factions.FACTIONS:
		_runs[faction] = _match_against(faction)


func test_the_attacker_wins_the_match(faction: String, _test_parameters := _each()) -> void:
	var world: World = _runs[faction].world
	assert_int(world.match_end_tick).is_greater(0)
	assert_int(world.winner).is_equal(1)
	assert_int(world.defeated_tick[2]).is_greater(0)
	assert_int(world.defeated_tick[1]).is_equal(0)


func test_the_dummy_met_the_scouts_with_attack_move_at_them(
	faction: String, _test_parameters := _each()
) -> void:
	assert_int(_runs[faction].at_attackers).is_greater(0)


func test_before_the_attack_arrived_the_squads_were_at_the_guard_point(
	faction: String, _test_parameters := _each()
) -> void:
	assert_vector(_runs[faction].first).is_equal(GUARD)


func test_no_order_sent_a_unit_beyond_the_radius_of_a_building(
	faction: String, _test_parameters := _each()
) -> void:
	assert_int(_runs[faction].orders).is_greater(1)
	assert_int(_runs[faction].beyond).is_equal(0)


func test_the_sim_dropped_nothing_the_dummy_sent(
	faction: String, _test_parameters := _each()
) -> void:
	assert_int(_runs[faction].world.dropped_commands).is_equal(0)


func test_the_squads_return_to_the_guard_point_after_a_raid(
	faction: String, _test_parameters := _each()
) -> void:
	# One idle rifle squad of player 1 (of the other faction), 5 tiles west of the dummy's
	# Headquarters, inside the radius and its sight; the dummy's squads go and kill it, then go back
	# to the guard point.
	var attacker: String = Factions.other(faction)
	var world: World = Factions.start(attacker, faction)
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: DummyAi = Factions.dummy(faction, 2)
	var raider: int = Rig.add_unit_of(world, 1, Factions.RIFLE[attacker], 22500, 27500)
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
	var squads: String = Factions.RIFLE[faction]
	assert_int(Rig.count_of(world, 2, squads)).is_greater(0)
	for id: int in Rig.ids_of(world, 2, squads):
		var row: int = world.index_of(id)
		assert_int(world.order[row]).is_equal(World.Order.IDLE)
		var gap: Vector2i = Vector2i(world.pos_x[row], world.pos_y[row]) - GUARD
		assert_int(gap.x * gap.x + gap.y * gap.y).is_less_equal(2000 * 2000)


## gdUnit4's parameter sets: one case per defending faction (a method, since gdUnit4 writes into
## the sets).
func _each() -> Array[Array]:
	return [["fossil"], ["renew"]]


## The match of the scripted attacker against the dummy of `defender`, tick by tick as the headless
## loop does it, until the match ends or BOUND ticks have run.
@warning_ignore("integer_division")
func _match_against(defender: String) -> Run:
	var attacker: String = Factions.other(defender)
	var run: Run = Run.new()
	run.world = Factions.start(attacker, defender)
	run.radius = Factions.def_of(defender).defend_radius_tiles
	var loop: MatchLoop = Rig.loop_of(run.world)
	var ai: DummyAi = Factions.dummy(defender, 2)
	var scouts: PackedInt32Array = PackedInt32Array()
	for index: int in SCOUTS:
		scouts.append(
			Rig.add_unit_of(
				run.world,
				1,
				Factions.SCOUT[attacker],
				11500 + index % 4 * 1500,
				12500 + index / 4 * 1500
			)
		)
	Rig.step(run.world, loop, [Command.attack_move(1, scouts, 27500, 27500)])
	for _tick: int in BOUND:
		if run.world.match_end_tick > 0:
			break
		var sent: Array[Command] = []
		if (run.world.tick + ai.think_offset) % ai.think_period == 0:
			ai.think(PlayerView.of(run.world, 2), sent)
		_audit(run, sent)
		Rig.step(run.world, loop, sent)
	return run


## Counts the ATTACK_MOVE commands of `sent` (the dummy's, player 2) as the header says.
func _audit(run: Run, sent: Array[Command]) -> void:
	for command: Command in sent:
		if command.type != Command.Type.ATTACK_MOVE:
			continue
		if run.orders == 0:
			run.first = Vector2i(command.target_x, command.target_y)
		run.orders += 1
		if Audit.meets(run.world, command, 1):
			run.at_attackers += 1
		if not Audit.within(run.world, command, run.radius):
			run.beyond += 1
