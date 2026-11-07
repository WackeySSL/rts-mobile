extends GdUnitTestSuite
## A whole Normal-vs-Normal match of `OpponentAi` (plan row P180, seed 1): it runs to its end or to
## 13 500 ticks, and the sim must have dropped none of the Commands the two AIs sent. Its end, its
## length, who wins and how many waves it holds are NOT asserted: the balance run judges those (so
## tuning cannot turn verify red). Every think it also checks the bounds no tuning can move: the
## goal keys within the cap and the army's within two, no Command cut, the tests within the def's.

const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const FactionRig: GDScript = preload("res://tests/ai/support/faction_rig.gd")
const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const TICKS: int = 13500
const SEED: int = 1


func test_a_normal_mirror_match_drops_no_command() -> void:
	var world: World = FactionRig.start("fossil", "fossil")
	var loop: MatchLoop = AiRig.loop_of(world, SEED)
	var ais: Array = [
		Rig.opponent("fossil", "normal", 1, SEED), Rig.opponent("fossil", "normal", 2, SEED)
	]
	var cap: int = Rig.def_of("fossil").target_tests_max
	for _tick: int in TICKS:
		if world.match_end_tick > 0:
			break
		AiRig.tick(world, loop, ais)
		for ai: OpponentAi in ais:
			assert_int(ai.memory.goal_keys()).is_less_equal(ai.memory.goal_keys_max)
			assert_int(ai.memory.goal_keys_of(AiMemory.Owner.ARMY)).is_less_equal(2)
			assert_int(ai.commands_cut).is_equal(0)
			assert_int(ai.army.tests).is_less_equal(cap)
	assert_int(world.dropped_commands).is_equal(0)
