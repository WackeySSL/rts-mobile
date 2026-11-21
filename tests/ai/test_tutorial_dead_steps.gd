extends GdUnitTestSuite
## A step of the scripted enemy whose units are all gone counts as fired (plan row P543e), so the
## card that waits for it still shows and the lesson goes on. In each lesson the player kills every
## unit the step would send before the beat it waits for; the director, on the lesson's own match,
## shows the gated card and ends the lesson. The three waves were stuck here before: no unit, no
## Command, no `has_fired`, no card.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const Tut: GDScript = preload("res://tests/ai/support/tutorial_rig.gd")
const Lesson: GDScript = preload("res://tests/ui/tutorial/support/lesson_rig.gd")
const LESSON_DIR: String = "res://data/tutorial/"
const FOE: int = 2
const NEXT: TutorialConditions.Kind = TutorialConditions.Kind.NEXT
## Ticks played before the units die, and the ticks the lesson is given to go on.
const BEFORE: int = 300
const WAIT: int = 120

var _dir: String = ""


func before_test() -> void:
	_dir = "user://test_dead_steps_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	SaveService.set_path_override(_dir.path_join("save.cfg"))


func after_test() -> void:
	SaveService.clear_path_override()
	for file_name: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file_name))
	DirAccess.remove_absolute(_dir)
	CommandQueue.clear()


func test_basics_goes_on_when_the_wave_has_no_squad_left() -> void:
	_goes_on(&"basics", &"groups", &"incoming", &"wave", &"renew_rifle")


func test_air_goes_on_when_the_raider_is_shot_down() -> void:
	_goes_on(&"air", &"home", &"raid", &"raid", &"renew_fighter")


func test_support_goes_on_when_the_squads_are_all_killed() -> void:
	_goes_on(&"support", &"sell-last", &"poke", &"poke", &"renew_rifle")


## The rule in the AI alone: squads that were seen and are all dead make the step fired with no
## Command; squads that were never there (not trained yet) are waited for, as before.
func test_a_step_whose_units_were_seen_and_died_fires_with_no_command() -> void:
	var def: TutorialScriptDef = TutorialScriptDef.new()
	(
		def
		. steps
		. append(
			(
				Tut
				. step(
					"go",
					TutorialStepDef.Trigger.TICK,
					TutorialStepDef.Action.ATTACK_MOVE,
					{
						"threshold": 30,
						"action_type": &"rifle_squad",
						"target": TutorialStepDef.Target.TILE,
						"target_tile": Vector2i(5, 6),
					}
				)
			)
		)
	)
	var world: World = Tut.start()
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: TutorialAi = Tut.ai_of(def)
	assert_array(Tut.think(world, ai)).is_empty()  # Tick 0: the squads are seen, the clock is not.
	for row: int in world.unit_count():
		if (
			world.owner[row] == Tut.PLAYER
			and world.type_ids[world.type_index[row]] == &"rifle_squad"
		):
			world.hp[row] = 0
	for _i: int in 31:
		Rig.step(world, loop)
	assert_array(Tut.think(world, ai)).is_empty()
	assert_bool(ai.has_fired(&"go")).is_true()


## The dead step is no early exit: with its squads alive the step still waits for its beat and
## sends them.
func test_a_step_with_units_left_still_sends_them() -> void:
	var runner: MatchRunner = _runner(&"support")
	runner.run_ticks(BEFORE)
	var ai: TutorialAi = runner.controller_of(FOE) as TutorialAi
	assert_bool(ai.has_fired(&"poke")).is_false()
	ai.note_beat(&"sell-last", BEFORE)
	runner.run_ticks(WAIT)
	assert_bool(ai.has_fired(&"poke")).is_true()
	assert_int(runner.replay.commands.size()).is_greater(0)


## `id`'s match to BEFORE ticks, the enemy's `foe_type` units killed, then a director on a lesson of
## two fixture beats (`prev`, done by Next, and `card`, which waits for `step`): the card shows and
## the lesson ends.
func _goes_on(
	id: StringName, prev: StringName, card: StringName, step: StringName, foe_type: StringName
) -> void:
	var runner: MatchRunner = _runner(id)
	runner.run_ticks(BEFORE)
	var world: World = runner.world
	var type: int = world.type_ids.find(foe_type)
	var killed: int = 0
	for row: int in world.unit_count():
		if world.owner[row] == FOE and world.type_index[row] == type:
			world.hp[row] = 0
			killed += 1
	assert_int(killed).override_failure_message(String(id)).is_greater(0)
	runner.run_ticks(5)  # They are removed.
	var director: TutorialDirector = auto_free(TutorialDirector.new())
	director.runner = runner
	var done: Array[StringName] = []
	director.lesson_done.connect(func(lesson_id: StringName) -> void: done.append(lesson_id))
	var gated: TutorialBeatDef = Lesson.beat(String(card), NEXT, {"after_ai_step": step})
	director.start(Lesson.lesson(String(id), [Lesson.beat(String(prev), NEXT), gated]))
	director.advance()
	assert_bool(director.next()).is_true()
	var shown: bool = false
	for _tick: int in WAIT:
		runner.run_ticks(1)
		director.advance()
		if director.current != null and director.current.id == card:
			shown = true
			break
	(
		assert_bool(shown)
		. override_failure_message("%s: the card %s never showed" % [id, card])
		. is_true()
	)
	assert_bool((runner.controller_of(FOE) as TutorialAi).has_fired(step)).is_true()
	assert_bool(director.next()).is_true()
	assert_array(done).is_equal([id])


func _runner(id: StringName) -> MatchRunner:
	var lesson: TutorialLessonDef = load("%s%s.tres" % [LESSON_DIR, id]) as TutorialLessonDef
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = lesson.scenario
	runner.match_seed = lesson.match_seed
	runner.tick_mode = MatchRunner.TickMode.SYNC
	runner.opponents = [lesson.enemy]
	runner.start()
	return runner
