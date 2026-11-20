extends GdUnitTestSuite
## Plan row P545 (ADR 0044 section 5): the TutorialBot plays each of the four lessons through its
## real match (`tests/e2e/support/tutorial_bot.gd`): the main scene's HUD, controller and camera on
## the lesson's scenario and seed against its scripted opponent, a director and a coach mark. The
## run must end every lesson. It fails on a renamed or hidden HUD control that a beat's action taps,
## and on a beat that cannot be finished. Ticks are counted, nothing is timed.

const Bot: GDScript = preload("res://tests/e2e/support/tutorial_bot.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
## The lessons are played on a phone: its dp sets the hit radii a tap is judged by.
const PHONE: StringName = &"android_6in"
const LESSON_DIR: String = "res://data/tutorial/"

var _main: Node2D
var _window_size_before: Vector2i


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	CommandQueue.clear()


func after_test() -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	_main = null
	CommandQueue.clear()
	UiScale.clear_override()
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
	_assert_order(lesson, result)
	# A beat's target is on the screen when its card shows (TUTORIAL_AUTHORING): no ring is missing.
	assert_array(result["ringless"]).override_failure_message(String(id)).is_empty()
	return result


func _play(lesson: TutorialLessonDef, think_ticks: int) -> Dictionary:
	var phone: UiMetrics = UiProfiles.by_name(PHONE)
	UiScale.set_override(phone)
	get_window().size = phone.window_size
	await await_idle_frame()
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


## Every beat showed and ended, in the lesson's order, each ending no earlier than it showed and
## the next showing no earlier than that.
func _assert_order(lesson: TutorialLessonDef, result: Dictionary) -> void:
	var ids: Array[StringName] = []
	for beat: TutorialBeatDef in lesson.beats:
		ids.append(beat.id)
	var shown: Dictionary = result["shown"]
	var done_at: Dictionary = result["done_at"]
	assert_array(shown.keys()).override_failure_message("shown order").is_equal(ids)
	assert_array(done_at.keys()).override_failure_message("done order").is_equal(ids)
	var last: int = 0
	for id: StringName in ids:
		assert_int(shown[id]).override_failure_message("%s shown early" % id).is_greater_equal(last)
		assert_int(done_at[id]).override_failure_message("%s done early" % id).is_greater_equal(
			shown[id]
		)
		last = done_at[id]
