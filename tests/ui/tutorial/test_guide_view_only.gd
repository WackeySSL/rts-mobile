extends GdUnitTestSuite
## Plan row P595 (ADR 0048 section 3 and 13): the guide is view only. The TutorialBot plays Basics
## on one seed, through its real match, three times at the same size: the guide on, the guide on
## again, and the guide on with Reduced effects on (a steady frame, a still hand, no Tween). The
## three runs must end in the same command log, the same tick count and the same final state hash,
## so nothing the guide draws or animates reaches the sim. The hash and the tick count of the
## landscape run are pinned as golden values: a change of either is a change of what Basics plays
## (the lesson, the scripted opponent or the sim) and is read, never relaxed.
##
## Option used: "guide on" against "guide on + Reduced effects", not "guide off". The bot cannot be
## driven with no guide: it finds each control and unit step through the coach mark's ring
## (`target_control`, `unit_anchor`), so with no mark it has nothing to tap. The director that the
## guide's beats run on also holds the match during a card and lets the scripted opponent's waves
## leave on the player's progress, which are part of the lesson and not of the view.
## What the log leaves out: nothing. The command log (`MatchRunner.replay.commands`) holds every
## Command the match stamped, the bot's orders and the scripted opponent's. The guide's own taps
## (the card's Next, Skip and the drawer tab, the hand, the ring) are UI calls on the director and
## send no Command, so there is nothing to exclude.
## One thing is held still so that the bot's ticks do not depend on wall time: the camera's zoom
## snap is a Tween of real time, so a run takes a different number of frames to reach a zoom level
## and the bot, which waits for the level, acts some ticks later (a first version of this suite
## differed in the third command's tick between two runs of the same guide). The camera of each run
## gets a copy of its settings with `zoom_snap_ms` 0, which snaps at once.
## The runs are played at the phone's landscape size only (ScreenSizes.LANDSCAPE[1]). At its
## portrait twin the bot's command ticks still moved between two runs of the same guide (1220, 1250
## and 1266 ticks in three runs: a real-time Tween of the upright HUD that the bot waits for, not
## found), so a portrait comparison would be flaky; it is an open point of plan row P595.

const Bot: GDScript = preload("res://tests/e2e/support/tutorial_bot.gd")
const ChainRig: GDScript = preload("res://tests/ui/tutorial/support/chain_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const LESSON: String = "res://data/tutorial/basics.tres"
## The golden of Basics at the landscape phone: ticks the bot played and the World's state hash.
const GOLDEN_TICKS: int = 1193
const GOLDEN_HASH: int = -8777520963123993103
const GOLDEN_COMMAND_WORDS: int = 175

var _window_size_before: Vector2i
var _main: Node2D


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	CommandQueue.clear()


func after_test() -> void:
	_free_main()
	CommandQueue.clear()
	UiScale.clear_override()
	MenuRig.end()


func test_basics_ends_the_same_with_the_guide_on_twice_and_with_reduced_effects() -> void:
	var landscape: Dictionary = await _three(ScreenSizes.LANDSCAPE[1])
	assert_int(landscape["ticks"]).override_failure_message("golden ticks").is_equal(GOLDEN_TICKS)
	assert_int(landscape["hash"]).override_failure_message("golden hash").is_equal(GOLDEN_HASH)
	assert_int(landscape["words"]).override_failure_message("golden command words").is_equal(
		GOLDEN_COMMAND_WORDS
	)


## Plays Basics three times at `size` (the guide, the guide again, the guide with Reduced effects)
## and asserts the runs agree; returns the first run's ticks, hash and command words.
func _three(size: Vector2i) -> Dictionary:
	var first: Dictionary = await _play(size, false)
	var again: Dictionary = await _play(size, false)
	var reduced: Dictionary = await _play(size, true)
	print(
		(
			"VIEW-ONLY %dx%d ticks %d hash %d command words %d"
			% [size.x, size.y, first["ticks"], first["hash"], first["words"]]
		)
	)
	assert_bool(first["done"]).override_failure_message("run 1 did not end Basics").is_true()
	assert_str(first["failure"]).override_failure_message("run 1").is_empty()
	for other: Dictionary in [again, reduced]:
		var which: String = "reduced effects" if other == reduced else "the guide again"
		assert_bool(other["done"]).override_failure_message(which + " did not end").is_true()
		assert_str(other["failure"]).override_failure_message(which).is_empty()
		assert_int(other["ticks"]).override_failure_message(which + ": ticks").is_equal(
			first["ticks"]
		)
		assert_int(other["hash"]).override_failure_message(which + ": state hash").is_equal(
			first["hash"]
		)
		(
			assert_bool(other["log"] == first["log"])
			. override_failure_message(which + ": command log")
			. is_true()
		)
	assert_int(first["words"]).override_failure_message("the log holds commands").is_greater(0)
	return first


## One run: the lesson through the bot with Reduced effects `reduced`; its ticks, the final state
## hash, the command log as the runner recorded it and whether the mark ran reduced.
func _play(size: Vector2i, reduced: bool) -> Dictionary:
	assert_int(MenuPrefs.set_reduced_effects(reduced)).is_equal(OK)
	var profile: UiMetrics = ChainRig.new(self).profile_of(size)
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	var lesson: TutorialLessonDef = load(LESSON) as TutorialLessonDef
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var runner: MatchRunner = _main.get_node("MatchRunner")
	runner.scenario = lesson.scenario
	runner.match_seed = lesson.match_seed
	runner.tick_mode = MatchRunner.TickMode.SYNC
	var opponents: Array[AiDef] = [lesson.enemy]
	runner.opponents = opponents
	add_child(_main)
	await await_idle_frame()
	# The zoom snap is a Tween of real time; the bot's ticks must not depend on how many frames it
	# takes. A copy of the settings snaps at once (`RtsCamera._snap_to_level`).
	var camera: RtsCamera = _main.get_node("Camera") as RtsCamera
	camera.settings = camera.settings.duplicate() as InputSettings
	camera.settings.zoom_snap_ms = 0
	var bot: RefCounted = Bot.new(self, _main)
	var result: Dictionary = await bot.play(lesson)
	var commands: PackedInt32Array = runner.replay.commands.duplicate()
	var made: Dictionary = {
		"done": result["done"],
		"failure": result["failure"],
		"ticks": result["ticks"],
		"hash": runner.world.state_hash(),
		"log": commands,
		"words": commands.size(),
	}
	_free_main()
	CommandQueue.clear()
	return made


func _free_main() -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	_main = null
