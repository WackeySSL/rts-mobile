extends GdUnitTestSuite
## MatchLoop (plan P35b, ADR 0007 section 9, ADR 0012 section 2): the one tick driver. Stamping
## order, the replay log, the checkpoints every 15 ticks, the hand-over of the caller's commands,
## and a tick without commands. Literal numbers: the arena is player 1 = ids 1-75, player 2 = ids
## 76-150, with one scenario order for each at tick 0, and controls_test is player 1 = ids 1-30,
## player 2 = ids 31-40.

const Samples: GDScript = preload("res://tests/sim/support/command_samples.gd")
const RecordingProbe: GDScript = preload("res://tests/sim/recording_probe.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
const PACKED_KINDS: Array[int] = [
	TYPE_PACKED_BYTE_ARRAY,
	TYPE_PACKED_INT32_ARRAY,
	TYPE_PACKED_INT64_ARRAY,
	TYPE_PACKED_STRING_ARRAY,
	TYPE_ARRAY,
]


func test_create_records_the_header_and_starts_empty() -> void:
	var scenario: ScenarioDef = load(SCENARIO_PATH) as ScenarioDef
	var world: World = _world(scenario, 5)
	var loop: MatchLoop = MatchLoop.create(scenario, SCENARIO_PATH, 5_000_000_000, world)
	assert_str(loop.replay.scenario_path).is_equal(SCENARIO_PATH)
	assert_array([loop.replay.seed, loop.replay.defs_hash]).is_equal(
		[5_000_000_000, world.defs_hash()]
	)
	assert_array([loop.last_hash, loop.next_sequence, world.tick]).is_equal([0, 0, 0])
	assert_array(loop.replay.commands).is_empty()
	assert_array(loop.replay.checkpoint_ticks).is_empty()
	assert_array(loop.replay.checkpoint_hashes).is_empty()
	assert_array([loop.replay.final_tick, loop.replay.final_hash]).is_equal([0, 0])


## The scenario's orders (stamped 0 and 1) go first, then the queued commands in the order they
## were submitted (2 and 3), also when Sim.step sorts them the other way: the log keeps the
## stamping order. Their effect shows the stamping too: player 1 attack-moves everyone (0), then
## stops unit 1 (3), and player 2 attack-moves everyone (1), then moves unit 76 (2).
func test_scenario_orders_are_stamped_before_queued_commands_and_come_first_in_the_replay() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = _world(scenario, 3)
	var loop: MatchLoop = MatchLoop.create(scenario, ARENA_PATH, 3, world)
	var move: Command = Command.move(2, PackedInt32Array([76]), 50500, 10500)
	var stop: Command = Command.stop(1, PackedInt32Array([1]))
	var queued: Array[Command] = [move, stop]
	loop.step(world, queued)
	var logged: Array[Command] = _log(loop.replay)
	assert_int(logged.size()).is_equal(4)
	var seen: Array = []
	for command: Command in logged:
		seen.append([command.tick, command.sequence, command.player_id, command.type])
		seen.append(command.unit_ids.size())
	(
		assert_array(seen)
		. is_equal(
			[
				[0, 0, 1, Command.Type.ATTACK_MOVE],
				75,
				[0, 1, 2, Command.Type.ATTACK_MOVE],
				75,
				[0, 2, 2, Command.Type.MOVE],
				1,
				[0, 3, 1, Command.Type.STOP],
				1,
			]
		)
	)
	assert_array([move.sequence, stop.sequence, loop.next_sequence]).is_equal([2, 3, 4])
	assert_int(world.dropped_commands).is_equal(0)
	assert_array([world.order[0], world.order[1]]).is_equal(
		[World.Order.IDLE, World.Order.ATTACK_MOVE]
	)
	assert_array([world.order[75], world.order[76]]).is_equal(
		[World.Order.MOVE, World.Order.ATTACK_MOVE]
	)


## A null scenario yields no scenario orders: the same arena stays where it is.
func test_a_null_scenario_gives_no_scenario_orders() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = _world(scenario, 3)
	var loop: MatchLoop = MatchLoop.create(null, ARENA_PATH, 3, world)
	var none: Array[Command] = []
	for _tick: int in 3:
		loop.step(world, none)
	assert_array(loop.replay.commands).is_empty()
	assert_int(loop.next_sequence).is_equal(0)
	assert_int(world.order.count(World.Order.IDLE)).is_equal(150)
	# With the scenario, the same world is given its two orders at tick 0.
	var ordered: World = _world(scenario, 3)
	var with_orders: MatchLoop = MatchLoop.create(scenario, ARENA_PATH, 3, ordered)
	with_orders.step(ordered, none)
	assert_int(ordered.order.count(World.Order.ATTACK_MOVE)).is_equal(150)
	assert_int(with_orders.next_sequence).is_equal(2)


## An order of the scenario at a later tick comes out at that tick and takes the next sequence.
func test_a_scenario_order_at_a_later_tick_is_stamped_then() -> void:
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(20, 20)
	var unit: UnitDef = UnitDef.new()
	unit.type_id = &"walker"
	unit.speed = 100
	var block: SpawnDef = SpawnDef.new()
	block.owner = 1
	block.unit = unit
	block.count = 2
	scenario.spawns.append(block)
	var order: OrderDef = OrderDef.new()
	order.tick = 4
	order.player = 1
	order.target_tile = Vector2i(9, 9)
	scenario.orders.append(order)
	var world: World = World.from_scenario(scenario)
	var loop: MatchLoop = MatchLoop.create(scenario, "x", 1, world)
	var none: Array[Command] = []
	for _tick: int in 4:
		loop.step(world, none)
	assert_array(loop.replay.commands).is_empty()
	loop.step(world, none)
	var logged: Array[Command] = _log(loop.replay)
	assert_int(logged.size()).is_equal(1)
	assert_array(Samples.fields(logged[0])).is_equal(
		[4, 1, 0, Command.Type.ATTACK_MOVE, 9500, 9500, 0, [1, 2], []]
	)
	assert_int(world.dropped_commands).is_equal(0)


func test_sequences_are_unique_and_increase_over_the_match() -> void:
	var scenario: ScenarioDef = load(SCENARIO_PATH) as ScenarioDef
	var world: World = _world(scenario, 1)
	var loop: MatchLoop = MatchLoop.create(scenario, SCENARIO_PATH, 1, world)
	var sent: Array[Array] = []
	for tick: int in 40:
		var queued: Array[Command] = []
		for k: int in tick % 4:
			var player: int = 1 + (tick + k) % 2
			var unit: int = 1 if player == 1 else 31
			queued.append(Command.move(player, PackedInt32Array([unit]), 2000 + tick, 3000 + k))
		loop.step(world, queued)
		for command: Command in queued:
			sent.append([command.tick, command.sequence])
	assert_int(sent.size()).is_equal(60)
	var logged: Array[Command] = _log(loop.replay)
	assert_int(logged.size()).is_equal(60)
	for k: int in 60:
		(
			assert_array([logged[k].tick, logged[k].sequence])
			. override_failure_message(str(k))
			. is_equal([sent[k][0], k])
		)
		assert_array(sent[k]).is_equal([sent[k][0], k])
	assert_array([sent[0][0], sent[59][0], loop.next_sequence]).is_equal([1, 39, 60])
	assert_int(world.dropped_commands).is_equal(0)


## The loop stamps the tick of the step, whatever the caller wrote, so a command is never late.
func test_commands_get_the_tick_of_the_step_whatever_the_caller_wrote() -> void:
	var scenario: ScenarioDef = load(SCENARIO_PATH) as ScenarioDef
	var world: World = _world(scenario, 1)
	var loop: MatchLoop = MatchLoop.create(scenario, SCENARIO_PATH, 1, world)
	var none: Array[Command] = []
	for _tick: int in 3:
		loop.step(world, none)
	var early: Command = Command.move(1, PackedInt32Array([1]), 9000, 9000)
	early.tick = 1
	var late: Command = Command.move(1, PackedInt32Array([2]), 9000, 9000)
	late.tick = 99
	var queued: Array[Command] = [early, late]
	loop.step(world, queued)
	assert_array([early.tick, late.tick]).is_equal([3, 3])
	assert_int(world.dropped_commands).is_equal(0)
	assert_array([world.order[0], world.order[1]]).is_equal([World.Order.MOVE, World.Order.MOVE])


## The checkpoint is the state hash after the step whose new tick is a multiple of 15. Tick 0 has
## none (no tick has run), nor does a final tick that is not a multiple of 15, and last_hash is 0
## until the first.
func test_checkpoints_at_15_30_and_45_equal_the_state_hash_at_those_ticks() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = _world(scenario, 9)
	var loop: MatchLoop = MatchLoop.create(scenario, ARENA_PATH, 9, world)
	var none: Array[Command] = []
	var expected: PackedInt64Array = PackedInt64Array()
	var last: Array[int] = []
	for _tick: int in 50:
		loop.step(world, none)
		if world.tick % 15 == 0:
			expected.append(world.state_hash())
		if world.tick == 14:
			assert_array([loop.last_hash, loop.replay.checkpoint_ticks.size()]).is_equal([0, 0])
		last.append(loop.last_hash)
	assert_array(loop.replay.checkpoint_ticks).is_equal([15, 30, 45])
	assert_array(loop.replay.checkpoint_hashes).is_equal(expected)
	assert_int(expected.size()).is_equal(3)
	assert_bool(expected[0] != expected[1] and expected[1] != expected[2]).is_true()
	# last_hash changes on a checkpoint and holds until the next one.
	assert_array([last[13], last[14], last[28], last[29], last[44], last[49]]).is_equal(
		[0, expected[0], expected[0], expected[1], expected[2], expected[2]]
	)
	assert_int(world.tick).is_equal(50)


## Nothing is created or resized on a tick with no scenario order and no queued command: every
## array of the world keeps its size, no object appears, and the log stays as long as it was.
func test_ticks_without_commands_keep_every_array_size() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = _world(scenario, 42)
	var loop: MatchLoop = MatchLoop.create(scenario, ARENA_PATH, 42, world)
	var none: Array[Command] = []
	for _tick: int in 2:
		loop.step(world, none)
	var sizes: Dictionary[String, int] = _array_sizes(world)
	assert_bool(sizes.size() > 40).is_true()
	var log_size: int = loop.replay.commands.size()
	var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	# Ticks 2 to 13: no order, no queued command and no checkpoint.
	for _tick: int in 12:
		loop.step(world, none)
	var objects_after: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	assert_int(world.tick).is_equal(14)
	assert_dict(_array_sizes(world)).is_equal(sizes)
	assert_int(objects_after).is_equal(objects)
	assert_int(loop.replay.commands.size()).is_equal(log_size)
	assert_array([loop.next_sequence, loop.replay.checkpoint_ticks.size()]).is_equal([2, 0])
	assert_bool(none.is_empty()).is_true()


## The commands in `queued` are the loop's from the call on (ADR 0012 section 2): it stamps those
## very objects and does not copy them, and it neither sorts nor empties the caller's array. The
## list it hands Sim.step is its own and is empty again after the step.
func test_the_loop_stamps_the_callers_commands_in_place_and_leaves_the_array_alone() -> void:
	var scenario: ScenarioDef = load(SCENARIO_PATH) as ScenarioDef
	var world: World = _world(scenario, 1)
	var loop: MatchLoop = MatchLoop.create(scenario, SCENARIO_PATH, 1, world)
	var second: Command = Command.move(2, PackedInt32Array([31]), 20500, 20500)
	var first: Command = Command.move(1, PackedInt32Array([1]), 20500, 20500)
	var queued: Array[Command] = [second, first]
	var ids: Array[int] = [second.get_instance_id(), first.get_instance_id()]
	loop.step(world, queued)
	# Stamped where they are: the first of the array has sequence 0, though Sim.step sorts player 1
	# before player 2.
	assert_array([second.tick, second.sequence, first.tick, first.sequence]).is_equal([0, 0, 0, 1])
	assert_array([queued[0].get_instance_id(), queued[1].get_instance_id()]).is_equal(ids)
	assert_int(queued.size()).is_equal(2)
	# A stale list would run both again with an old tick: dropped and counted.
	loop.step(world, [])
	assert_int(world.dropped_commands).is_equal(0)
	assert_array([queued[0].sequence, queued[1].sequence, loop.next_sequence]).is_equal([0, 1, 2])


## The list the loop hands Sim.step is one Array for the whole match (private, so it is read here
## only to tell it apart from a new one). A probe looks at it from inside Sim.step: it holds the
## stamped commands of the tick there, is the same object after every tick, and is empty then.
func test_the_loop_reuses_one_command_list() -> void:
	var scenario: ScenarioDef = load(SCENARIO_PATH) as ScenarioDef
	var world: World = _world(scenario, 1)
	var loop: MatchLoop = MatchLoop.create(scenario, SCENARIO_PATH, 1, world)
	var list: Array[Command] = loop._commands
	var probe: ListProbe = ListProbe.new()
	probe.loop = loop
	for tick: int in 6:
		var queued: Array[Command] = []
		if tick % 2 == 1:
			queued.append(Command.stop(1, PackedInt32Array([1])))
		loop.step(world, queued, probe)
		assert_bool(is_same(loop._commands, list)).override_failure_message(str(tick)).is_true()
		assert_int(loop._commands.size()).override_failure_message(str(tick)).is_equal(0)
	assert_array(probe.sizes).is_equal([0, 1, 0, 1, 0, 1])
	assert_int(loop.next_sequence).is_equal(3)


## A null in `queued` is skipped before stamping: no record, no sequence, no dropped command, in
## the run (and so in a replay). CommandQueue.submit ignores null, so the runner never sends one.
func test_a_null_in_the_queue_is_skipped_and_neither_recorded_nor_counted() -> void:
	var scenario: ScenarioDef = load(SCENARIO_PATH) as ScenarioDef
	var world: World = _world(scenario, 1)
	var plain: World = _world(scenario, 1)
	var loop: MatchLoop = MatchLoop.create(scenario, SCENARIO_PATH, 1, world)
	var clean: MatchLoop = MatchLoop.create(scenario, SCENARIO_PATH, 1, plain)
	var command: Command = Command.move(1, PackedInt32Array([1]), 20500, 20500)
	var twin: Command = Command.move(1, PackedInt32Array([1]), 20500, 20500)
	var queued: Array[Command] = [null, command, null]
	loop.step(world, queued)
	var only: Array[Command] = [twin]
	clean.step(plain, only)
	assert_array([world.dropped_commands, loop.next_sequence, command.sequence]).is_equal([0, 1, 0])
	assert_int(queued.size()).is_equal(3)
	assert_array(loop.replay.commands).is_equal(clean.replay.commands)
	assert_int(loop.replay.commands.size()).is_equal(10)
	assert_int(world.state_hash()).is_equal(plain.state_hash())
	# A null alone changes nothing.
	var nulls: Array[Command] = [null, null]
	loop.step(world, nulls)
	assert_array([world.dropped_commands, loop.next_sequence]).is_equal([0, 1])


## Every stamped command is recorded before Sim.step, whatever Sim.step then does with it: one it
## drops (a foreign unit, an unknown type, an over-limit command) is in the log as it is, and is
## counted in dropped_commands. An over-limit command is recorded whole, so a replay drops it again.
func test_every_command_is_recorded_as_stamped_even_when_sim_step_drops_it() -> void:
	var scenario: ScenarioDef = load(SCENARIO_PATH) as ScenarioDef
	var world: World = _world(scenario, 1)
	var loop: MatchLoop = MatchLoop.create(scenario, SCENARIO_PATH, 1, world)
	var foreign: Command = Command.move(1, PackedInt32Array([31]), 5000, 5000)
	var reserved: Command = Samples.full(12, -1, 9)
	var crowd: Command = Command.move(1, PackedInt32Array(range(1, 258)), 5000, 5000)
	var heavy: Command = Command.move(1, PackedInt32Array([1]), 5000, 5000)
	heavy.payload = PackedInt32Array(range(17))
	var good: Command = Command.move(1, PackedInt32Array([2]), 5000, 5000)
	var queued: Array[Command] = [foreign, reserved, crowd, heavy, good]
	loop.step(world, queued)
	assert_int(world.dropped_commands).is_equal(4)
	assert_array(world.order.slice(0, 3)).is_equal(
		[World.Order.IDLE, World.Order.MOVE, World.Order.IDLE]
	)
	var expected: PackedInt32Array = PackedInt32Array()
	for k: int in queued.size():
		assert_array([queued[k].tick, queued[k].sequence]).is_equal([0, k])
		queued[k].encode(expected)
	assert_array(loop.replay.commands).is_equal(expected)
	# 10 + 14 + 266 (257 ids) + 27 (17 payload ints) + 10 ints.
	assert_int(expected.size()).is_equal(327)


## The probe goes to Sim.step, one begin per tick, and a probe changes no hash.
func test_the_probe_is_passed_on_and_changes_no_hash() -> void:
	var scenario: ScenarioDef = load(SCENARIO_PATH) as ScenarioDef
	var probed: World = _world(scenario, 1)
	var plain: World = _world(scenario, 1)
	var with_probe: MatchLoop = MatchLoop.create(scenario, SCENARIO_PATH, 1, probed)
	var without: MatchLoop = MatchLoop.create(scenario, SCENARIO_PATH, 1, plain)
	var probe: SimProbe = RecordingProbe.new()
	var none: Array[Command] = []
	for _tick: int in 30:
		with_probe.step(probed, none, probe)
		without.step(plain, none)
	assert_int(probe.calls.count(-1)).is_equal(30)
	assert_int(probe.calls[0]).is_equal(-1)
	assert_array(with_probe.replay.checkpoint_hashes).is_equal(without.replay.checkpoint_hashes)
	assert_int(probed.state_hash()).is_equal(plain.state_hash())


func _world(scenario: ScenarioDef, seed: int) -> World:
	return World.from_scenario(scenario, DetRandom.create(seed, DetRandom.STREAM_SIM))


## The commands of the log, decoded.
func _log(replay: Replay) -> Array[Command]:
	var all: Array[Command] = []
	var at: int = 0
	while at < replay.commands.size():
		var command: Command = Command.new()
		at = Command.decode(replay.commands, at, command)
		assert_bool(at > 0).is_true()
		all.append(command)
	return all


## The size of every Packed array and Array a world holds, by property name.
func _array_sizes(world: World) -> Dictionary[String, int]:
	var sizes: Dictionary[String, int] = {}
	for info: Dictionary in world.get_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if PACKED_KINDS.has(int(info["type"])):
			sizes[String(info["name"])] = int(world.get(info["name"]).size())
	return sizes


## Writes down how many commands the loop's list holds when Sim.step starts.
class ListProbe:
	extends SimProbe
	var loop: MatchLoop
	var sizes: Array[int] = []

	func begin() -> void:
		sizes.append(loop._commands.size())
