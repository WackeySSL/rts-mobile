extends GdUnitTestSuite
## Easy is as it was (plan row P250e): its level file has every group field at 0, so a whole Easy
## mirror match with the all-in pulled forward gathers, halts and closes nothing, and its wave still
## sends every unit one by one after the all-in.

const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const FactionRig: GDScript = preload("res://tests/ai/support/faction_rig.gd")
const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const TICKS: int = 3000
const ALL_IN: int = 600
## The state hash and the Commands sent of this match at 7682046e, before the group fields existed:
## Easy must play it the same.
const EASY_HASH: String = "b3e06ef2e3708a20"
const EASY_SENT: int = 72


func _ai(level: AiDifficultyDef, player: int) -> OpponentAi:
	var stream: DetRandom = DetRandom.create(1, DetRandom.STREAM_AI_BASE + player)
	return OpponentAi.create(Rig.def_of("fossil"), level, player, stream)


## An Easy copy with the all-in at `ALL_IN` and the first wave early, so the wave logic runs.
func _early(base: AiDifficultyDef) -> AiDifficultyDef:
	var level: AiDifficultyDef = base.duplicate() as AiDifficultyDef
	level.all_in_tick = ALL_IN
	level.wave_first_tick = 300
	level.wave_first_strength = 200
	return level


func _play(level: AiDifficultyDef) -> Array:
	var world: World = FactionRig.start("fossil", "fossil")
	var loop: MatchLoop = AiRig.loop_of(world, 1)
	var ais: Array = [_ai(level, 1), _ai(level, 2)]
	var sent: int = 0
	for _tick: int in TICKS:
		if world.match_end_tick > 0:
			break
		sent += AiRig.tick(world, loop, ais).size()
	return [ais, World.hash_hex(world.state_hash()), sent]


func test_an_easy_match_with_the_all_in_early_uses_no_group_rule() -> void:
	var played: Array = _play(_early(Rig.level_of("easy")))
	var ais: Array = played[0]
	for ai: OpponentAi in ais:
		assert_array(ai.army.group_stats()).is_equal([0, 0, 0, 0])
		assert_int(ai.army.waves).is_greater(0)


func test_an_easy_match_is_the_match_it_was_before_the_group_fields() -> void:
	var played: Array = _play(_early(Rig.level_of("easy")))
	assert_array([played[1], played[2]]).is_equal([EASY_HASH, EASY_SENT])


func test_normal_with_the_same_early_all_in_does_use_them() -> void:
	var level: AiDifficultyDef = _early(Rig.level_of("normal"))
	var played: Array = _play(level)
	var total: int = 0
	for ai: OpponentAi in played[0]:
		for count: int in ai.army.group_stats():
			total += count
	assert_int(total).is_greater(0)


func test_zeroing_the_group_fields_of_normal_makes_it_play_as_easy_does_here() -> void:
	var level: AiDifficultyDef = _early(Rig.level_of("normal"))
	level.group_min_size = 0
	level.wave_regroup_spread_tiles = 0
	level.wave_lead_percent = 0
	var played: Array = _play(level)
	for ai: OpponentAi in played[0]:
		assert_array(ai.army.group_stats()).is_equal([0, 0, 0, 0])
