extends GdUnitTestSuite
## The opponent AI's think cadence (plan row P198b, ADR 0030 section 2's note): period 3 and five
## slots, no think on a checkpoint tick for players 1 to 4, and what players 3 and 4 do.

const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")


func test_no_player_from_1_to_4_thinks_on_the_tick_that_ends_in_a_checkpoint() -> void:
	# A checkpoint hashes in the step that starts at tick % 15 == 14 (ADR 0030 section 2).
	for faction: String in ["fossil", "renew"]:
		for player: int in [1, 2, 3, 4]:
			var ai: OpponentAi = Rig.opponent(faction, "normal", player)
			assert_int(ai.think_period).is_equal(3)
			for tick: int in range(0, 600):
				if (tick + ai.think_offset) % ai.think_period == 0:
					(
						assert_int(tick % Replay.CHECKPOINT_PERIOD)
						. append_failure_message(
							"%s player %d thinks on tick %d" % [faction, player, tick]
						)
						. is_not_equal(Replay.CHECKPOINT_PERIOD - 1)
					)


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
