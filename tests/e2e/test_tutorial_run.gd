extends GdUnitTestSuite
## Plan row P545 (ADR 0044 section 5): the TutorialBot plays each of the four lessons through its
## real match (`tests/e2e/support/tutorial_bot.gd`): the main scene's HUD, controller and camera on
## the lesson's scenario and seed against its scripted opponent, a director and a coach mark. The
## run must end every lesson. It fails on a renamed or hidden HUD control that a beat's action taps,
## and on a beat that cannot be finished. Ticks are counted, nothing is timed.

const Bot: GDScript = preload("res://tests/e2e/support/tutorial_bot.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const LESSON_DIR: String = "res://data/tutorial/"

var _main: Node2D


func before_test() -> void:
	MenuRig.begin()
	CommandQueue.clear()


func after_test() -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	_main = null
	CommandQueue.clear()
	MenuRig.end()


func test_the_bot_finishes_basics() -> void:
	await _finishes(&"basics")


func test_the_bot_finishes_strikes() -> void:
	await _finishes(&"strikes")


func test_the_bot_finishes_air() -> void:
	await _finishes(&"air")


func test_the_bot_finishes_support() -> void:
	await _finishes(&"support")


## Plays `id` and checks the run ended the lesson, with every anchor control a node of the HUD.
func _finishes(id: StringName, think_ticks: int = 0) -> Dictionary:
	var lesson: TutorialLessonDef = load("%s%s.tres" % [LESSON_DIR, id]) as TutorialLessonDef
	var result: Dictionary = await _play(lesson, think_ticks)
	print(
		(
			"TutorialBot %s: done=%s ticks=%d failure='%s' ringless=%s contact=%d shown=%s"
			% [
				id,
				result["done"],
				result["ticks"],
				result["failure"],
				result["ringless"],
				result["contact"],
				result["shown"]
			]
		)
	)
	assert_str(result["failure"]).override_failure_message(String(id)).is_empty()
	assert_bool(result["skipped"]).override_failure_message(String(id) + " skipped").is_false()
	assert_bool(result["done"]).override_failure_message(String(id) + " did not end").is_true()
	assert_bool(TutorialDirector.is_done(id)).override_failure_message(id + " not saved").is_true()
	assert_array(result["missing"]).override_failure_message(String(id)).is_empty()
	assert_int(result["shown"].size()).is_equal(lesson.beats.size())
	return result


func _play(lesson: TutorialLessonDef, think_ticks: int) -> Dictionary:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var runner: MatchRunner = _main.get_node("MatchRunner")
	runner.scenario = lesson.scenario
	runner.match_seed = lesson.match_seed
	runner.tick_mode = MatchRunner.TickMode.SYNC
	var opponents: Array[AiDef] = [lesson.enemy]
	runner.opponents = opponents
	add_child(_main)
	await await_idle_frame()
	var bot: RefCounted = Bot.new(self, _main)
	bot.think_ticks = think_ticks
	return await bot.play(lesson)
