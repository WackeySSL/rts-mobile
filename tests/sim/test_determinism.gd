extends GdUnitTestSuite
## Determinism (plan P35b, ADR 0007 sections 8 and 9, CLAUDE.md rule 3): the sim is a pure function
## of the scenario, the seed and the ordered commands. The same seed and commands give the same
## hash at every checkpoint, another seed does not, the order a list of stamped commands is given
## in does not matter, and two matches stepped one tick at a time in turn do not touch each other.
## A mismatch is reported by the sections of the state hash that differ (HashReport).

const MatchScript: GDScript = preload("res://tests/sim/support/match_script.gd")
const HashReport: GDScript = preload("res://tests/sim/support/hash_report.gd")
const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
const TICKS: int = 300


func test_the_same_seed_and_commands_twice_give_equal_hashes_every_15_ticks() -> void:
	var first: World = MatchScript.world(42)
	var second: World = MatchScript.world(42)
	var a: MatchLoop = MatchScript.loop(first, 42)
	MatchScript.play(first, a, TICKS)
	var b: MatchLoop = MatchScript.loop(second, 42)
	MatchScript.play(second, b, TICKS)
	assert_int(a.replay.checkpoint_hashes.size()).is_equal(20)
	assert_array(b.replay.checkpoint_ticks).is_equal(a.replay.checkpoint_ticks)
	(
		assert_array(b.replay.checkpoint_hashes)
		. override_failure_message(HashReport.mismatch(first, second))
		. is_equal(a.replay.checkpoint_hashes)
	)
	assert_str(HashReport.mismatch(first, second)).is_empty()
	assert_array(b.replay.commands).is_equal(a.replay.commands)
	# Not vacuous: the 20 checkpoints are all different, and another seed gives other ones.
	var distinct: Dictionary[int, bool] = {}
	for hash_value: int in a.replay.checkpoint_hashes:
		distinct[hash_value] = true
	assert_int(distinct.size()).is_equal(20)
	var third: World = MatchScript.world(43)
	var c: MatchLoop = MatchScript.loop(third, 43)
	MatchScript.play(third, c, TICKS)
	assert_int(first.dropped_commands).is_equal(2)
	for k: int in 20:
		assert_bool(c.replay.checkpoint_hashes[k] != a.replay.checkpoint_hashes[k]).is_true()


## The seed reaches the match through the jitter of the spawn, so the two worlds differ before the
## first tick: in the unit positions, and in the stream state of the header. Without jitter (the
## controls scenario) only the header differs, which is how a jitter shows apart from the stream.
func test_seed_1_and_seed_2_differ_at_tick_0_through_jitter() -> void:
	var one: World = MatchScript.world(1)
	var two: World = MatchScript.world(2)
	var again: World = MatchScript.world(1)
	assert_array([one.tick, two.tick]).is_equal([0, 0])
	assert_int(one.state_hash()).is_not_equal(two.state_hash())
	assert_str(HashReport.mismatch(one, again)).is_empty()
	assert_array(one.pos_x).is_not_equal(two.pos_x)
	var message: String = HashReport.mismatch(one, two)
	for section: String in ["header", "pos_x", "pos_y"]:
		assert_str(message).contains(section)
	for section: String in ["unit_id", "owner", "hp", "map", "fog"]:
		assert_str(message).not_contains(section)
	# No jitter in the controls scenario: the positions are the same and the header is not.
	var scenario: ScenarioDef = load(SCENARIO_PATH) as ScenarioDef
	var plain_one: World = World.from_scenario(scenario, DetRandom.create(1, DetRandom.STREAM_SIM))
	var plain_two: World = World.from_scenario(scenario, DetRandom.create(2, DetRandom.STREAM_SIM))
	assert_array(plain_one.pos_x).is_equal(plain_two.pos_x)
	assert_str(HashReport.mismatch(plain_one, plain_two)).is_equal("tick 0 / 0: header")
	# The difference stays through the first checkpoint.
	var a: MatchLoop = MatchScript.loop(one, 1)
	var b: MatchLoop = MatchScript.loop(two, 2)
	MatchScript.play(one, a, 15)
	MatchScript.play(two, b, 15)
	assert_array(a.replay.checkpoint_ticks).is_equal([15])
	assert_int(a.replay.checkpoint_hashes[0]).is_not_equal(b.replay.checkpoint_hashes[0])


## Sim.step sorts by (tick, player, sequence), so the order of the list it is given does not
## matter once the commands are stamped. The players' groups overlap and conflict, so the sequence
## decides who wins, and swapping two sequences changes the hash.
func test_commands_listed_in_another_order_with_the_same_sequences_give_the_same_hashes() -> void:
	var worlds: Array[World] = []
	for _k: int in 4:
		worlds.append(MatchScript.world(5))
	# 0: as stamped, 1: reversed, 2: rotated by one, 3: as stamped, with two sequences swapped.
	for _tick: int in 90:
		for k: int in 4:
			Sim.step(worlds[k], _stamped(worlds[k].tick, k, k == 3))
		if worlds[0].tick % 15 == 0:
			for k: int in [1, 2]:
				assert_str(HashReport.mismatch(worlds[0], worlds[k])).is_empty()
	# The swap decides who wins the overlap, and the worlds never meet again.
	assert_int(worlds[3].state_hash()).is_not_equal(worlds[0].state_hash())
	assert_int(worlds[0].dropped_commands).is_equal(0)
	assert_int(worlds[0].order.count(World.Order.MOVE)).is_greater(10)


## Through the loop the sequence is the order of submission. Two players' commands queued in either
## order give one match, because the player comes before the sequence; one player's two commands
## do not, because the later one wins.
func test_queue_order_matters_only_within_a_player() -> void:
	var results: Array[int] = []
	for order: Array in [[1, 2], [2, 1]]:
		var world: World = MatchScript.world(5)
		var loop: MatchLoop = MatchScript.loop(world, 5)
		var queued: Array[Command] = []
		for player: int in order:
			var first_id: int = 1 if player == 1 else 76
			queued.append(Command.move(player, PackedInt32Array([first_id]), 40500, 10500))
		loop.step(world, queued)
		for _tick: int in 29:
			loop.step(world, [])
		results.append(world.state_hash())
	assert_int(results[1]).is_equal(results[0])
	var by_order: Array[int] = []
	for flip: bool in [false, true]:
		var world: World = MatchScript.world(5)
		var loop: MatchLoop = MatchScript.loop(world, 5)
		# Unit 2 is in both groups, and goes where the later of the two sends it.
		var queued: Array[Command] = [
			Command.move(1, PackedInt32Array([1, 2]), 30500, 20500),
			Command.move(1, PackedInt32Array([2, 3]), 10500, 40500),
		]
		if flip:
			queued.reverse()
		loop.step(world, queued)
		for _tick: int in 29:
			loop.step(world, [])
		by_order.append(world.state_hash())
	assert_int(by_order[1]).is_not_equal(by_order[0])


## A and B step one tick each in turn: every checkpoint equals the other's, and equals a run
## that had the machine to itself, so no state is shared between two worlds or two loops. A third
## match with another seed in the turn does not change either.
func test_two_worlds_stepped_alternately_match_every_15_ticks() -> void:
	var alone: World = MatchScript.world(7)
	var alone_loop: MatchLoop = MatchScript.loop(alone, 7)
	MatchScript.play(alone, alone_loop, TICKS)
	var world_a: World = MatchScript.world(7)
	var world_b: World = MatchScript.world(7)
	var world_c: World = MatchScript.world(8)
	var loop_a: MatchLoop = MatchScript.loop(world_a, 7)
	var loop_b: MatchLoop = MatchScript.loop(world_b, 7)
	var loop_c: MatchLoop = MatchScript.loop(world_c, 8)
	var checked: int = 0
	for _tick: int in TICKS:
		loop_a.step(world_a, MatchScript.commands_at(world_a.tick))
		loop_c.step(world_c, MatchScript.commands_at(world_c.tick))
		loop_b.step(world_b, MatchScript.commands_at(world_b.tick))
		if world_a.tick % 15 == 0:
			assert_str(HashReport.mismatch(world_a, world_b)).is_empty()
			checked += 1
	assert_int(checked).is_equal(20)
	assert_array(loop_a.replay.checkpoint_hashes).is_equal(alone_loop.replay.checkpoint_hashes)
	assert_array(loop_b.replay.checkpoint_hashes).is_equal(alone_loop.replay.checkpoint_hashes)
	assert_array(loop_a.replay.commands).is_equal(alone_loop.replay.commands)
	assert_bool(world_c.state_hash() != alone.state_hash()).is_true()
	# The third match is the same as it would be alone.
	var alone_c: World = MatchScript.world(8)
	var alone_c_loop: MatchLoop = MatchScript.loop(alone_c, 8)
	MatchScript.play(alone_c, alone_c_loop, TICKS)
	assert_array(loop_c.replay.checkpoint_hashes).is_equal(alone_c_loop.replay.checkpoint_hashes)


## The message of a mismatch names the sections of hash_parts() that differ, in hash order, and
## nothing for equal Worlds.
func test_a_mismatch_message_lists_the_hash_parts_sections() -> void:
	var scenario: ScenarioDef = load(SCENARIO_PATH) as ScenarioDef
	var a: World = World.from_scenario(scenario, DetRandom.create(3, DetRandom.STREAM_SIM))
	var b: World = World.from_scenario(scenario, DetRandom.create(3, DetRandom.STREAM_SIM))
	assert_str(HashReport.mismatch(a, b)).is_empty()
	var names: PackedStringArray = World.hash_section_names()
	assert_int(a.hash_parts().size()).is_equal(names.size())
	b.hp[3] -= 1
	assert_str(HashReport.mismatch(a, b)).is_equal("tick 0 / 0: hp")
	b.pos_x[7] += 1
	assert_str(HashReport.mismatch(a, b)).is_equal("tick 0 / 0: pos_x, hp")
	b.fog.explored[0] ^= 1
	b.dropped_commands += 1
	b.tick = 4
	var message: String = HashReport.mismatch(a, b)
	assert_str(message).is_equal("tick 0 / 4: header, pos_x, hp, fog")
	# The names are the sections of World.hash_section_names(), in that order.
	var listed: PackedStringArray = message.split(": ")[1].split(", ")
	var at: int = -1
	for section: String in listed:
		assert_bool(names.find(section) > at).override_failure_message(section).is_true()
		at = names.find(section)


## The commands of `tick`, stamped. Player 1 sends two overlapping MOVEs at tick 0 (sequence 0 and
## 1) and a STOP and a MOVE at tick 30 (sequence 2 and 3), player 2 an ATTACK_MOVE at tick 0
## (sequence 0). `shape` 0 lists them as stamped, 1 reversed, 2 rotated by one and 3 as stamped;
## `swapped` swaps the sequences of the two MOVEs of player 1 at tick 0.
func _stamped(tick: int, shape: int, swapped: bool) -> Array[Command]:
	var list: Array[Command] = []
	match tick:
		0:
			var low: int = 1 if swapped else 0
			list.append(_stamp(Command.move(1, _ids(1, 11), 30500, 20500), 0, low))
			list.append(_stamp(Command.move(1, _ids(5, 16), 10500, 30500), 0, 1 - low))
			list.append(_stamp(Command.attack_move(2, _ids(76, 91), 10500, 40500), 0, 0))
		30:
			list.append(_stamp(Command.stop(1, _ids(1, 4)), 30, 2))
			list.append(_stamp(Command.move(1, _ids(2, 5), 20500, 20500), 30, 3))
	if shape == 1:
		list.reverse()
	elif shape == 2 and list.size() > 1:
		var head: Command = list.pop_front()
		list.append(head)
	return list


func _stamp(command: Command, tick: int, sequence: int) -> Command:
	command.tick = tick
	command.sequence = sequence
	return command


## The ids from `first` up to, not including, `end`.
func _ids(first: int, end: int) -> PackedInt32Array:
	return PackedInt32Array(range(first, end))
