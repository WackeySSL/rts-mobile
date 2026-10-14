extends GdUnitTestSuite
## Command v1 (ADR 0007 section 5): the field defaults, the four factories and the
## (tick, player_id, sequence) ordering that Sim.step sorts by.


func test_a_new_command_has_the_contract_defaults() -> void:
	var c: Command = Command.new()
	assert_array([c.tick, c.player_id, c.sequence, c.type]).is_equal([-1, 0, 0, 0])
	assert_array([c.target_x, c.target_y, c.target_id]).is_equal([0, 0, 0])
	assert_array(c.unit_ids).is_empty()
	assert_array([Command.Type.NONE, Command.Type.ATTACK_MOVE]).is_equal([0, 1])


func test_attack_move_sets_the_order_and_copies_the_unit_ids() -> void:
	var ids: PackedInt32Array = PackedInt32Array([31, 33])
	var c: Command = Command.attack_move(2, ids, 12500, -700)
	ids[0] = 99
	assert_array(c.unit_ids).is_equal([31, 33])
	assert_array([c.type, c.player_id, c.target_x, c.target_y]).is_equal([1, 2, 12500, -700])
	# The runner stamps these.
	assert_array([c.tick, c.sequence, c.target_id]).is_equal([-1, 0, 0])


func test_v1_types_limits_and_factories() -> void:
	var types: Array[int] = [Command.Type.NONE, Command.Type.ATTACK_MOVE, Command.Type.MOVE]
	types.append_array([Command.Type.ATTACK, Command.Type.STOP])
	assert_array(types).is_equal([0, 1, 2, 3, 4])
	assert_array([Command.MAX_UNITS, Command.MAX_PAYLOAD]).is_equal([256, 16])
	assert_array(Command.new().payload).is_empty()
	# Each factory sets its type, player and fields, and leaves the rest and the stamps alone.
	var ids: PackedInt32Array = PackedInt32Array([5, 6])
	var move: Command = Command.move(2, ids, 800, 41000)
	assert_array([move.type, move.player_id, move.target_x, move.target_y]).is_equal(
		[2, 2, 800, 41000]
	)
	var attack: Command = Command.attack(1, ids, 77)
	assert_array([attack.type, attack.player_id, attack.target_id]).is_equal([3, 1, 77])
	var stop: Command = Command.stop(2, ids)
	assert_array([stop.type, stop.player_id]).is_equal([4, 2])
	for c: Command in [move, attack, stop]:
		assert_array(c.unit_ids).is_equal([5, 6])
		assert_array([c.tick, c.sequence, c.payload.size()]).is_equal([-1, 0, 0])
	assert_array([move.target_id, attack.target_x, attack.target_y]).is_equal([0, 0, 0])
	assert_array([stop.target_id, stop.target_x, stop.target_y]).is_equal([0, 0, 0])


## A command changes hands once (ADR 0012 section 2): changing the caller's array after the call
## must not reach the command, for every factory (none takes a payload yet).
func test_every_factory_copies_the_unit_ids() -> void:
	var factories: Array[Callable] = [
		func(ids: PackedInt32Array) -> Command: return Command.attack_move(1, ids, 5, 6),
		func(ids: PackedInt32Array) -> Command: return Command.move(1, ids, 5, 6),
		func(ids: PackedInt32Array) -> Command: return Command.attack(1, ids, 7),
		func(ids: PackedInt32Array) -> Command: return Command.stop(1, ids),
	]
	for k: int in factories.size():
		var ids: PackedInt32Array = PackedInt32Array([31, 33])
		var c: Command = factories[k].call(ids)
		ids[0] = 99
		ids.append(100)
		assert_array(c.unit_ids).override_failure_message("factory %d" % k).is_equal([31, 33])


func test_compare_orders_by_tick_then_player_then_sequence() -> void:
	# Each earlier key beats a later one, even when every later field says the opposite.
	_assert_before(_stamped(1, 9, 9), _stamped(2, 0, 0))
	_assert_before(_stamped(5, 1, 9), _stamped(5, 2, 0))
	_assert_before(_stamped(5, 2, 3), _stamped(5, 2, 4))
	_assert_before(_stamped(-1, 0, 0), _stamped(0, 0, 0))
	assert_bool(Command.compare(_stamped(4, 1, 2), _stamped(4, 1, 2))).is_false()


func _stamped(tick: int, player_id: int, sequence: int) -> Command:
	var command: Command = Command.new()
	command.tick = tick
	command.player_id = player_id
	command.sequence = sequence
	return command


func _assert_before(first: Command, second: Command) -> void:
	assert_bool(Command.compare(first, second)).is_true()
	assert_bool(Command.compare(second, first)).is_false()
