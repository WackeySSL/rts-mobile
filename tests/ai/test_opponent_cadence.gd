extends GdUnitTestSuite
## The opponent AI's think cadence (plan row P198b, ADR 0030 section 2's note): period 3 and five
## slots, what players 3 and 4 do, the army reading the refresh of the think before, and Easy's
## budget. (No think on a checkpoint tick is pinned in `test_opponent_def_data.gd`.)

const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const FactionRig: GDScript = preload("res://tests/ai/support/faction_rig.gd")


func test_players_1_and_2_never_think_on_the_same_tick_and_a_shared_tick_runs_two_slots() -> void:
	var ais: Array[OpponentAi] = []
	for player: int in [1, 2, 3, 4]:
		ais.append(Rig.opponent("fossil", "normal", player))
	for tick: int in range(0, 300):
		var thinking: Array[int] = []
		for ai: OpponentAi in ais:
			if (tick + ai.think_offset) % ai.think_period == 0:
				thinking.append(ai.player_id)
		# Two lanes of residues: at most one player of each lane thinks on a tick.
		assert_bool(thinking.size() <= 2).is_true()
		assert_bool(thinking.has(1) and thinking.has(2)).is_false()
		assert_bool(thinking.has(3) and thinking.has(4)).is_false()
		if thinking.size() == 2:
			assert_int(ais[thinking[0] - 1].slot_of(tick)).is_not_equal(
				ais[thinking[1] - 1].slot_of(tick)
			)
	# Players 3 and 4 share the residues of 1 and 2 and run two slots ahead.
	assert_array([ais[2].think_offset, ais[3].think_offset]).is_equal(
		[ais[0].think_offset, ais[1].think_offset]
	)
	(
		assert_array([ais[0].slot_shift, ais[1].slot_shift, ais[2].slot_shift, ais[3].slot_shift])
		. is_equal([0, 0, 2, 2])
	)


func test_every_army_think_follows_a_refresh_think_three_ticks_before_for_players_1_to_4() -> void:
	for player: int in [1, 2, 3, 4]:
		var ai: OpponentAi = Rig.opponent("fossil", "normal", player)
		var armies: int = 0
		for tick: int in range(3, 300):
			if (tick + ai.think_offset) % ai.think_period != 0:
				continue
			if ai.slot_of(tick) == OpponentAi.Slot.ARMY:
				armies += 1
				assert_int(ai.slot_of(tick - ai.think_period)).is_equal(OpponentAi.Slot.REFRESH)
		assert_int(armies).is_greater(15)


## Easy's "slow hands" (ADR 0030 section 6, cap 3): the economy and the production share one budget
## a round, as they did in one think; ARMY and INTEL have their own.
func test_easy_sends_at_most_its_cap_across_the_economy_and_production_thinks_of_a_round() -> void:
	var world: World = FactionRig.start("fossil", "renew")
	Power.run(world)
	world.credits[1] = 100000
	var loop: MatchLoop = AiRig.loop_of(world)
	var ai: OpponentAi = Rig.opponent("fossil", "easy", 1, 1)
	assert_int(ai.commands_per_think_max).is_equal(3)
	var economy: int = 0
	var rounds_at_cap: int = 0
	var production_sent: int = 0
	for _tick: int in 3000:
		var tick: int = world.tick
		var sent: Array[Command] = AiRig.tick(world, loop, [ai])
		if (tick + ai.think_offset) % ai.think_period != 0:
			continue
		match ai.last_slot:
			OpponentAi.Slot.ECONOMY:
				economy = sent.size()
			OpponentAi.Slot.PRODUCTION:
				assert_int(economy + sent.size()).is_less_equal(3)
				production_sent += sent.size()
				rounds_at_cap += 1 if economy + sent.size() == 3 else 0
			_:
				assert_int(sent.size()).is_less_equal(3)
	# Both managers wanted to send and the shared budget did bind in some round.
	assert_int(production_sent).is_greater(0)
	assert_int(rounds_at_cap).is_greater(0)
