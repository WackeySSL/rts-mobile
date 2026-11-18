extends GdUnitTestSuite
## The tutorial director (plan row P541, ADR 0044 section 2): beats in order, the gap and the gate,
## the pause that is held and given back, Next, the budget, a lesson's end and its save, a skip, a
## new match under the lesson, and what it reads from the nodes it is given.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const Tut: GDScript = preload("res://tests/ai/support/tutorial_rig.gd")
const Lesson: GDScript = preload("res://tests/ui/tutorial/support/lesson_rig.gd")
const NEXT: TutorialConditions.Kind = TutorialConditions.Kind.NEXT

var _world: World
var _loop: MatchLoop
var _runner: MatchRunner
var _director: TutorialDirector
var _hud: HudState
var _shown: Array[StringName] = []
var _done: Array[StringName] = []
var _ended: Array[StringName] = []
var _skipped: Array[StringName] = []
var _dir: String = ""


func before_test() -> void:
	_dir = "user://test_tutorial_director_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	SaveService.set_path_override(_dir.path_join("save.cfg"))
	_world = Rig.start()
	_loop = Rig.loop_of(_world)
	_runner = auto_free(MatchRunner.new())
	_runner.snapshot = Lesson.snapshot(_world)
	_hud = HudState.new()
	_director = auto_free(TutorialDirector.new())
	_director.runner = _runner
	_director.hud = _hud
	_director.selection = SelectionModel.new()
	_shown.clear()
	_done.clear()
	_ended.clear()
	_skipped.clear()
	_director.beat_shown.connect(func(beat: TutorialBeatDef) -> void: _shown.append(beat.id))
	_director.beat_done.connect(func(beat: TutorialBeatDef) -> void: _done.append(beat.id))
	_director.lesson_done.connect(func(id: StringName) -> void: _ended.append(id))
	_director.lesson_skipped.connect(func(id: StringName) -> void: _skipped.append(id))


func after_test() -> void:
	SaveService.clear_path_override()
	for file_name: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file_name))
	DirAccess.remove_absolute(_dir)


## Plays `ticks` ticks of the world and publishes its snapshot (the serial of the match).
func _play(ticks: int, serial: int = 1) -> void:
	for _i: int in ticks:
		Rig.step(_world, _loop)
	_runner.snapshot = Lesson.snapshot(_world, serial)


func test_read_only_beats_show_in_order_and_end_by_next() -> void:
	_director.start(Lesson.lesson("basics", [Lesson.beat("one", NEXT), Lesson.beat("two", NEXT)]))
	assert_bool(_director.running()).is_true()
	assert_object(_director.current).is_null()
	assert_bool(_director.next()).is_false()  # Nothing is on show yet.
	_director.advance()
	assert_array(_shown).is_equal([&"one"])
	assert_bool(_director.can_next()).is_true()
	assert_object(_director.current).is_not_null()
	_director.advance()
	assert_array(_shown).is_equal([&"one"])  # NEXT never ends by itself.
	assert_bool(_director.next()).is_true()
	assert_array(_done).is_equal([&"one"])
	assert_object(_director.current).is_null()
	assert_that(_director.progress()).is_equal(Vector2i(1, 2))
	_director.advance()
	assert_array(_shown).is_equal([&"one", &"two"])
	_director.next()
	assert_array(_ended).is_equal([&"basics"])
	assert_bool(_director.running()).is_false()


func test_an_action_beat_ends_when_its_condition_holds() -> void:
	var beat: TutorialBeatDef = Lesson.beat(
		"pick", TutorialConditions.Kind.SELECTED, {"type_id": &"rifle_squad", "count": 1}
	)
	_director.start(Lesson.lesson("basics", [beat]))
	_director.advance()
	assert_bool(_director.can_next()).is_false()
	assert_bool(_director.next()).is_false()
	assert_array(_done).is_empty()
	_director.selection.set_ids(PackedInt32Array([Lesson.row_id(_world, 1, "rifle_squad")]))
	_director.advance()
	assert_array(_ended).is_equal([&"basics"])


func test_a_beat_waits_its_delay_in_match_ticks() -> void:
	_director.start(Lesson.lesson("basics", [Lesson.beat("late", NEXT, {"delay_ticks": 30})]))
	_director.advance()
	assert_array(_shown).is_empty()
	_play(29)
	_director.advance()
	assert_array(_shown).is_empty()
	_play(1)
	_director.advance()
	assert_array(_shown).is_equal([&"late"])


func test_a_stalled_beat_is_one_past_its_budget() -> void:
	var beat: TutorialBeatDef = Lesson.beat(
		"pan", TutorialConditions.Kind.CAMERA_PANNED, {"budget_s": 2}
	)
	_director.start(Lesson.lesson("basics", [beat]))
	assert_bool(_director.stalled()).is_false()
	_director.advance()
	_play(2 * Sim.TICK_RATE - 1)
	assert_bool(_director.stalled()).is_false()
	_play(1)
	assert_bool(_director.stalled()).is_true()


func test_a_pause_beat_holds_the_match_until_it_is_done() -> void:
	var held: TutorialBeatDef = Lesson.beat("read", NEXT, {"pause": true})
	_director.start(Lesson.lesson("basics", [held, Lesson.beat("go", NEXT)]))
	assert_bool(_runner.paused).is_false()
	_director.advance()
	assert_bool(_runner.paused).is_true()
	_director.next()
	assert_bool(_runner.paused).is_false()


func test_the_director_pauses_again_after_the_pause_menu_resumes() -> void:
	_director.start(Lesson.lesson("basics", [Lesson.beat("read", NEXT, {"pause": true})]))
	_director.advance()
	# The pause menu opens over the beat and, on Resume, unpauses what it paused.
	_hud.open(HudState.Unfold.PAUSE)
	_director.advance()
	assert_bool(_runner.paused).is_true()
	_hud.close(HudState.Unfold.PAUSE)
	_runner.paused = false
	_director.advance()
	assert_bool(_runner.paused).is_true()
	_director.next()
	assert_bool(_runner.paused).is_false()


func test_a_beat_that_ends_under_the_pause_menu_leaves_the_pause_to_it() -> void:
	_director.start(Lesson.lesson("basics", [Lesson.beat("read", NEXT, {"pause": true})]))
	_director.advance()
	_hud.open(HudState.Unfold.PAUSE)
	_director.next()
	assert_bool(_runner.paused).is_true()  # The menu's own pause; its Resume lets go.


func test_a_beat_without_pause_never_touches_the_runner() -> void:
	_runner.paused = true  # The player's own pause stays whatever the lesson does.
	_director.start(Lesson.lesson("basics", [Lesson.beat("a", NEXT)]))
	_director.advance()
	_director.next()
	assert_bool(_runner.paused).is_true()


func test_the_last_beat_saves_the_lesson_as_done() -> void:
	assert_bool(TutorialDirector.is_done(&"basics")).is_false()
	_director.start(Lesson.lesson("basics", [Lesson.beat("a", NEXT)]))
	_director.advance()
	_director.next()
	assert_bool(TutorialDirector.is_done(&"basics")).is_true()
	assert_bool(TutorialDirector.is_done(&"drill_air")).is_false()
	assert_bool(TutorialDirector.mark_done(&"basics")).is_true()  # Once, not twice.
	assert_array(Array(TutorialDirector.lessons_done())).is_equal(["basics"])


func test_skip_ends_the_lesson_unsaved_and_gives_the_pause_back() -> void:
	_director.start(Lesson.lesson("basics", [Lesson.beat("a", NEXT, {"pause": true})]))
	_director.advance()
	_director.skip()
	assert_array(_skipped).is_equal([&"basics"])
	assert_array(_ended).is_empty()
	assert_bool(_runner.paused).is_false()
	assert_bool(_director.running()).is_false()
	assert_bool(TutorialDirector.is_done(&"basics")).is_false()
	_director.skip()  # Nothing runs: no second signal.
	assert_int(_skipped.size()).is_equal(1)


func test_a_new_match_under_the_lesson_ends_it() -> void:
	_director.start(Lesson.lesson("basics", [Lesson.beat("a", NEXT, {"pause": true})]))
	_director.advance()
	_runner.snapshot = Lesson.snapshot(_world, 2)
	_director.advance()
	assert_array(_skipped).is_equal([&"basics"])
	assert_bool(_runner.paused).is_false()


func test_a_beat_waits_for_the_scripted_opponents_step() -> void:
	var arena: World = Tut.start()
	var def: TutorialScriptDef = TutorialScriptDef.new()
	def.steps.append(
		Tut.step(
			"go",
			TutorialStepDef.Trigger.TICK,
			TutorialStepDef.Action.ATTACK_MOVE,
			{"target": TutorialStepDef.Target.HOME, "target_tile": Vector2i(2, 0)}
		)
	)
	var ai: TutorialAi = Tut.ai_of(def)
	_director.ai = ai
	_director.start(
		Lesson.lesson("basics", [Lesson.beat("attack", NEXT, {"after_ai_step": &"go"})])
	)
	_director.advance()
	_runner.ticked.emit(0)
	_director.advance()
	assert_array(_shown).is_empty()  # The step has not fired.
	Tut.think(arena, ai)
	assert_bool(ai.has_fired(&"go")).is_true()
	_director.advance()
	assert_array(_shown).is_empty()  # The gate is read on a published tick only.
	_runner.ticked.emit(1)
	_director.advance()
	assert_array(_shown).is_equal([&"attack"])


func test_a_gate_with_no_opponent_set_warns_and_opens() -> void:
	var lesson: TutorialLessonDef = Lesson.lesson(
		"basics", [Lesson.beat("a", NEXT, {"after_ai_step": &"go"})]
	)
	(
		assert_error(func() -> void: _director.start(lesson))
		. is_push_warning("TutorialDirector: beat a waits for the opponent, none is set")
	)
	_director.advance()
	assert_array(_shown).is_equal([&"a"])


func test_it_reads_the_camera_the_placement_and_the_strike_aim() -> void:
	var camera: RtsCamera = auto_free(RtsCamera.new())
	camera.settings = InputSettings.new()
	camera.zoom = Vector2.ONE * camera.settings.zoom_levels[2]
	var placement: PlacementController = auto_free(PlacementController.new())
	var aim: StrikeAim = auto_free(StrikeAim.new())
	_director.camera = camera
	_director.placement = placement
	_director.strike_aim = aim
	var kinds: TutorialConditions.Kind = TutorialConditions.Kind.ZOOM_LEVEL
	var zoom: TutorialBeatDef = Lesson.beat("zoom", kinds, {"value": 2})
	var place: TutorialBeatDef = Lesson.beat("place", TutorialConditions.Kind.PLACING)
	var strike: TutorialBeatDef = Lesson.beat("strike", TutorialConditions.Kind.STRIKE_AIMED)
	_director.start(Lesson.lesson("basics", [zoom, place, strike]))
	_director.advance()  # Shows the zoom beat.
	_director.advance()  # The camera is on level 2: done.
	assert_array(_done).is_equal([&"zoom"])
	_director.advance()
	assert_array(_shown).is_equal([&"zoom", &"place"])
	placement.active = true
	placement.type_index = Rig.type_of(_world, "barracks")
	_director.advance()
	assert_array(_done).is_equal([&"zoom", &"place"])
	_director.advance()
	aim.active = true
	aim.has_point = true
	_director.advance()
	assert_array(_ended).is_equal([&"basics"])


func test_a_surrender_under_a_held_beat_ends_the_lesson_and_lets_the_match_tick() -> void:
	_director.start(Lesson.lesson("basics", [Lesson.beat("read", NEXT, {"pause": true})]))
	_director.advance()
	# The pause menu's SURRENDER: it closes PAUSE (and unpauses), then queues the Command.
	_hud.open(HudState.Unfold.PAUSE)
	_hud.close(HudState.Unfold.PAUSE)
	_runner.paused = false
	var drained: Array[Command] = []
	CommandQueue.submit(Command.stop(1, PackedInt32Array([1])))  # Another order: no skip.
	assert_bool(_director.running()).is_true()
	CommandQueue.submit(Command.surrender(1))
	CommandQueue.drain_into(drained)
	assert_array(_skipped).is_equal([&"basics"])
	assert_bool(_runner.paused).is_false()
	_director.advance()
	assert_bool(_runner.paused).is_false()  # Nothing holds it again.
	# And in a frame the director runs before the runner, so a re-pause lands before its tick.
	assert_int(_director.process_priority).is_less(_runner.process_priority)


func test_a_lesson_started_before_the_first_snapshot_adopts_its_match() -> void:
	_runner.snapshot = null
	_director.start(Lesson.lesson("basics", [Lesson.beat("a", NEXT, {"delay_ticks": 5})]))
	_director.advance()
	assert_bool(_director.running()).is_true()
	_runner.snapshot = Lesson.snapshot(_world, 7)
	_director.advance()
	assert_bool(_director.running()).is_true()
	assert_array(_skipped).is_empty()
	_runner.snapshot = Lesson.snapshot(_world, 8)  # Another match is a skip.
	_director.advance()
	assert_array(_skipped).is_equal([&"basics"])


func test_a_tick_condition_is_checked_again_only_on_a_new_snapshot() -> void:
	var beat: TutorialBeatDef = Lesson.beat(
		"train", TutorialConditions.Kind.OWN_AT_LEAST, {"type_id": &"rifle_squad", "count": 3}
	)
	_director.start(Lesson.lesson("basics", [beat]))
	_director.advance()  # Shows.
	_director.advance()  # Checks the snapshot: two squads.
	Rig.add_unit_of(_world, 1, "rifle_squad", 5000, 11000)
	_director.advance()
	assert_array(_done).is_empty()  # The published snapshot is the same object.
	_runner.snapshot = Lesson.snapshot(_world)
	_director.advance()
	assert_array(_done).is_equal([&"train"])
