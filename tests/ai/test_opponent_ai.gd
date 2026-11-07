extends GdUnitTestSuite
## The opponent AI's skeleton (plan row P175, ADR 0030 sections 1-3 and 8): the slot of every think
## from the tick, the factory, one code path for the levels, an empty think that counts one view,
## the cap on a think's Commands, the counters and the memory's "none" values. The managers' own
## suites come with their rows.

const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const FactionRig: GDScript = preload("res://tests/ai/support/faction_rig.gd")
const Probe: GDScript = preload("res://tests/ai/support/opponent_probe.gd")


func test_the_slot_of_every_think_follows_the_tick_in_the_order_economy_army_intel() -> void:
	for player: int in [1, 2, 3, 4]:
		var ai: OpponentAi = Rig.opponent("fossil", "normal", player)
		var previous: int = -1
		for tick: int in 300:
			if (tick + ai.think_offset) % ai.think_period != 0:
				continue
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
	# The probe's hooks stand for managers with nothing to do (the real managers have their suites).
	var ai: Variant = Probe.new()
	ai.copy_from(Rig.opponent("fossil", "normal", 1))
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
	assert_array(_ints(easy)).is_equal([0, 3])
	assert_array(_ints(hard)).is_equal([2, 12])


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


func test_each_slot_runs_its_own_hook_whichever_player_thinks() -> void:
	var world: World = FactionRig.start("fossil", "renew")
	# Players 2 and 3 think on ticks 1, 6, 11 and 2, 7, 12 of the round: ARMY, INTEL, ECONOMY.
	for player: int in [2, 3]:
		var probe: Variant = Probe.new()
		probe.copy_from(Rig.opponent("fossil", "normal", player))
		var ticks: Array[int] = [player - 1, player + 4, player + 9]
		for tick: int in ticks:
			world.tick = tick
			probe.think(PlayerView.of(world, player), [] as Array[Command])
		assert_array(probe.ran).is_equal(
			[OpponentAi.Slot.ARMY, OpponentAi.Slot.INTEL, OpponentAi.Slot.ECONOMY]
		)
	# Player 1 starts on slot ECONOMY at tick 0.
	var first: Variant = Probe.new()
	first.copy_from(Rig.opponent("fossil", "normal", 1))
	for tick: int in [0, 5, 10]:
		world.tick = tick
		first.think(PlayerView.of(world, 1), [] as Array[Command])
	assert_array(first.ran).is_equal(
		[OpponentAi.Slot.ECONOMY, OpponentAi.Slot.ARMY, OpponentAi.Slot.INTEL]
	)


func test_the_guard_keeps_the_first_commands_in_order_and_counts_the_cut() -> void:
	var world: World = FactionRig.start("fossil", "renew")
	var ai: OpponentAi = Rig.opponent("fossil", "easy", 1)
	assert_int(ai.commands_per_think_max).is_equal(3)
	var probe: Variant = Probe.new()
	probe.copy_from(ai)
	probe.extra = 5
	# One Command already in the list (not this think's) stays; of the five, the first three stay.
	var sent: Array[Command] = [Command.stop(1, PackedInt32Array([99]))]
	probe.think(PlayerView.of(world, 1), sent)
	assert_array(_unit_ids(sent)).is_equal([99, 1, 2, 3])
	assert_array([probe.commands, probe.commands_cut]).is_equal([3, 2])
	probe.extra = 2
	probe.think(PlayerView.of(world, 1), sent)
	assert_array(_unit_ids(sent)).is_equal([99, 1, 2, 3, 1, 2])
	assert_array([probe.commands, probe.commands_cut]).is_equal([5, 2])


func test_a_manager_that_checks_the_budget_is_never_cut() -> void:
	var world: World = FactionRig.start("fossil", "renew")
	var probe: Variant = Probe.new()
	probe.copy_from(Rig.opponent("fossil", "easy", 1))
	probe.extra = 5
	probe.polite = true
	var sent: Array[Command] = []
	probe.think(PlayerView.of(world, 1), sent)
	assert_array(_unit_ids(sent)).is_equal([1, 2, 3])
	assert_array([probe.commands, probe.commands_cut, probe.memory.commands_left]).is_equal(
		[3, 0, 0]
	)
	# The budget is set again at the start of the next think.
	probe.think(PlayerView.of(world, 1), sent)
	assert_int(sent.size()).is_equal(6)
	assert_int(probe.commands_cut).is_equal(0)


func test_a_negative_cap_is_clamped_and_never_cuts_commands_already_in_the_list() -> void:
	var world: World = FactionRig.start("fossil", "renew")
	var level: AiDifficultyDef = Rig.level_of("easy").duplicate() as AiDifficultyDef
	level.commands_per_think_max = -2
	var ai: OpponentAi = OpponentAi.create(
		Rig.def_of("fossil"), level, 1, DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1)
	)
	assert_int(ai.commands_per_think_max).is_equal(0)
	var probe: Variant = Probe.new()
	probe.copy_from(ai)
	probe.extra = 2
	var sent: Array[Command] = [Command.stop(1, PackedInt32Array([99]))]
	probe.think(PlayerView.of(world, 1), sent)
	assert_array(_unit_ids(sent)).is_equal([99])
	assert_int(probe.commands_cut).is_equal(2)


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
	(
		assert_array(
			[
				memory.wave_count,
				memory.scout_waypoint,
				memory.spiral_resume,
				memory.spiral_for_x,
				memory.spiral_for_y
			]
		)
		. is_equal([0, 0, 0, -1, -1])
	)
	assert_int(memory.squad_role.size()).is_equal(def.squads_max)
	assert_int(memory.sector_own.size()).is_equal(def.sectors_max)
	assert_int(memory.sector_enemy.size()).is_equal(def.sectors_max)
	for at: int in def.squads_max:
		assert_int(memory.squad_role[at]).is_equal(AiMemory.NONE)
	assert_int(memory.goal_keys()).is_equal(0)
	assert_array([memory.member_id.size(), memory.hp_id.size()]).is_equal([0, 0])


func test_the_caps_come_from_their_own_def_fields() -> void:
	var def: OpponentDef = Rig.def_of("fossil").duplicate() as OpponentDef
	def.goal_keys_max = 3
	def.squads_max = 5
	def.sectors_max = 7
	var memory: AiMemory = AiMemory.create(def)
	assert_array([memory.goal_keys_max, memory.squads_max, memory.sectors_max]).is_equal([3, 5, 7])
	assert_array([memory.squad_role.size(), memory.sector_own.size()]).is_equal([5, 7])
	assert_bool(memory.add_goal_key(10, 12, 2, AiMemory.Owner.ARMY)).is_true()
	assert_bool(memory.add_goal_key(10, 12, 2, AiMemory.Owner.ARMY)).is_true()
	assert_int(memory.goal_keys()).is_equal(1)
	assert_bool(memory.add_goal_key(10, 12, 0, AiMemory.Owner.ARMY)).is_true()
	assert_bool(memory.add_goal_key(20, 20, 2, AiMemory.Owner.ARMY)).is_true()
	assert_int(memory.goal_keys()).is_equal(3)
	assert_bool(memory.add_goal_key(20, 20, 0, AiMemory.Owner.ARMY)).is_false()
	assert_int(memory.goal_keys()).is_equal(3)
	memory.clear_goal_keys()
	assert_array([memory.goal_keys(), memory.goal_owner.size()]).is_equal([0, 0])


func test_goal_keys_keep_every_owner_and_go_when_the_last_releases() -> void:
	var memory: AiMemory = AiMemory.create(Rig.def_of("fossil"))
	var staging: int = AiMemory.Owner.STAGING
	var army: int = AiMemory.Owner.ARMY
	var scout: int = AiMemory.Owner.SCOUT
	memory.add_goal_key(5, 5, 2, staging)
	memory.add_goal_key(30, 30, 2, army)
	# The scout shares the army's key: one key, two owners.
	memory.add_goal_key(30, 30, 2, scout)
	memory.add_goal_key(12, 40, 2, scout)
	assert_int(memory.goal_keys()).is_equal(3)
	assert_array([memory.goal_keys_of(staging), memory.goal_keys_of(army)]).is_equal([1, 1])
	assert_int(memory.goal_keys_of(scout)).is_equal(2)
	# The army releases its goal: the scout keeps the shared key.
	memory.release_goal_key(1, army)
	assert_int(memory.goal_keys()).is_equal(3)
	assert_array([memory.goal_keys_of(army), memory.goal_keys_of(scout)]).is_equal([0, 2])
	# The scout releases it too: the key goes, in every parallel array, the others keep their order.
	memory.release_goal_key(1, scout)
	assert_int(memory.goal_keys()).is_equal(2)
	assert_array(memory.goal_x).is_equal(PackedInt32Array([5, 12]))
	assert_array(memory.goal_owner).is_equal(PackedInt32Array([1 << staging, 1 << scout]))
	assert_array([memory.goal_y.size(), memory.goal_class.size()]).is_equal([2, 2])
	memory.release_goal_key(7, army)
	memory.release_goal_key(-1, army)
	assert_int(memory.goal_keys()).is_equal(2)


func test_a_shared_key_never_passes_the_cap_and_a_new_key_is_refused_when_full() -> void:
	var def: OpponentDef = Rig.def_of("fossil").duplicate() as OpponentDef
	def.goal_keys_max = 2
	var memory: AiMemory = AiMemory.create(def)
	assert_bool(memory.add_goal_key(1, 1, 0, AiMemory.Owner.ARMY)).is_true()
	assert_bool(memory.add_goal_key(2, 2, 0, AiMemory.Owner.STAGING)).is_true()
	assert_bool(memory.add_goal_key(3, 3, 0, AiMemory.Owner.SCOUT)).is_false()
	# A full cache still lets the scout use a key that is live.
	assert_bool(memory.add_goal_key(1, 1, 0, AiMemory.Owner.SCOUT)).is_true()
	assert_int(memory.goal_keys()).is_equal(2)
	assert_int(memory.goal_keys_of(AiMemory.Owner.SCOUT)).is_equal(1)


func test_the_command_budget_and_the_credit_reserve_start_empty() -> void:
	var memory: AiMemory = AiMemory.create(Rig.def_of("fossil"))
	assert_bool(memory.can_send()).is_false()
	memory.commands_left = 2
	assert_bool(memory.can_send(2)).is_true()
	assert_bool(memory.can_send(3)).is_false()
	memory.spent(2)
	assert_bool(memory.can_send()).is_false()
	memory.spent()
	assert_int(memory.commands_left).is_equal(0)
	assert_int(memory.reserve_credits).is_equal(0)


func test_a_think_records_the_rules_unit_cap_in_the_memory() -> void:
	var world: World = FactionRig.start("fossil", "renew")
	var ai: OpponentAi = Rig.opponent("fossil", "normal", 1)
	ai.think(PlayerView.of(world, 1), [] as Array[Command])
	assert_int(ai.memory.unit_cap).is_greater(0)
	assert_int(ai.memory.unit_cap).is_equal(PlayerView.of(world, 1).unit_cap)


func test_an_opponent_in_the_headless_loop_sends_only_economy_commands_and_drops_nothing() -> void:
	var world: World = FactionRig.start("fossil", "renew")
	var loop: MatchLoop = AiRig.loop_of(world)
	var controllers: Array = [Rig.opponent("fossil", "normal", 1), Rig.opponent("renew", "hard", 2)]
	var sent: Array[Command] = AiRig.run(world, loop, controllers, 150)
	# Only the economy is wired so far (P176): it queues and places, nothing else.
	assert_array(sent).is_not_empty()
	for command: Command in sent:
		assert_bool([Command.Type.QUEUE, Command.Type.PLACE].has(command.type)).is_true()
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


## The ints a level sets in the controller: build-order tier and Commands per think.
func _ints(ai: OpponentAi) -> Array:
	return [ai.tier, ai.commands_per_think_max]


func _unit_ids(commands: Array[Command]) -> Array[int]:
	var ids: Array[int] = []
	for command: Command in commands:
		ids.append(command.unit_ids[0])
	return ids
