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
