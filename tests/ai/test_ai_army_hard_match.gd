extends GdUnitTestSuite
## A whole Hard-vs-Hard match of `OpponentAi` (plan row P180b, seed 1): the unit control (the
## step-back and the focus fire) runs on the shipped Hard level. It runs to its end or to 13 500
## ticks, and the sim must have dropped none of the Commands the two AIs sent (so the step-back
## `MOVE`s and the focus `ATTACK`s pass the sim's validation). Its end, its length and who wins
## are NOT asserted: the balance run judges those. Two asserts are seed-1 pins under exception 20:
## that step-backs and focus orders happen at all; a tuning row that zeroes one changes the seed
## and lists it. Every think it checks the bounds no tuning can move: the goal keys within the cap
## and the army's and the staging's within two, no Command cut, the tests within the def's, the
## work within 3 and the step-back list within the AI's own unit count (after the ARMY slot).

const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const FactionRig: GDScript = preload("res://tests/ai/support/faction_rig.gd")
const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const TICKS: int = 13500
const SEED: int = 1


func test_a_hard_mirror_match_drops_no_command_and_keeps_every_bound() -> void:
	var world: World = FactionRig.start("fossil", "fossil")
	var loop: MatchLoop = AiRig.loop_of(world, SEED)
	var ais: Array = [
		Rig.opponent("fossil", "hard", 1, SEED), Rig.opponent("fossil", "hard", 2, SEED)
	]
	var cap: int = Rig.def_of("fossil").target_tests_max
	for _tick: int in TICKS:
		if world.match_end_tick > 0:
			break
		var thought: int = world.tick
		AiRig.tick(world, loop, ais)
		for ai: OpponentAi in ais:
			assert_int(ai.memory.goal_keys()).is_less_equal(ai.memory.goal_keys_max)
			assert_int(ai.memory.goal_keys_of(AiMemory.Owner.ARMY)).is_less_equal(2)
			assert_int(ai.memory.goal_keys_of(AiMemory.Owner.STAGING)).is_less_equal(2)
			assert_int(ai.commands_cut).is_equal(0)
			assert_int(ai.army.tests).is_less_equal(cap)
			# The army prunes the list against the lists of the REFRESH slot before it (P198b), so
			# the bound holds after the ARMY slot's think and, between a refresh and it, only the
			# unit cap does.
			assert_int(ai.memory.withdrawn_id.size()).is_less_equal(ai.memory.unit_cap)
			if (
				(thought + ai.think_offset) % ai.think_period == 0
				and ai.last_slot == OpponentAi.Slot.ARMY
			):
				assert_int(ai.memory.withdrawn_id.size()).is_less_equal(ai.memory.unit_id.size())
	assert_int(world.dropped_commands).is_equal(0)
	for ai: OpponentAi in ais:
		assert_int(ai.work_max).is_less_equal(3)
	# The control ran: the fights of 13 500 ticks hold orders of both kinds (seed 1).
	assert_int(ais[0].army.stepbacks + ais[1].army.stepbacks).is_greater(0)
	assert_int(ais[0].army.focuses + ais[1].army.focuses).is_greater(0)
