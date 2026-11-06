extends GdUnitTestSuite
## The opponent AI's skeleton (plan row P175, ADR 0030 sections 1-3 and 8): the slot of every think
## from the tick, the factory, one code path for the levels, an empty think that counts one view,
## the cap on a think's Commands, the counters and the memory's "none" values. The managers' own
## suites come with their rows.

const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const FactionRig: GDScript = preload("res://tests/ai/support/faction_rig.gd")


func test_the_slot_of_every_think_follows_the_tick_in_the_order_economy_army_intel() -> void:
	for player: int in [1, 2, 3, 4]:
		var ai: OpponentAi = Rig.opponent("fossil", "normal", player)
		var previous: int = -1
		for tick: int in 300:
			if (tick + ai.think_offset) % ai.think_period != 0:
				continue
			assert_int(ai.slot_of(tick)).is_equal((tick + ai.think_offset) / 5 % 3)
			# Consecutive thinks rotate through the slots, whichever slot the first one has.
			if previous >= 0:
				assert_int(ai.slot_of(tick)).is_equal((previous + 1) % 3)
			previous = ai.slot_of(tick)
	# Player 1 thinks on tick 0 (slot 0), 5 (slot 1), 10 (slot 2), 15 (slot 0 again).
	var first: OpponentAi = Rig.opponent("fossil", "normal", 1)
	(
		assert_array([first.slot_of(0), first.slot_of(5), first.slot_of(10), first.slot_of(15)])
		. is_equal([0, 1, 2, 0])
	)


func test_a_manager_runs_once_in_fifteen_ticks_and_the_thinks_record_their_slot() -> void:
	var world: World = FactionRig.start("fossil", "fossil")
	var ai: OpponentAi = Rig.opponent("fossil", "normal", 2)
	var slots: Array[int] = []
	for tick: int in 60:
		world.tick = tick
		if (tick + ai.think_offset) % ai.think_period == 0:
			ai.think(PlayerView.of(world, 2), [] as Array[Command])
			slots.append(ai.last_slot)
	# Player 2's first think is on tick 1, which is the second slot of the round.
	assert_array(slots).is_equal([1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0])
	assert_array(ai.slot_thinks).is_equal(PackedInt32Array([4, 4, 4]))


func test_a_think_with_empty_managers_sends_nothing_and_counts_one_view() -> void:
	var world: World = FactionRig.start("fossil", "renew")
	var ai: OpponentAi = Rig.opponent("fossil", "normal", 1)
	var sent: Array[Command] = []
	for tick: int in 15:
		world.tick = tick
		ai.think(PlayerView.of(world, 1), sent)
		assert_int(ai.work).is_equal(1)
	assert_array(sent).is_empty()
	assert_array([ai.work_max, ai.commands, ai.commands_cut]).is_equal([1, 0, 0])
	assert_array([ai.waves, ai.retreats, ai.scouts, ai.strikes]).is_equal([0, 0, 0, 0])


func test_the_factory_returns_the_dummy_for_a_plain_def_and_the_opponent_for_an_opponent_def(
) -> void:
	var stream: DetRandom = DetRandom.create(3, DetRandom.STREAM_AI_BASE + 2)
	var dummy: AiController = AiFactory.create(AiRig.dummy_def(), null, 2, stream)
	assert_object(dummy).is_instanceof(DummyAi)
	assert_object(dummy.rng).is_same(stream)
	assert_int(dummy.player_id).is_equal(2)
	# The level is ignored for the dummy, even when given.
	var with_level: AiController = AiFactory.create(
		AiRig.dummy_def(), Rig.level_of("hard"), 2, stream
	)
	assert_object(with_level).is_instanceof(DummyAi)
	assert_int(with_level.think_period).is_equal(AiRig.dummy_def().think_period)
	var opponent: AiController = AiFactory.create(
		Rig.def_of("renew"), Rig.level_of("easy"), 3, stream
	)
	assert_object(opponent).is_instanceof(OpponentAi)
	assert_object(opponent.rng).is_same(stream)
	assert_array([opponent.player_id, opponent.think_period]).is_equal([3, 5])


func test_a_null_level_plays_as_normal() -> void:
	var stream: DetRandom = DetRandom.create(3, DetRandom.STREAM_AI_BASE + 2)
	var ai: OpponentAi = AiFactory.create(Rig.def_of("fossil"), null, 2, stream) as OpponentAi
	var normal: OpponentAi = Rig.opponent("fossil", "normal", 2)
	assert_array(_ints(ai)).is_equal(_ints(normal))


func test_the_same_seed_at_two_levels_gives_the_same_class_with_different_ints() -> void:
	var easy: AiController = AiFactory.create(
		Rig.def_of("fossil"),
		Rig.level_of("easy"),
		2,
		DetRandom.create(7, DetRandom.STREAM_AI_BASE + 2)
	)
	var hard: AiController = AiFactory.create(
		Rig.def_of("fossil"),
		Rig.level_of("hard"),
		2,
		DetRandom.create(7, DetRandom.STREAM_AI_BASE + 2)
	)
	assert_object(easy.get_script()).is_same(hard.get_script())
	assert_array([easy.think_period, easy.think_offset]).is_equal(
		[hard.think_period, hard.think_offset]
	)
	assert_array(_ints(easy)).is_not_equal(_ints(hard))
	assert_array(_ints(easy)).is_equal([0, 90, 3, 0])
	assert_array(_ints(hard)).is_equal([2, 15, 12, 1])


func test_the_controller_copies_its_defs_and_keeps_no_resource() -> void:
	var ai: OpponentAi = Rig.opponent("renew", "normal", 2)
	for property: Dictionary in ai.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var value: Variant = ai.get(property["name"])
		(
			assert_bool(value is Resource or value is Node)
			. override_failure_message("%s holds an object" % property["name"])
			. is_false()
		)
	assert_str(String(ai.def_id)).is_equal("opponent_renew")
	assert_str(String(ai.level_id)).is_equal("normal")


func test_a_think_sends_at_most_the_levels_commands_and_counts_the_cut() -> void:
	var world: World = FactionRig.start("fossil", "renew")
	var ai: OpponentAi = Rig.opponent("fossil", "easy", 1)
	assert_int(ai.commands_per_think_max).is_equal(3)
	# A probe subclass-free check of the cap: five Commands already in the list stay (they are not
	# this think's), and what a slot appends beyond the cap is cut.
	var probe: _Probe = _Probe.new()
	probe.copy_from(ai)
	probe.extra = 5
	var sent: Array[Command] = [Command.stop(1, PackedInt32Array())]
	probe.think(PlayerView.of(world, 1), sent)
	assert_int(sent.size()).is_equal(1 + 3)
	assert_array([probe.commands, probe.commands_cut]).is_equal([3, 2])
	probe.extra = 2
	probe.think(PlayerView.of(world, 1), sent)
	assert_int(sent.size()).is_equal(1 + 3 + 2)
	assert_array([probe.commands, probe.commands_cut]).is_equal([5, 2])


func test_the_memory_starts_at_its_none_values_within_the_defs_caps() -> void:
	var def: OpponentDef = Rig.def_of("fossil")
	var memory: AiMemory = AiMemory.create(def)
	assert_bool(memory.has_staging()).is_false()
	assert_bool(memory.has_base_estimate()).is_false()
	assert_array([memory.staging_x, memory.staging_y, memory.base_x, memory.base_y]).is_equal(
		[-1, -1, -1, -1]
	)
	assert_array([memory.scout_id, memory.wave_start_tick, memory.threat_first_tick]).is_equal(
		[-1, -1, -1]
	)
	assert_array([memory.wave_count, memory.scout_waypoint, memory.spiral_resume]).is_equal(
		[0, 0, 0]
	)
	assert_int(memory.squad_role.size()).is_equal(def.squads_max)
	assert_int(memory.sector_own.size()).is_equal(def.sectors_max)
	assert_int(memory.sector_enemy.size()).is_equal(def.sectors_max)
	for at: int in def.squads_max:
		assert_int(memory.squad_role[at]).is_equal(AiMemory.NONE)
	assert_int(memory.goal_keys()).is_equal(0)
	assert_array([memory.member_id.size(), memory.hp_id.size()]).is_equal([0, 0])


func test_the_goal_keys_are_capped_and_a_live_key_is_not_added_twice() -> void:
	var memory: AiMemory = AiMemory.create(Rig.def_of("fossil"))
	assert_bool(memory.add_goal_key(10, 12, 2)).is_true()
	assert_bool(memory.add_goal_key(10, 12, 2)).is_true()
	assert_int(memory.goal_keys()).is_equal(1)
	assert_bool(memory.add_goal_key(10, 12, 0)).is_true()
	assert_bool(memory.add_goal_key(20, 20, 2)).is_true()
	assert_bool(memory.add_goal_key(20, 20, 0)).is_true()
	assert_int(memory.goal_keys()).is_equal(4)
	assert_bool(memory.add_goal_key(30, 30, 2)).is_false()
	assert_int(memory.goal_keys()).is_equal(4)
	memory.clear_goal_keys()
	assert_int(memory.goal_keys()).is_equal(0)


func test_a_think_records_the_rules_unit_cap_in_the_memory() -> void:
	var world: World = FactionRig.start("fossil", "renew")
	var ai: OpponentAi = Rig.opponent("fossil", "normal", 1)
	ai.think(PlayerView.of(world, 1), [] as Array[Command])
	assert_int(ai.memory.unit_cap).is_greater(0)
	assert_int(ai.memory.unit_cap).is_equal(PlayerView.of(world, 1).unit_cap)


func test_an_opponent_in_the_headless_loop_sends_nothing_yet_and_drops_nothing() -> void:
	var world: World = FactionRig.start("fossil", "renew")
	var loop: MatchLoop = AiRig.loop_of(world)
	var controllers: Array = [Rig.opponent("fossil", "normal", 1), Rig.opponent("renew", "hard", 2)]
	var sent: Array[Command] = AiRig.run(world, loop, controllers, 150)
	assert_array(sent).is_empty()
	assert_int(world.dropped_commands).is_equal(0)
	for controller: OpponentAi in controllers:
		assert_array(controller.slot_thinks).is_equal(PackedInt32Array([10, 10, 10]))


func test_the_dummy_counts_its_commands_and_nothing_else() -> void:
	var world: World = AiRig.start()
	var loop: MatchLoop = AiRig.loop_of(world)
	var dummy: DummyAi = AiRig.dummy(2)
	var sent: Array[Command] = AiRig.run(world, loop, [dummy], 60)
	assert_int(sent.size()).is_greater(0)
	assert_int(dummy.commands).is_equal(sent.size())
	(
		assert_array(
			[dummy.work, dummy.work_max, dummy.waves, dummy.retreats, dummy.scouts, dummy.strikes]
		)
		. is_equal([0, 0, 0, 0, 0, 0])
	)


## The ints a level sets: tier, reaction delay, Commands per think and the strike flag.
func _ints(ai: OpponentAi) -> Array:
	return [ai.tier, ai.reaction_ticks, ai.commands_per_think_max, ai.uses_strike]


## A controller whose ECONOMY slot appends `extra` Commands, to test the cap on a think.
class _Probe:
	extends OpponentAi
	var extra: int = 0

	func copy_from(other: OpponentAi) -> void:
		player_id = other.player_id
		think_period = other.think_period
		think_offset = other.think_offset
		memory = other.memory
		commands_per_think_max = other.commands_per_think_max

	func _run_economy_slot(_view: PlayerView, out: Array[Command]) -> void:
		for _i: int in extra:
			out.append(Command.stop(player_id, PackedInt32Array()))
