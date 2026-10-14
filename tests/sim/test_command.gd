extends GdUnitTestSuite
## Command v1 (ADR 0007 section 5): the field defaults, the four factories and the
## (tick, player_id, sequence) ordering that Sim.step sorts by, and encode and decode for the
## replay log (P35a, ADR 0007 section 5; the round trips are in test_replay).

const Samples: GDScript = preload("res://tests/sim/support/command_samples.gd")


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


## The layout and the limits are literals, so an encoder cannot agree with its own decoder by
## being wrong. `ints` below are tick, player_id, sequence, type, target_x, target_y, target_id,
## the unit count, the ids, the payload count and the payload.
func test_encode_appends_the_adr_layout_after_what_is_in_out() -> void:
	assert_array([Command.ENCODED_HEADER, Command.ENCODED_MIN]).is_equal([7, 9])
	var out: PackedInt32Array = PackedInt32Array([99])
	Samples.full(Command.Type.ATTACK, 40, 6).encode(out)
	assert_array(out).is_equal([99, 40, 2, 6, 3, 12500, -700, 31, 3, 5, 9, 40, 2, 7, -8])
	var empty: PackedInt32Array = PackedInt32Array()
	Command.new().encode(empty)
	assert_array(empty).is_equal([-1, 0, 0, 0, 0, 0, 0, 0, 0])


func test_decode_reads_at_the_offset_and_returns_the_next_one() -> void:
	var data: PackedInt32Array = PackedInt32Array([-5, -6])
	var first: Command = Samples.full(Command.Type.MOVE, 1, 1)
	first.encode(data)
	var second_at: int = data.size()
	var second: Command = Command.attack(1, PackedInt32Array([8]), 3)
	second.tick = 2
	second.encode(data)
	data.append(77)  # An int after the last command that belongs to no command.
	var out: Command = Command.new()
	assert_int(Command.decode(data, 2, out)).is_equal(second_at)
	assert_array(Samples.fields(out)).is_equal(Samples.fields(first))
	# Reusing `out` replaces its arrays: a shorter record leaves nothing of the longer one.
	assert_int(Command.decode(data, second_at, out)).is_equal(data.size() - 1)
	assert_array(Samples.fields(out)).is_equal(Samples.fields(second))


func test_a_count_above_the_limits_is_malformed_even_when_the_data_is_there() -> void:
	assert_array([Command.MAX_UNITS, Command.MAX_PAYLOAD]).is_equal([256, 16])
	var at_limit: Command = Samples.full(Command.Type.MOVE, 4, 1)
	for k: int in 253:
		at_limit.unit_ids.append(k + 100)
	for k: int in 14:
		at_limit.payload.append(k)
	var data: PackedInt32Array = PackedInt32Array()
	at_limit.encode(data)
	var out: Command = Command.new()
	assert_int(Command.decode(data, 0, out)).is_equal(data.size())
	assert_array([out.unit_ids.size(), out.payload.size()]).is_equal([256, 16])
	# One more id, or one more payload int, is refused although every int is in the buffer.
	for extra: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var longer: Command = Samples.full(Command.Type.MOVE, 4, 1)
		longer.unit_ids = at_limit.unit_ids.duplicate()
		longer.payload = at_limit.payload.duplicate()
		if extra.x > 0:
			longer.unit_ids.append(999)
		if extra.y > 0:
			longer.payload.append(999)
		var over: PackedInt32Array = PackedInt32Array()
		longer.encode(over)
		assert_int(over.size()).is_equal(data.size() + extra.x + extra.y)
		assert_int(Command.decode(over, 0, Command.new())).is_equal(-1)


func test_an_offset_outside_the_data_or_a_record_cut_short_is_malformed() -> void:
	var data: PackedInt32Array = PackedInt32Array()
	Command.new().encode(data)
	var out: Command = Command.new()
	assert_int(Command.decode(data, 0, out)).is_equal(9)
	# One int in, the end, past the end, below zero and far out of range: no read, no overflow.
	for at: int in [1, 8, 9, 10, 1000, -1, -2147483648, 1 << 62, 9223372036854775807]:
		assert_int(Command.decode(data, at, out)).override_failure_message(str(at)).is_equal(-1)
	assert_int(Command.decode(PackedInt32Array(), 0, out)).is_equal(-1)
	assert_int(Command.decode(data, 0, null)).is_equal(-1)
	# Every prefix of a command that has ids and a payload is malformed.
	var full: PackedInt32Array = PackedInt32Array()
	Samples.full(Command.Type.ATTACK, 9, 2).encode(full)
	assert_int(Command.decode(full, 0, out)).is_equal(full.size())
	var accepted: Array[int] = []
	for length: int in full.size():
		if Command.decode(full.slice(0, length), 0, out) != -1:
			accepted.append(length)
	assert_array(accepted).is_empty()


func test_decode_leaves_out_alone_when_it_returns_minus_one() -> void:
	var out: Command = Samples.full(Command.Type.STOP, 3, 4)
	assert_int(Samples.decode([1, 0, 0, 3, 0, 0, 0, 3, 5, 9], out)).is_equal(-1)
	assert_int(Samples.decode([1, 0, 0, 3, 0, 0, 0, 0, -1], out)).is_equal(-1)
	assert_int(Samples.decode([1, 0, 0, 3, 0, 0, 0, 0, 5, 1], out)).is_equal(-1)
	assert_array(Samples.fields(out)).is_equal(
		Samples.fields(Samples.full(Command.Type.STOP, 3, 4))
	)


func test_decode_and_encode_share_no_array_with_the_other_side() -> void:
	var data: PackedInt32Array = PackedInt32Array()
	Samples.full(Command.Type.ATTACK, 5, 1).encode(data)
	var a: Command = Command.new()
	var b: Command = Command.new()
	Command.decode(data, 0, a)
	Command.decode(data, 0, b)
	# The ids start at 8 and the payload at 12, after its count.
	data[8] = 999
	data[12] = 888
	assert_array(a.unit_ids).is_equal([5, 9, 40])
	assert_array(a.payload).is_equal([7, -8])
	a.unit_ids[1] = 111
	a.payload.append(1)
	assert_array(b.unit_ids).is_equal([5, 9, 40])
	assert_array(b.payload).is_equal([7, -8])
	assert_array(data.slice(8, 11)).is_equal([999, 9, 40])
	# encode copies the ids and the payload too.
	var command: Command = Samples.full(Command.Type.MOVE, 5, 1)
	var out: PackedInt32Array = PackedInt32Array()
	command.encode(out)
	command.unit_ids[0] = 1
	command.payload[0] = 2
	out.append(5)
	assert_array(out.slice(8, 11)).is_equal([5, 9, 40])
	assert_int(out[12]).is_equal(7)
	assert_array(command.unit_ids).is_equal([1, 9, 40])


## The bound: tick and sequence are -1 or in 0..2147483647 (a tick beyond it is 4.5 years of play
## at 15 Hz), and every int a PackedInt32Array takes fits int32 (ADR 0007 section 1). A wider
## value saturates, so it never wraps to the other sign.
func test_encode_writes_int32_values_and_saturates_the_wider_ones() -> void:
	assert_array([Command.INT32_MIN, Command.INT32_MAX]).is_equal([-2147483648, 2147483647])
	var edge: Command = Samples.full(Command.Type.MOVE, 2147483647, 2147483647)
	edge.target_x = -2147483648
	edge.target_y = 2147483647
	var data: PackedInt32Array = PackedInt32Array()
	edge.encode(data)
	var out: Command = Command.new()
	assert_int(Command.decode(data, 0, out)).is_equal(data.size())
	assert_array(Samples.fields(out)).is_equal(Samples.fields(edge))
	var wide: Command = Samples.full((1 << 31) + 3, 2147483648, 1 << 40)
	wide.player_id = -(1 << 40)
	wide.target_x = 1 << 62
	wide.target_y = -(1 << 62)
	wide.target_id = (1 << 32) + 5  # Stored as int32 it would wrap to 5.
	var wide_data: PackedInt32Array = PackedInt32Array()
	wide.encode(wide_data)
	# tick, player_id, sequence, type, target_x, target_y, target_id.
	var most: int = 2147483647
	assert_array(wide_data.slice(0, 7)).is_equal(
		[most, -most - 1, most, most, most, -most - 1, most]
	)


func _stamped(tick: int, player_id: int, sequence: int) -> Command:
	var command: Command = Command.new()
	command.tick = tick
	command.player_id = player_id
	command.sequence = sequence
	return command


func _assert_before(first: Command, second: Command) -> void:
	assert_bool(Command.compare(first, second)).is_true()
	assert_bool(Command.compare(second, first)).is_false()
