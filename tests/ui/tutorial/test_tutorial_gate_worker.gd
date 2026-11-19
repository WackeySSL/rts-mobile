extends GdUnitTestSuite
## The director's gate on a WORKER runner with the AI on its own thread (plan row P543, ADR 0038
## section 2, ADR 0044 section 2): the director reads the scripted opponent only on a published
## tick, after `wait_idle()`, and through `MatchRunner.controller_of`; it never holds a
## controller. The beat's prompt shows after the step has fired and never before, whatever the two
## threads do.
## A thread suite: it runs three times in a row (CLAUDE.md). The runner is built the Phase 1 way
## (auto_free, never in the tree) and played by frames.

const DummyStart: GDScript = preload("res://tests/core/support/dummy_start.gd")
const Tut: GDScript = preload("res://tests/ai/support/tutorial_rig.gd")
const Lesson: GDScript = preload("res://tests/ui/tutorial/support/lesson_rig.gd")
const FOE: int = 2
const FRAME: float = 0.07
const FRAMES_MAX: int = 400
const GO_TICK: int = 30

var _runner: MatchRunner
var _director: TutorialDirector
var _shown: Array[int] = []


func before_test() -> void:
	_shown.clear()
	CommandQueue.clear()


func after_test() -> void:
	if is_instance_valid(_runner):
		assert_bool(_runner.wait_idle()).is_true()
	CommandQueue.clear()


func test_a_beat_shows_after_the_step_fired_on_a_worker_runner_with_the_ai_thread() -> void:
	_start(MatchRunner.TickMode.WORKER)
	assert_bool(_runner._ai_thread != null and _runner._ai_thread.is_started()).is_true()
	var frames: int = _play_until_shown()
	assert_int(frames).is_less(FRAMES_MAX)
	assert_int(_shown.size()).is_equal(1)
	assert_bool(_runner.wait_idle()).is_true()
	var ai: TutorialAi = _runner.controller_of(FOE) as TutorialAi
	assert_object(ai).is_not_null()
	assert_int(ai.fired_tick_of(&"go")).is_greater_equal(GO_TICK)
	# The prompt is up on a tick at or after the one the step fired on, never before.
	assert_int(_shown[0]).is_greater_equal(ai.fired_tick_of(&"go"))


## SYNC reads the same: the gate opens on the tick after the step fired.
func test_the_same_gate_opens_in_sync_mode() -> void:
	_start(MatchRunner.TickMode.SYNC)
	var frames: int = _play_until_shown()
	assert_int(frames).is_less(FRAMES_MAX)
	var ai: TutorialAi = _runner.controller_of(FOE) as TutorialAi
	assert_int(ai.fired_tick_of(&"go")).is_greater_equal(GO_TICK)  # It did fire, on its clock.
	assert_int(_shown[0]).is_greater_equal(ai.fired_tick_of(&"go"))


## A new match under the lesson ends it, and the director holds no controller of the old one: the
## next lesson on the same runner reads the new match's opponent.
func test_a_restarted_runner_gives_the_director_its_new_opponent() -> void:
	_start(MatchRunner.TickMode.SYNC)
	_play_until_shown()
	var old: TutorialAi = _runner.controller_of(FOE) as TutorialAi
	_runner.start()
	_director.advance()
	assert_bool(_director.running()).is_false()  # The new match ended the lesson.
	var fresh: TutorialAi = _runner.controller_of(FOE) as TutorialAi
	assert_object(fresh).is_not_same(old)
	assert_bool(fresh.has_fired(&"go")).is_false()
	_director.start(_lesson())
	_shown.clear()
	assert_int(_play_until_shown()).is_less(FRAMES_MAX)
	assert_bool((_runner.controller_of(FOE) as TutorialAi).has_fired(&"go")).is_true()


func _lesson() -> TutorialLessonDef:
	return Lesson.lesson(
		"gate", [Lesson.beat("raid", TutorialConditions.Kind.NEXT, {"after_ai_step": &"go"})]
	)


func _start(mode: int) -> void:
	var def: TutorialScriptDef = TutorialScriptDef.new()
	def.id = &"gate_test"
	def.steps.append(
		Tut.step(
			"go",
			TutorialStepDef.Trigger.TICK,
			TutorialStepDef.Action.ATTACK_MOVE,
			{
				"threshold": GO_TICK,
				"target": TutorialStepDef.Target.TILE,
				"target_tile": Vector2i(20, 20)
			}
		)
	)
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = DummyStart.scenario()
	_runner.match_seed = 42
	_runner.tick_mode = mode
	_runner.opponents = [def]
	_runner.start()
	_director = auto_free(TutorialDirector.new())
	_director.runner = _runner
	_director.beat_shown.connect(
		func(_beat: TutorialBeatDef) -> void: _shown.append(_runner.snapshot.tick)
	)
	_director.start(_lesson())


## Frames of the runner and the director until the prompt is up; the number of frames played.
func _play_until_shown() -> int:
	var frames: int = 0
	while _shown.is_empty() and frames < FRAMES_MAX:
		_runner._process(FRAME)
		_director.advance()
		frames += 1
		OS.delay_msec(2)
	return frames
