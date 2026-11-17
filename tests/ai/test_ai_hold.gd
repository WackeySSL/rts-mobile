extends "res://tests/ai/support/support_suite.gd"
## Hold position for the waves' artillery (plan row P300): a wave member whose type is in
## `OpponentDef.hold_types` is set to hold with `STANCE`, no other type is, Easy and the frozen
## copies play as before, and the unit is released when it leaves the wave. The fixture's `tank` is
## the hold type; the `squad` is not.


func test_a_hold_type_that_joins_a_wave_gets_a_hold_command() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var tank: int = _add(world, "tank", 4000, 9000)
	_fill(world, memory)
	_launch_wave(memory, PackedInt32Array([tank]), Vector2i(20, 12))
	var holder: AiHold = AiHold.create(_hold_def(), _hold_level(1))
	var sent: Array[Command] = _hold(holder, world, memory)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].type).is_equal(Command.Type.STANCE)
	assert_array(sent[0].payload).is_equal(PackedInt32Array([1]))
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([tank]))
	assert_int(sent[0].player_id).is_equal(1)
	assert_int(holder.holds).is_equal(1)
	# Through the Command, the sim sets the stance (and nothing else did).
	assert_int(world.stance[world.index_of(tank)]).is_equal(0)
	AiRig.step(world, AiRig.loop_of(world), sent)
	assert_int(world.stance[world.index_of(tank)]).is_equal(1)


func test_no_other_type_and_no_home_unit_is_held() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var squad: int = _add(world, "squad", 4000, 9000)
	var wave_tank: int = _add(world, "tank", 4500, 9000)
	var home_tank: int = _add(world, "tank", 5000, 9000)
	_fill(world, memory)
	_launch_wave(memory, PackedInt32Array([squad, wave_tank]), Vector2i(20, 12))
	var holder: AiHold = AiHold.create(_hold_def(), _hold_level(1))
	var sent: Array[Command] = _hold(holder, world, memory)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([wave_tank]))
	assert_bool(sent[0].unit_ids.has(home_tank)).is_false()
	assert_bool(sent[0].unit_ids.has(squad)).is_false()


func test_a_held_unit_is_asked_once_and_released_when_its_wave_ends() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var tank: int = _add(world, "tank", 4000, 9000)
	_fill(world, memory)
	_launch_wave(memory, PackedInt32Array([tank]), Vector2i(20, 12))
	var holder: AiHold = AiHold.create(_hold_def(), _hold_level(1))
	var loop: MatchLoop = AiRig.loop_of(world)
	AiRig.step(world, loop, _hold(holder, world, memory))
	assert_int(world.stance[world.index_of(tank)]).is_equal(1)
	# Held and still in the wave: nothing more to say.
	assert_array(_hold(holder, world, memory)).is_empty()
	# The wave disbands into the home squad (or the unit steps back): it is released.
	memory.member_squad[memory.member_id.bsearch(tank)] = HOME
	var sent: Array[Command] = _hold(holder, world, memory)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].payload).is_equal(PackedInt32Array([0]))
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([tank]))
	assert_int(holder.releases).is_equal(1)
	AiRig.step(world, loop, sent)
	assert_int(world.stance[world.index_of(tank)]).is_equal(0)
	assert_array(_hold(holder, world, memory)).is_empty()


func test_a_normal_unit_at_home_is_never_released_by_a_command() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	_add(world, "tank", 4000, 9000)
	_add(world, "squad", 4500, 9000)
	_fill(world, memory)
	var holder: AiHold = AiHold.create(_hold_def(), _hold_level(1))
	assert_array(_hold(holder, world, memory)).is_empty()


func test_easy_and_a_level_without_the_flag_send_nothing() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var tank: int = _add(world, "tank", 4000, 9000)
	_fill(world, memory)
	_launch_wave(memory, PackedInt32Array([tank]), Vector2i(20, 12))
	var off: AiHold = AiHold.create(_hold_def(), _hold_level(0))
	assert_array(_hold(off, world, memory)).is_empty()
	var easy: AiHold = AiHold.create(_hold_def(), load("res://data/ai/difficulty/easy.tres"))
	assert_array(_hold(easy, world, memory)).is_empty()


func test_no_budget_sends_nothing_and_asks_again_next_think() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var tank: int = _add(world, "tank", 4000, 9000)
	_fill(world, memory)
	_launch_wave(memory, PackedInt32Array([tank]), Vector2i(20, 12))
	var holder: AiHold = AiHold.create(_hold_def(), _hold_level(1))
	var out: Array[Command] = []
	memory.commands_left = 0
	holder.run(PlayerView.of(world, 1), memory, out)
	assert_array(out).is_empty()
	assert_int(_hold(holder, world, memory).size()).is_equal(1)


func test_one_command_left_goes_to_the_hold_and_the_release_waits_for_the_next_think() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var wave_tank: int = _add(world, "tank", 4000, 9000)
	var home_tank: int = _add(world, "tank", 4500, 9000)
	_fill(world, memory)
	var loop: MatchLoop = AiRig.loop_of(world)
	var holder: AiHold = AiHold.create(_hold_def(), _hold_level(1))
	# The second tank holds already (set by an earlier wave) and has left it.
	AiRig.step(world, loop, [Command.stance(1, PackedInt32Array([home_tank]), true)])
	_launch_wave(memory, PackedInt32Array([wave_tank]), Vector2i(20, 12))
	var out: Array[Command] = []
	memory.commands_left = 1
	holder.run(PlayerView.of(world, 1), memory, out)
	assert_int(out.size()).is_equal(1)
	assert_array(out[0].payload).is_equal(PackedInt32Array([1]))
	assert_array(out[0].unit_ids).is_equal(PackedInt32Array([wave_tank]))
	assert_int(memory.commands_left).is_equal(0)
	assert_int(holder.releases).is_equal(0)
	AiRig.step(world, loop, out)
	var next: Array[Command] = _hold(holder, world, memory)
	assert_int(next.size()).is_equal(1)
	assert_array(next[0].payload).is_equal(PackedInt32Array([0]))
	assert_array(next[0].unit_ids).is_equal(PackedInt32Array([home_tank]))
	assert_int(memory.commands_left).is_equal(98)


func test_a_release_with_no_command_left_is_not_sent_and_spends_nothing() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var tank: int = _add(world, "tank", 4000, 9000)
	_fill(world, memory)
	AiRig.step(world, AiRig.loop_of(world), [Command.stance(1, PackedInt32Array([tank]), true)])
	var holder: AiHold = AiHold.create(_hold_def(), _hold_level(1))
	var out: Array[Command] = []
	memory.commands_left = 0
	holder.run(PlayerView.of(world, 1), memory, out)
	assert_array(out).is_empty()
	assert_int(memory.commands_left).is_equal(0)
	assert_int(holder.releases).is_equal(0)


func test_a_hold_type_the_roster_lacks_changes_nothing() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var tank: int = _add(world, "tank", 4000, 9000)
	_fill(world, memory)
	_launch_wave(memory, PackedInt32Array([tank]), Vector2i(20, 12))
	var def: OpponentDef = _hold_def()
	def.hold_types = [&"no_such_type"] as Array[StringName]
	assert_array(_hold(AiHold.create(def, _hold_level(1)), world, memory)).is_empty()


func test_the_controller_owns_a_holder_and_the_shipped_levels_set_the_flag() -> void:
	var ai: OpponentAi = OpponentAi.create(
		_hold_def(), _hold_level(1), 1, DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1)
	)
	assert_object(ai.holder).is_not_null()
	for level: String in ["easy", "normal", "hard"]:
		var shipped: AiDifficultyDef = load("res://data/ai/difficulty/%s.tres" % level)
		assert_int(shipped.hold_in_waves).is_equal(0 if level == "easy" else 1)


func test_the_frozen_copies_hold_nothing_and_keep_their_types() -> void:
	for level: String in ["easy", "normal", "hard"]:
		var copy: AiDifficultyDef = load("res://data/dev/arena/ai_4b/difficulty/%s.tres" % level)
		assert_int(copy.hold_in_waves).is_equal(0)
	var fossil: OpponentDef = load("res://data/dev/arena/ai_4b/opponent_fossil.tres")
	var renew: OpponentDef = load("res://data/dev/arena/ai_4b/opponent_renew.tres")
	assert_array(fossil.hold_types).is_equal([&"artillery"])
	assert_array(renew.hold_types).is_equal([&"renew_artillery"])


func _fixture() -> Array:
	var world: World = _world(false, false)
	return [world, _memory()]


func _hold_def() -> OpponentDef:
	var def: OpponentDef = _def()
	def.hold_types = [&"tank"] as Array[StringName]
	return def


func _hold_level(on: int) -> AiDifficultyDef:
	var level: AiDifficultyDef = AiDifficultyDef.new()
	level.hold_in_waves = on
	return level


func _hold(holder: AiHold, world: World, memory: AiMemory) -> Array[Command]:
	memory.commands_left = 99
	var out: Array[Command] = []
	holder.run(PlayerView.of(world, 1), memory, out)
	return out
