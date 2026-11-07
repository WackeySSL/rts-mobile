extends GdUnitTestSuite
## A whole Normal-vs-Normal match of `OpponentAi` (plan row P180, seed 1): it runs to its end or to
## 13 500 ticks, and the sim must have dropped none of the Commands the two AIs sent. Its end, its
## length and who wins are NOT asserted: the balance run judges those (so tuning cannot turn
## verify red).

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
	for _tick: int in TICKS:
		if world.match_end_tick > 0:
			break
		AiRig.tick(world, loop, ais)
	assert_int(world.dropped_commands).is_equal(0)
