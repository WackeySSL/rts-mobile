extends GdUnitTestSuite
## AiDriver.think_all (plan row P82, ADR 0020 section 2): who thinks on a tick, in which order, on
## which view, where the Commands go, and that nothing thinks after the end of the match. The
## controllers are tests/core/support/recording_ai.gd on the rig's start of tests/ai (two players),
## with no step: the driver alone.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const RecordingAi: GDScript = preload("res://tests/core/support/recording_ai.gd")
## The fields of a journal record.
const LABEL: int = 0
const PLAYER: int = 1
const TICK: int = 2
const VIEW: int = 3
const OUT_SIZE: int = 4

var _journal: Array = []


func before_test() -> void:
	_journal = []


## Four controllers out of player order, one of them not due: the three due ones think once each,
## in ascending player order and, for the two of player 2, in list order. Each gets its own new
## view of its own player at the World's tick, and appends after what `out` held, so the human's
## command stays first.
func test_due_controllers_think_in_player_order_each_on_a_fresh_view_of_its_player() -> void:
	var world: World = Rig.start()
	world.tick = 30
	var controllers: Array[AiController] = [
		_recorder("b", 2, 15, 0), _recorder("a", 1, 15, 0), _recorder("c", 2, 1, 0)
	]
	controllers.append(_recorder("late", 1, 15, 1))
	var human: Command = Command.move(1, PackedInt32Array([2]), 10500, 4500)
	var out: Array[Command] = [human]
	AiDriver.think_all(world, controllers, out)
	var order: Array = _journal.map(func(record: Array) -> Array: return record.slice(0, 3))
	assert_array(order).is_equal([["a", 1, 30], ["b", 2, 30], ["c", 2, 30]])
	(
		assert_array(_journal.map(func(record: Array) -> int: return record[OUT_SIZE]))
		. is_equal([1, 2, 3])
	)
	var views: Array = _journal.map(func(record: Array) -> PlayerView: return record[VIEW])
	assert_bool(is_same(views[0], views[1]) or is_same(views[1], views[2])).is_false()
	assert_bool(is_same(views[0], views[2])).is_false()
	var senders: Array[int] = []
	for command: Command in out:
		senders.append(command.player_id)
	assert_array(senders).is_equal([1, 1, 2, 2])
	assert_bool(is_same(out[0], human)).is_true()
	assert_int(out[1].type).is_equal(Command.Type.STOP)
	# The driver changes neither the World nor the list of controllers.
	assert_array([world.tick, controllers.size(), world.dropped_commands]).is_equal([30, 4, 0])


## A controller thinks on the ticks with `(tick + think_offset) % think_period == 0`: period 15
## and offset 8 (the shipped dummy's player 2) at ticks 7, 22 and 37 of 0 to 44; period 1 on every
## tick; a period of 0 or below counts as 1, so it thinks on every tick and divides by nothing.
func test_a_controller_thinks_on_the_ticks_its_period_and_offset_give() -> void:
	var world: World = Rig.start()
	var controllers: Array[AiController] = [
		_recorder("dummy", 2, 15, 8),
		_recorder("every", 1, 1, 0),
		_recorder("zero", 1, 0, 3),
		_recorder("negative", 1, -4, 0),
	]
	var out: Array[Command] = []
	for tick: int in 45:
		world.tick = tick
		AiDriver.think_all(world, controllers, out)
	var ticks: Dictionary[String, Array] = {}
	for record: Array in _journal:
		ticks.get_or_add(record[LABEL], []).append(record[TICK])
	assert_array(ticks["dummy"]).is_equal([7, 22, 37])
	for label: String in ["every", "zero", "negative"]:
		assert_array(ticks[label]).override_failure_message(label).is_equal(range(45))
	assert_int(out.size()).is_equal(3 + 3 * 45)


## Once `match_end_tick` is above 0 nothing thinks and `out` keeps what it held; a null entry and an
## empty list are skipped.
func test_nothing_thinks_after_the_end_and_a_null_entry_is_skipped() -> void:
	var world: World = Rig.start()
	var controllers: Array[AiController] = [null, _recorder("a", 1, 1, 0)]
	var out: Array[Command] = [Command.surrender(2)]
	world.match_end_tick = 5
	world.winner = 1
	AiDriver.think_all(world, controllers, out)
	assert_array([_journal.size(), out.size()]).is_equal([0, 1])
	world.match_end_tick = 0
	AiDriver.think_all(world, controllers, out)
	var none: Array[AiController] = []
	AiDriver.think_all(world, none, out)
	assert_array([_journal.size(), out.size()]).is_equal([1, 2])
	assert_array(_journal[0].slice(0, 3)).is_equal(["a", 1, 0])


## A recording controller of `player` with `label`, `period` and `offset`, on the case's journal.
func _recorder(label: String, player: int, period: int, offset: int) -> AiController:
	var controller: AiController = RecordingAi.new()
	controller.player_id = player
	controller.think_period = period
	controller.think_offset = offset
	controller.set(&"label", label)
	controller.set(&"journal", _journal)
	return controller
