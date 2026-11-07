extends GdUnitTestSuite
## `AiArmy` in running matches (plan row P179, ADR 0030 sections 4 and 6): P83b's scripted attacker
## and raid against a Normal opponent (the dummy's cases, `test_dummy_defence_match.gd`), and a
## 2,700-tick match of two opponents that counts the goal keys, the dropped Commands and the work.

const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const FactionRig: GDScript = preload("res://tests/ai/support/faction_rig.gd")
const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const Audit: GDScript = preload("res://tests/ai/support/defence_audit.gd")
const TANKS: int = 8
const BOUND: int = 4500
const RAID_TICKS: int = 900
const MATCH_TICKS: int = 2700

var _world: World = null
var _radius: int = 0
var _first_unit_order: Vector2i = Vector2i(-1, -1)
var _orders: int = 0
var _at_attackers: int = 0
var _beyond: int = 0


func before() -> void:
	_world = FactionRig.start("fossil", "fossil")
	_radius = Rig.def_of("fossil").defend_radius_tiles
	var loop: MatchLoop = AiRig.loop_of(_world)
	var ai: OpponentAi = Rig.opponent("fossil", "normal", 2)
	var tanks: PackedInt32Array = PackedInt32Array()
	for index: int in TANKS:
		tanks.append(
			AiRig.add_unit_of(
				_world, 1, "light_tank", 11500 + index % 4 * 1500, 12500 + index / 4 * 1500
			)
		)
	AiRig.step(_world, loop, [Command.attack_move(1, tanks, 27500, 27500)])
	for _tick: int in BOUND:
		if _world.match_end_tick > 0:
			break
		var sent: Array[Command] = []
		if (_world.tick + ai.think_offset) % ai.think_period == 0:
			ai.think(PlayerView.of(_world, 2), sent)
		_audit(sent)
		AiRig.step(_world, loop, sent)


func test_the_attacker_still_wins_the_match() -> void:
	assert_int(_world.match_end_tick).is_greater(0)
	assert_int(_world.winner).is_equal(1)
	assert_int(_world.defeated_tick[2]).is_greater(0)


func test_the_opponent_met_the_tanks_with_attack_move_at_them() -> void:
	assert_int(_at_attackers).is_greater(0)


func test_no_unit_order_went_beyond_the_radius_of_a_building_and_the_first_went_to_staging(
) -> void:
	assert_int(_orders).is_greater(0)
	assert_int(_beyond).is_equal(0)
	# Player 2's Headquarters is on tile (27, 27); its staging point lies 4 tiles toward the mirror
	# point (12, 12) along each axis, tile (23, 23), when the first order goes out.
	assert_vector(_first_unit_order).is_equal(Vector2i(23500, 23500))


func test_the_sim_dropped_nothing_the_opponent_sent() -> void:
	assert_int(_world.dropped_commands).is_equal(0)


func test_the_squads_go_back_to_the_staging_point_after_a_raid() -> void:
	# One idle rifle squad of player 1, 5 tiles west of player 2's Headquarters, inside the radius
	# and its sight: the squads kill it and go back to the staging point, and stand idle there.
	var world: World = FactionRig.start("fossil", "fossil")
	var loop: MatchLoop = AiRig.loop_of(world)
	var ai: OpponentAi = Rig.opponent("fossil", "normal", 2)
	var raider: int = AiRig.add_unit_of(world, 1, "rifle_squad", 22500, 27500)
	var attack_moves: Array[Vector2i] = []
	var moves: Array[Vector2i] = []
	for _tick: int in RAID_TICKS:
		for command: Command in AiRig.tick(world, loop, [ai]):
			if command.type == Command.Type.ATTACK_MOVE:
				attack_moves.append(Vector2i(command.target_x, command.target_y))
			elif command.type == Command.Type.MOVE:
				moves.append(Vector2i(command.target_x, command.target_y))
	assert_int(world.dropped_commands).is_equal(0)
	assert_int(world.index_of(raider)).is_less(0)
	# Sent at the raider once, and back to the staging point once (after it died).
	assert_array(attack_moves).is_equal([Vector2i(22500, 27500)])
	assert_array(moves).is_equal([Vector2i(23500, 23500)])
	assert_int(AiRig.count_of(world, 2, "rifle_squad")).is_greater(0)
	for id: int in AiRig.ids_of(world, 2, "rifle_squad"):
		var row: int = world.index_of(id)
		assert_int(world.order[row]).is_equal(World.Order.IDLE)
		var gap: Vector2i = Vector2i(world.pos_x[row], world.pos_y[row]) - Vector2i(23500, 23500)
		assert_int(gap.x * gap.x + gap.y * gap.y).is_less_equal(2000 * 2000)


func test_two_opponents_keep_the_goal_keys_work_and_orders_in_bounds_over_a_match() -> void:
	var world: World = FactionRig.start("fossil", "renew")
	var loop: MatchLoop = AiRig.loop_of(world)
	var ais: Array = [Rig.opponent("fossil", "normal", 1), Rig.opponent("renew", "hard", 2)]
	var most_keys: int = 0
	var army_orders: int = 0
	for _tick: int in MATCH_TICKS:
		var sent: Array[Command] = AiRig.tick(world, loop, ais)
		for command: Command in sent:
			if command.type == Command.Type.RALLY or command.type == Command.Type.ATTACK_MOVE:
				army_orders += 1
			if command.unit_ids.is_empty():
				continue
			# Unit orders go to own units only.
			for id: int in command.unit_ids:
				var row: int = world.index_of(id)
				if row >= 0:
					assert_int(world.owner[row]).is_equal(command.player_id)
		for ai: OpponentAi in ais:
			most_keys = maxi(most_keys, ai.memory.goal_keys())
			assert_int(ai.memory.goal_keys()).is_less_equal(ai.memory.goal_keys_max)
			assert_int(ai.memory.goal_keys_of(AiMemory.Owner.ARMY)).is_less_equal(2)
			assert_int(ai.memory.goal_keys_of(AiMemory.Owner.STAGING)).is_less_equal(2)
	assert_int(world.dropped_commands).is_equal(0)
	assert_int(most_keys).is_greater(0)
	assert_int(army_orders).is_greater(0)
	for ai: OpponentAi in ais:
		assert_int(ai.work_max).is_less_equal(3)
		assert_int(ai.commands_cut).is_equal(0)
		assert_int(ai.army.passes).is_equal(0)
		assert_bool(ai.memory.has_staging()).is_true()


## Counts the unit orders of `sent` (the opponent's, player 2) as the header says.
func _audit(sent: Array[Command]) -> void:
	for command: Command in sent:
		if command.type != Command.Type.ATTACK_MOVE and command.type != Command.Type.MOVE:
			continue
		if _orders == 0:
			_first_unit_order = Vector2i(command.target_x, command.target_y)
		_orders += 1
		if command.type == Command.Type.ATTACK_MOVE and Audit.meets(_world, command, 1):
			_at_attackers += 1
		if not Audit.within(_world, command, _radius):
			_beyond += 1
