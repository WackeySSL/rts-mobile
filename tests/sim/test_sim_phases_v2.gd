extends GdUnitTestSuite
## The Phase 3 skeleton of Sim.step (plan P70b, ADR 0017 sections 4 and 5): every new Command type
## is dropped and counted until its row (the modules refuse it), the commands need an undefeated
## player, the five module stubs change no state, and a tick runs them after FOG in the order of the
## pipeline. The perf arena is the world: 2 players, 150 units, no building, so it has no queue and
## no producer: since P73 `Production` is no stub, but QUEUE and CANCEL are still dropped here and
## its `run` still changes nothing (tests/sim/test_production_*.gd have the rules).

const RecordingProbe: GDScript = preload("res://tests/sim/recording_probe.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"


func test_every_new_command_type_is_dropped_and_counted_until_its_row() -> void:
	var commands: Dictionary[String, Command] = {
		"place": Command.place(1, 20500, 4500),
		"queue": Command.queue(1, 0),
		"cancel": Command.cancel(1, 0, 0),
		"rally": Command.rally(1, 1, 20500, 4500),
		"harvest": Command.harvest(1, PackedInt32Array([1]), 20500, 4500),
		"surrender": Command.surrender(1),
	}
	var base: World = _arena()
	Sim.step(base, [])
	for label: String in commands:
		var command: Command = commands[label]
		command.tick = 0
		var world: World = _arena()
		Sim.step(world, [command])
		assert_int(world.dropped_commands).override_failure_message(label).is_equal(1)
		# The counter is in the header; nothing else of the state moved.
		assert_array(_differing(base, world)).override_failure_message(label).is_equal(["header"])
		assert_array([world.match_end_tick, world.winner]).is_equal([0, 0])
		assert_array(world.defeated_tick).is_equal([0, 0, 0])


## Types 15-19 and 21-29 stay reserved: no branch, so dropped as unknown like any other.
func test_the_reserved_types_next_to_the_new_ones_are_still_unknown() -> void:
	for type: int in [9, 15, 19, 21, 29]:
		var command: Command = Command.surrender(1)
		command.type = type
		command.tick = 0
		var world: World = _arena()
		Sim.step(world, [command])
		assert_int(world.dropped_commands).override_failure_message(str(type)).is_equal(1)


## The new types need a player who is not defeated; a player past the arrays (a hand-built world
## may raise player_count after prepare()) is not playing either.
func test_a_defeated_or_unknown_player_is_not_playing() -> void:
	var world: World = _arena()
	var command: Command = Command.queue(1, 0)
	assert_bool(Sim._playing(world, command)).is_true()
	world.defeated_tick[1] = 40
	assert_bool(Sim._playing(world, command)).is_false()
	assert_bool(Sim._playing(world, Command.queue(2, 0))).is_true()
	world.player_count = 3
	assert_bool(Sim._playing(world, Command.queue(3, 0))).is_false()


## The skeleton modules change nothing: each `run`, and `release`, leaves the state hash and every
## part of it as it was (Power.run rebuilds the derived row lists since P71, which are in no hash
## section), and each `apply_*` refuses a command that looks right (the arena has no producer for a
## QUEUE and no item for a CANCEL, since P73).
func test_the_stub_modules_change_no_state_and_refuse_every_command() -> void:
	var world: World = _arena()
	var before: PackedInt64Array = world.hash_parts()
	var hash_before: int = world.state_hash()
	Power.run(world)
	Harvest.run(world)
	Production.run(world)
	Outcome.run(world)
	LastSeen.run(world)
	Harvest.release(world, PackedInt32Array([0, 1, 2]))
	assert_int(world.state_hash()).is_equal(hash_before)
	assert_array(world.hash_parts()).is_equal(before)
	assert_bool(Production.apply_queue(world, Command.queue(1, 0))).is_false()
	assert_bool(Production.apply_cancel(world, Command.cancel(1, 0, 0))).is_false()
	assert_bool(Production.apply_place(world, Command.place(1, 20500, 4500))).is_false()
	var ids: PackedInt32Array = PackedInt32Array([1])
	assert_bool(Harvest.apply_harvest(world, Command.harvest(1, ids, 20500, 4500))).is_false()
	assert_bool(Outcome.apply_rally(world, Command.rally(1, 1, 20500, 4500))).is_false()
	assert_bool(Outcome.apply_surrender(world, Command.surrender(1))).is_false()


## A MOVE and a STOP still hand their units to `Harvest.release` and work as before: the order and
## the formation slot are as in Phase 2 (the stub changes no column).
func test_a_unit_group_order_still_applies_with_the_release_call() -> void:
	var world: World = _arena()
	var move: Command = Command.move(1, PackedInt32Array([1, 2]), 20500, 4500)
	move.tick = 0
	Sim.step(world, [move])
	assert_int(world.dropped_commands).is_equal(0)
	assert_array([world.order[0], world.order[1]]).is_equal([World.Order.MOVE, World.Order.MOVE])
	var stop: Command = Command.stop(1, PackedInt32Array([1]))
	stop.tick = 1
	Sim.step(world, [stop])
	assert_int(world.dropped_commands).is_equal(0)
	assert_array([world.order[0], world.order[1]]).is_equal([World.Order.IDLE, World.Order.MOVE])


## One tick marks every phase once, in id order, and the three Phase 3 phases follow FOG; a run of
## the arena through them is the run without a probe (the hashes are equal at every tick).
func test_a_tick_runs_the_three_phases_after_fog_and_the_probe_changes_nothing() -> void:
	var plain: World = _arena()
	var probed: World = _arena()
	var probe: Variant = RecordingProbe.new()
	for _tick: int in 30:
		Sim.step(plain, [])
		Sim.step(probed, [], probe)
		assert_int(probed.state_hash()).is_equal(plain.state_hash())
	var calls: PackedInt32Array = probe.calls
	var one_tick: PackedInt32Array = PackedInt32Array([-1])
	one_tick.append_array(PackedInt32Array(range(SimProbe.Phase.COUNT)))
	assert_int(calls.size()).is_equal(30 * one_tick.size())
	assert_array(calls.slice(calls.size() - one_tick.size())).is_equal(one_tick)
	var tail: PackedInt32Array = calls.slice(calls.size() - 4)
	assert_array(tail).is_equal(
		[
			SimProbe.Phase.FOG,
			SimProbe.Phase.ECONOMY,
			SimProbe.Phase.PRODUCTION,
			SimProbe.Phase.MEMORY
		]
	)


func _arena() -> World:
	return World.from_scenario(load(ARENA_PATH) as ScenarioDef)


## The names of the hash sections where `a` and `b` differ.
func _differing(a: World, b: World) -> Array[String]:
	var names: PackedStringArray = World.hash_section_names()
	var left: PackedInt64Array = a.hash_parts()
	var right: PackedInt64Array = b.hash_parts()
	var found: Array[String] = []
	for index: int in names.size():
		if left[index] != right[index]:
			found.append(names[index])
	return found
