extends GdUnitTestSuite
## Command v0 (ADR 0003 section 2): the field defaults, the attack_move factory and the
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
