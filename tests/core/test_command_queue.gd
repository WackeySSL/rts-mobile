extends GdUnitTestSuite
## The CommandQueue autoload API v0 (ADR 0003 section 7). Each test uses its own instance of the
## service script, so the autoload that the match runner drains is never touched.

const QueueScript: GDScript = preload("res://game/core/command_queue_service.gd")

var _queue: Node


func before_test() -> void:
	_queue = auto_free(QueueScript.new())


func test_drain_appends_in_submission_order_returns_the_count_and_empties_the_queue() -> void:
	var held: Command = _command(5)
	var first: Command = _command(12)
	var second: Command = _command(11)
	_queue.submit(first)
	_queue.submit(second)
	assert_int(_queue.pending()).is_equal(2)
	var out: Array[Command] = [held]
	assert_int(_queue.drain_into(out)).is_equal(2)
	assert_int(out.size()).is_equal(3)
	assert_object(out[0]).is_same(held)
	assert_object(out[1]).is_same(first)
	assert_object(out[2]).is_same(second)
	assert_int(_queue.pending()).is_equal(0)
	assert_int(_queue.drain_into(out)).is_equal(0)
	assert_int(out.size()).is_equal(3)


func test_clear_drops_everything_queued() -> void:
	_queue.submit(_command(1))
	_queue.submit(_command(2))
	_queue.clear()
	assert_int(_queue.pending()).is_equal(0)
	var out: Array[Command] = []
	assert_int(_queue.drain_into(out)).is_equal(0)


func test_submitting_null_is_ignored() -> void:
	_queue.submit(null)
	assert_int(_queue.pending()).is_equal(0)
	_queue.submit(_command(1))
	_queue.submit(null)
	assert_int(_queue.pending()).is_equal(1)


func _command(target_x: int) -> Command:
	return Command.attack_move(1, PackedInt32Array([1]), target_x, 0)


func test_submit_emits_submitted_once_per_command_after_queueing() -> void:
	var seen: Array[Command] = []
	var pending_at_emit: Array[int] = []
	_queue.submitted.connect(
		func(command: Command) -> void:
			seen.append(command)
			pending_at_emit.append(_queue.pending())
	)
	var first: Command = _command(1)
	var second: Command = _command(2)
	_queue.submit(first)
	_queue.submit(null)
	_queue.submit(second)
	assert_int(seen.size()).is_equal(2)
	assert_object(seen[0]).is_same(first)
	assert_object(seen[1]).is_same(second)
	assert_array(pending_at_emit).is_equal([1, 2])


func test_submit_logged_queues_the_same_command_and_emits_nothing() -> void:
	var emitted: Array[int] = [0]
	_queue.submitted.connect(func(_command: Command) -> void: emitted[0] += 1)
	var held: Command = _command(3)
	_queue.submit_logged(held)
	_queue.submit_logged(null)
	assert_int(emitted[0]).is_equal(0)
	assert_int(_queue.pending()).is_equal(1)
	var out: Array[Command] = []
	_queue.drain_into(out)
	assert_object(out[0]).is_same(held)


func test_submit_and_submit_logged_leave_identical_queue_state() -> void:
	var logged: Node = auto_free(QueueScript.new())
	for x: int in [7, 3, 9, 3]:
		_queue.submit(_command(x))
		logged.submit_logged(_command(x))
	assert_int(logged.pending()).is_equal(_queue.pending())
	var a: Array[Command] = []
	var b: Array[Command] = []
	_queue.drain_into(a)
	logged.drain_into(b)
	var encoded_a: PackedInt32Array = PackedInt32Array()
	var encoded_b: PackedInt32Array = PackedInt32Array()
	for i: int in a.size():
		a[i].encode(encoded_a)
		b[i].encode(encoded_b)
	assert_int(a.size()).is_equal(b.size())
	assert_array(encoded_a).is_equal(encoded_b)
