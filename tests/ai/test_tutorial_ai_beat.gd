extends GdUnitTestSuite
## The `BEAT` trigger of `TutorialAi` (plan row P543c): a step that waits for the player's progress.
## The director tells the script a beat is done (`note_beat`, with the tick); the step fires on the
## first think at or after that tick plus its threshold, and never before the beat is noted.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const Tut: GDScript = preload("res://tests/ai/support/tutorial_rig.gd")
const AFTER: int = 30


func test_a_beat_step_waits_for_the_note_and_then_for_its_delay() -> void:
	var world: World = Tut.start()
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: TutorialAi = Tut.ai_of(_def())
	_run(world, loop, 200)
	Tut.think(world, ai)
	assert_bool(ai.has_fired(&"go")).is_false()  # No clock opens it.
	ai.note_beat(&"groups", world.tick)
	var noted: int = world.tick
	_run(world, loop, AFTER - 1)
	Tut.think(world, ai)
	assert_bool(ai.has_fired(&"go")).is_false()  # One tick short.
	_run(world, loop, 1)
	assert_int(Tut.think(world, ai).size()).is_greater(0)
	assert_int(ai.fired_tick_of(&"go")).is_equal(noted + AFTER)


func test_a_beat_is_noted_once_and_only_when_a_step_waits_for_it() -> void:
	var world: World = Tut.start()
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: TutorialAi = Tut.ai_of(_def())
	ai.note_beat(&"unrelated", 5)  # No step waits for it: it is not kept.
	ai.note_beat(&"groups", 100)
	ai.note_beat(&"groups", 3)  # The first word stands.
	assert_array(ai._noted_ids).is_equal([&"groups"])
	assert_array(Array(ai._noted_at)).is_equal([100])
	_run(world, loop, 100 + AFTER - 1)
	Tut.think(world, ai)
	# The second word (tick 3) would have opened it long ago; the first (100) not yet.
	assert_bool(ai.has_fired(&"go")).is_false()
	_run(world, loop, 1)
	Tut.think(world, ai)
	assert_int(ai.fired_tick_of(&"go")).is_equal(100 + AFTER)


func test_the_same_beat_ticks_give_the_same_commands() -> void:
	var logs: Array = []
	for _run_number: int in 2:
		var world: World = Tut.start()
		var loop: MatchLoop = Rig.loop_of(world)
		var ai: TutorialAi = Tut.ai_of(_def())
		ai.note_beat(&"groups", 20)
		var sent: int = 0
		for _tick: int in 80:
			sent += Tut.think(world, ai).size()
			Rig.step(world, loop)
		logs.append(sent)
		logs.append(ai.fired_tick_of(&"go"))
	assert_array(logs.slice(0, 2)).is_equal(logs.slice(2, 4))
	assert_int(logs[1]).is_equal(20 + AFTER)


func _def() -> TutorialScriptDef:
	var def: TutorialScriptDef = TutorialScriptDef.new()
	def.id = &"beat_test"
	(
		def
		. steps
		. append(
			(
				Tut
				. step(
					"go",
					TutorialStepDef.Trigger.BEAT,
					TutorialStepDef.Action.ATTACK_MOVE,
					{
						"trigger_beat": &"groups",
						"threshold": AFTER,
						"target": TutorialStepDef.Target.TILE,
						"target_tile": Vector2i(20, 20),
					}
				)
			)
		)
	)
	return def


func _run(world: World, loop: MatchLoop, ticks: int) -> void:
	for _i: int in ticks:
		Rig.step(world, loop)
