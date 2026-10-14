extends GdUnitTestSuite
## Replay.play (plan P35b, ADR 0007 section 9), part 2 of the replay tests; part 1, the log and its
## bytes, is test_replay (it holds 15 tests and gdlint allows 20 public methods per file).
## Literal numbers: checkpoints and the first tick that differs are pinned as ticks, not computed.

const MatchScript: GDScript = preload("res://tests/sim/support/match_script.gd")
const HashReport: GDScript = preload("res://tests/sim/support/hash_report.gd")

# Part 2 (P35b): Replay.play. The recording is the arena with its jitter and seed 7 (MatchScript):
# the two scenario orders, then MOVE (tick 20), ATTACK_MOVE (45), STOP (50), ATTACK (100) and two
# commands that Sim.step drops, a MOVE that names player 2's units (130) and an ATTACK_MOVE with 257
# ids (160, over MAX_UNITS). Checkpoints are at 15, 30, ... 300: index k is tick 15 * (k + 1).


func test_play_on_a_fresh_world_matches_every_checkpoint_and_the_final_hash() -> void:
	var recording: Recording = _record(300)
	var replay: Replay = recording.replay
	assert_array([replay.final_tick, replay.checkpoint_ticks.size()]).is_equal([300, 20])
	assert_int(recording.world.dropped_commands).is_equal(2)
	# The log holds the scenario orders first, then the six, the dropped two among them.
	var types: Array[int] = []
	var ticks: Array[int] = []
	var sequences: Array[int] = []
	var counts: Array[int] = []
	for command: Command in _decode(replay):
		types.append(command.type)
		ticks.append(command.tick)
		sequences.append(command.sequence)
		counts.append(command.unit_ids.size())
	assert_array(types).is_equal([1, 1, 2, 1, 4, 3, 2, 1])
	assert_array(ticks).is_equal([0, 0, 20, 45, 50, 100, 130, 160])
	assert_array(sequences).is_equal([0, 1, 2, 3, 4, 5, 6, 7])
	assert_array(counts).is_equal([75, 75, 10, 15, 5, 10, 3, 257])
	var fresh: World = _fresh(replay)
	assert_int(Replay.play(replay, fresh, 300)).is_equal(-1)
	assert_array([fresh.tick, fresh.dropped_commands]).is_equal([300, 2])
	assert_int(fresh.state_hash()).is_equal(replay.final_hash)
	assert_str(HashReport.mismatch(fresh, recording.world)).is_empty()
	# Through bytes, too: what the runner would save plays the same.
	var loaded: Replay = Replay.from_bytes(replay.to_bytes())
	assert_object(loaded).is_not_null()
	var again: World = _fresh(loaded)
	assert_int(Replay.play(loaded, again, 300)).is_equal(-1)
	assert_int(again.state_hash()).is_equal(replay.final_hash)


## An edit of the log shows at the first checkpoint at or after the tick after it ran: a command
## stamped T changes the state of tick T + 1. A dropped command counts in the state too, so
## removing one is found, and so is a command added.
func test_a_changed_command_makes_play_return_the_first_checkpoint_after_it() -> void:
	var replay: Replay = _record(300).replay
	# The edit and the checkpoint it must be found at. The scenario orders are records 0 and 1, so
	# the command of MatchScript.TICKS[k] is record k + 2.
	var cases: Dictionary[String, int] = {
		"move_elsewhere": 30,
		"stop_without_unit_5": 60,
		"attack_unit_101": 105,
		"remove_dropped_130": 135,
		"remove_over_limit_160": 165,
		"remove_scenario_order": 15,
		"add_move_200": 210,
	}
	for edit: String in cases:
		var edited: Replay = _edited(replay, edit)
		var world: World = _fresh(replay)
		var found: int = Replay.play(edited, world, 300)
		assert_int(found).override_failure_message(edit).is_equal(cases[edit])
		assert_int(world.tick).override_failure_message(edit).is_equal(cases[edit])
	# The copy itself is not what fails: with no edit it matches.
	assert_int(Replay.play(_edited(replay, "none"), _fresh(replay), 300)).is_equal(-1)
	# A recorded hash that is wrong is found at its own tick, nothing else needed.
	var wrong: Replay = _edited(replay, "none")
	wrong.checkpoint_hashes[4] ^= 1
	assert_int(Replay.play(wrong, _fresh(replay), 300)).is_equal(75)


## The tick of the change decides the checkpoint: 14 shows at 15 (the state of tick 15 holds it),
## 15 only at 30, 104 at 105 and 105 at 120.
func test_a_command_next_to_a_checkpoint_shows_at_the_right_one() -> void:
	var expected: Dictionary[int, int] = {14: 15, 15: 30, 104: 105, 105: 120}
	for stamped: int in expected:
		var world: World = MatchScript.world(4)
		var loop: MatchLoop = MatchScript.loop(world, 4)
		for _tick: int in 150:
			var queued: Array[Command] = []
			if world.tick == stamped:
				queued.append(Command.move(1, PackedInt32Array([1, 2, 3]), 33500, 12500))
			loop.step(world, queued)
		loop.replay.finish(world)
		var changed: Replay = _edited(loop.replay, "move_elsewhere")
		var found: int = Replay.play(changed, _fresh(loop.replay), 150)
		assert_int(found).override_failure_message("at %d" % stamped).is_equal(expected[stamped])
		assert_int(Replay.play(loop.replay, _fresh(loop.replay), 150)).is_equal(-1)


## Data that differs is found before any step: a changed weapon damage, a changed unit speed, a
## changed rule or a replay with another defs_hash all give -2, and the world stays at tick 0.
func test_changed_data_returns_minus_2_before_any_step() -> void:
	var replay: Replay = _record(60).replay
	for change: String in ["damage", "speed", "armour_table", "rule", "type_id"]:
		var world: World = _fresh(replay)
		match change:
			"damage":
				world.weapon_damage[0] += 1
			"speed":
				world.type_speed[1] -= 1
			"armour_table":
				world.weapon_vs_armour[5] += 1
			"rule":
				world.retarget_period_ticks += 1
			"type_id":
				world.type_ids[2] = &"other"
		assert_int(Replay.play(replay, world, 60)).override_failure_message(change).is_equal(-2)
		assert_int(world.tick).override_failure_message(change).is_equal(0)
	var other: Replay = Replay.from_bytes(replay.to_bytes())
	other.defs_hash ^= 1
	var fresh: World = _fresh(replay)
	assert_int(Replay.play(other, fresh, 60)).is_equal(-2)
	assert_int(fresh.tick).is_equal(0)
	# Unchanged data is not -2.
	assert_int(Replay.play(replay, _fresh(replay), 60)).is_equal(-1)


## play stops at `until_tick` and compares only the checkpoints up to it; a bound at or below the
## world's tick steps nothing, and a bound past the log steps on without commands.
func test_play_stops_at_until_tick_and_compares_the_checkpoints_up_to_it() -> void:
	var replay: Replay = _record(300).replay
	var at_105: World = _fresh(replay)
	assert_int(Replay.play(replay, at_105, 105)).is_equal(-1)
	assert_array([at_105.tick, at_105.state_hash()]).is_equal([105, replay.checkpoint_hashes[6]])
	var at_100: World = _fresh(replay)
	assert_int(Replay.play(replay, at_100, 100)).is_equal(-1)
	assert_int(at_100.tick).is_equal(100)
	var start: int = _fresh(replay).state_hash()
	for bound: int in [0, -5]:
		var untouched: World = _fresh(replay)
		assert_int(Replay.play(replay, untouched, bound)).is_equal(-1)
		assert_array([untouched.tick, untouched.state_hash()]).is_equal([0, start])
	var past: World = _fresh(replay)
	assert_int(Replay.play(replay, past, 450)).is_equal(-1)
	assert_int(past.tick).is_equal(450)
	# The last checkpoint is wrong: it is not compared below 300, and found at 300.
	var wrong: Replay = Replay.from_bytes(replay.to_bytes())
	wrong.checkpoint_hashes[19] ^= 1
	assert_int(Replay.play(wrong, _fresh(replay), 299)).is_equal(-1)
	assert_int(Replay.play(wrong, _fresh(replay), 300)).is_equal(300)
	assert_int(Replay.play(wrong, _fresh(replay), 450)).is_equal(300)


## A command Sim.step drops is recorded whole, so the replay drops it again and counts it: here a
## command with 17 payload ints and one with 257 ids, among good ones. The log keeps both sizes,
## and the final hash includes the two counts.
func test_over_limit_commands_are_recorded_whole_and_dropped_again() -> void:
	var world: World = MatchScript.world(11)
	var loop: MatchLoop = MatchScript.loop(world, 11)
	for _tick: int in 45:
		var queued: Array[Command] = []
		match world.tick:
			5:
				var heavy: Command = Command.move(1, PackedInt32Array([1]), 5500, 5500)
				heavy.payload = PackedInt32Array(range(100, 117))
				queued.append(heavy)
			10:
				queued.append(Command.move(1, PackedInt32Array(range(1, 258)), 5500, 5500))
			12:
				queued.append(Command.stop(1, PackedInt32Array([1, 2])))
		loop.step(world, queued)
	loop.replay.finish(world)
	assert_int(world.dropped_commands).is_equal(2)
	var logged: Array[Command] = _decode(loop.replay)
	assert_int(logged.size()).is_equal(5)
	assert_array([logged[2].payload.size(), logged[2].unit_ids.size()]).is_equal([17, 1])
	assert_array(Array(logged[2].payload)).is_equal(Array(range(100, 117)))
	assert_array([logged[3].unit_ids.size(), logged[3].payload.size()]).is_equal([257, 0])
	assert_array([logged[4].type, logged[4].tick]).is_equal([Command.Type.STOP, 12])
	var fresh: World = _fresh(loop.replay)
	assert_int(Replay.play(loop.replay, fresh, 45)).is_equal(-1)
	assert_array([fresh.dropped_commands, fresh.state_hash()]).is_equal([2, loop.replay.final_hash])


## A replay built in memory can hold a log that does not decode (from_bytes refuses one): play
## returns -3 at the record, and ends. A record behind the world's tick is the same failure. The
## world is stepped up to the record and no further, and a bound before it never reads it. A
## checkpoint that no run reaches is found at its own tick.
func test_a_log_that_does_not_decode_returns_minus_3_and_ends() -> void:
	# A MOVE of unit 1 at tick 2, ten ints.
	var good: PackedInt32Array = PackedInt32Array([2, 1, 0, 2, 5500, 5500, 0, 1, 1, 0])
	var count_past_end: PackedInt32Array = good.duplicate()
	count_past_end[7] = 3
	var negative_count: PackedInt32Array = good.duplicate()
	negative_count[9] = -1
	var behind: PackedInt32Array = good.duplicate()
	behind[0] = -1
	# The log and the tick the play ends at.
	var cases: Dictionary[String, Array] = {
		"cut short": [good.slice(0, 9), 2],
		"unit count past the end": [count_past_end, 2],
		"negative payload count": [negative_count, 2],
		"tick before the world's": [behind, 0],
		"cut short after a good record": [good + good.slice(0, 9), 2],
		"a lone int": [PackedInt32Array([2]), 2],
	}
	for label: String in cases:
		var replay: Replay = _bare(cases[label][0])
		var world: World = _fresh(replay)
		# 1000 ticks asked for, and it ends where the record is.
		assert_int(Replay.play(replay, world, 1000)).override_failure_message(label).is_equal(-3)
		assert_int(world.tick).override_failure_message(label).is_equal(cases[label][1])
		# A bound at the record's tick does not read it.
		if cases[label][1] > 0:
			var early: World = _fresh(replay)
			assert_int(Replay.play(replay, early, cases[label][1])).is_equal(-1)
			assert_int(early.tick).is_equal(cases[label][1])
	# Ticks that go back: a record at tick 5, then one at tick 2, which is behind at tick 5.
	var backwards: PackedInt32Array = good.duplicate()
	backwards[0] = 5
	var unordered: Replay = _bare(backwards + good)
	var walked: World = _fresh(unordered)
	assert_int(Replay.play(unordered, walked, 1 << 40)).is_equal(-3)
	assert_int(walked.tick).is_equal(5)
	# Checkpoints that no run reaches: off the 15-tick grid, out of order, and one array longer.
	var run: World = MatchScript.world(7)
	var quiet: MatchLoop = MatchLoop.create(null, MatchScript.ARENA_PATH, 7, run)
	for _tick: int in 45:
		quiet.step(run, [])
	var real: PackedInt64Array = quiet.replay.checkpoint_hashes
	assert_array(quiet.replay.checkpoint_ticks).is_equal([15, 30, 45])
	assert_int(Replay.play(quiet.replay, _fresh(quiet.replay), 45)).is_equal(-1)
	var odd: Replay = _bare(PackedInt32Array())
	odd.checkpoint_ticks = PackedInt32Array([20])
	odd.checkpoint_hashes = PackedInt64Array([real[0]])
	assert_int(Replay.play(odd, _fresh(odd), 100)).is_equal(20)
	odd.checkpoint_ticks = PackedInt32Array([30, 15, 45])
	odd.checkpoint_hashes = PackedInt64Array([real[1], real[0], real[2]])
	assert_int(Replay.play(odd, _fresh(odd), 100)).is_equal(15)
	odd.checkpoint_ticks = PackedInt32Array([15, 30, 45])
	odd.checkpoint_hashes = PackedInt64Array([real[0]])
	assert_int(Replay.play(odd, _fresh(odd), 100)).is_equal(-1)
	# A negative tick would read as a code (-1 is "matched"), so it is a bad replay.
	for negative: int in [-1, -2, -3, -40]:
		odd.checkpoint_ticks = PackedInt32Array([negative])
		odd.checkpoint_hashes = PackedInt64Array([real[0]])
		(
			assert_int(Replay.play(odd, _fresh(odd), 100))
			. override_failure_message(str(negative))
			. is_equal(-3)
		)


## What a recording gives back: the replay, finished, and the world it ended in.
class Recording:
	extends RefCounted
	var replay: Replay
	var world: World


## `ticks` ticks of the arena (MatchScript) with `match_seed`, recorded and finished.
func _record(ticks: int, match_seed: int = 7) -> Recording:
	var recording: Recording = Recording.new()
	recording.world = MatchScript.world(match_seed)
	var loop: MatchLoop = MatchScript.loop(recording.world, match_seed)
	MatchScript.play(recording.world, loop, ticks)
	loop.replay.finish(recording.world)
	recording.replay = loop.replay
	return recording


## A fresh world of the replay's scenario, drawn from the replay's seed.
func _fresh(replay: Replay) -> World:
	var scenario: ScenarioDef = load(replay.scenario_path) as ScenarioDef
	return World.from_scenario(scenario, DetRandom.create(replay.seed, DetRandom.STREAM_SIM))


## A replay of the arena with this log, seed 7 and the defs_hash of that world, and no checkpoints.
func _bare(log_ints: PackedInt32Array) -> Replay:
	var world: World = MatchScript.world(7)
	var replay: Replay = Replay.begin(MatchScript.ARENA_PATH, 7, world.defs_hash())
	replay.commands = log_ints
	return replay


## The commands of the log, in order.
func _decode(replay: Replay) -> Array[Command]:
	var all: Array[Command] = []
	var at: int = 0
	while at < replay.commands.size():
		var command: Command = Command.new()
		at = Command.decode(replay.commands, at, command)
		assert_bool(at > 0).override_failure_message("the log does not decode").is_true()
		if at < 0:
			break
		all.append(command)
	return all


## A copy of `replay` (through its bytes) whose log is the decoded commands after the edit named
## by `edit` (see _edit) changed them.
func _edited(replay: Replay, edit: String) -> Replay:
	var copy: Replay = Replay.from_bytes(replay.to_bytes())
	var all: Array[Command] = _decode(copy)
	_edit(all, edit)
	copy.commands = PackedInt32Array()
	for command: Command in all:
		command.encode(copy.commands)
	return copy


## Changes the decoded log of the recording: records 0 and 1 are the scenario orders and record
## k + 2 is the command of MatchScript.TICKS[k]; "move_elsewhere" changes record 2, the first
## command after the scenario orders, in either recording.
func _edit(all: Array[Command], edit: String) -> void:
	match edit:
		"move_elsewhere":
			all[2].target_x += 3000
		"stop_without_unit_5":
			all[4].unit_ids = all[4].unit_ids.slice(0, 4)
		"attack_unit_101":
			all[5].target_id = 101
		"remove_dropped_130":
			all.remove_at(6)
		"remove_over_limit_160":
			all.remove_at(7)
		"remove_scenario_order":
			all.remove_at(0)
		"add_move_200":
			var late: Command = Command.move(1, PackedInt32Array([20, 21, 22]), 5500, 5500)
			late.tick = 200
			all.append(late)
