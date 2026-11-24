extends GdUnitTestSuite
## The director's chain of targets (plan row P586, ADR 0048 section 5): the active target per
## state, one `target_changed` per change, and a paused beat's chain. Split from
## `test_tutorial_director.gd`, which holds the beats, the pause and the save.

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


func _chained() -> TutorialBeatDef:
	return (
		Lesson
		. beat(
			"train",
			TutorialConditions.Kind.NEXT,
			{
				"anchor": TutorialBeatDef.Anchor.CONTROL,
				"anchor_control": &"Tile_rifle_squad",
				"lead_in":
				[
					Lesson.lead_in(
						"BuildButton", TutorialConditions.Kind.UNFOLD_OPEN, HudState.Unfold.DRAWER
					),
					Lesson.lead_in(
						"TabInfantry", TutorialConditions.Kind.DRAWER_TAB, World.Tab.INFANTRY
					),
				],
			}
		)
	)


func test_the_active_target_follows_the_chain_per_state() -> void:
	var changes: Array[StringName] = []
	_director.target_changed.connect(
		func(target: TutorialLeadInDef) -> void: changes.append(target.anchor_control)
	)
	var sidebar: BuildSidebar = auto_free(BuildSidebar.new())
	_director.sidebar = sidebar
	assert_object(_director.active_target()).is_null()  # No lesson.
	var beat: TutorialBeatDef = _chained()
	beat.delay_ticks = 5
	_director.start(Lesson.lesson("basics", [beat]))
	_director.advance()
	assert_object(_director.active_target()).is_null()  # In the gap.
	_play(5)
	_director.advance()
	assert_array(_shown).is_equal([&"train"])
	assert_str(String(_director.active_target().anchor_control)).is_equal("BuildButton")
	assert_array(changes).is_empty()  # beat_shown carries the first step.
	_hud.open(HudState.Unfold.DRAWER)
	_director.advance()
	assert_str(String(_director.active_target().anchor_control)).is_equal("TabInfantry")
	sidebar.tab = World.Tab.INFANTRY
	_director.advance()
	assert_object(_director.active_target()).is_not_same(beat.lead_in[1])
	assert_str(String(_director.active_target().anchor_control)).is_equal("Tile_rifle_squad")
	assert_array(changes).is_equal([&"TabInfantry", &"Tile_rifle_squad"])
	_director.skip()
	assert_object(_director.active_target()).is_null()


func test_target_changed_fires_once_per_change_and_both_ways() -> void:
	var count: Array[int] = [0]
	_director.target_changed.connect(func(_target: TutorialLeadInDef) -> void: count[0] += 1)
	_director.start(Lesson.lesson("basics", [_chained()]))
	_director.advance()
	for _i: int in 3:
		_director.advance()  # Nothing moved: no signal.
	assert_int(count[0]).is_equal(0)
	_hud.open(HudState.Unfold.DRAWER)
	for _i: int in 3:
		_director.advance()
	assert_int(count[0]).is_equal(1)
	_hud.close(HudState.Unfold.DRAWER)  # Closed by hand: back to BUILD.
	_director.advance()
	_director.advance()
	assert_int(count[0]).is_equal(2)
	assert_str(String(_director.active_target().anchor_control)).is_equal("BuildButton")


func test_the_final_step_is_one_object_per_beat() -> void:
	_director.start(Lesson.lesson("basics", [_chained()]))
	_director.advance()
	_hud.open(HudState.Unfold.DRAWER)
	_director.sidebar = auto_free(BuildSidebar.new())
	(_director.sidebar as BuildSidebar).tab = World.Tab.INFANTRY
	_director.advance()
	var first: TutorialLeadInDef = _director.active_target()
	_director.advance()
	assert_object(_director.active_target()).is_same(first)


func test_a_paused_beats_chain_still_works() -> void:
	var beat: TutorialBeatDef = _chained()
	beat.pause = true
	_director.start(Lesson.lesson("basics", [beat]))
	_director.advance()
	assert_bool(_runner.paused).is_true()
	assert_str(String(_director.active_target().anchor_control)).is_equal("BuildButton")
	_hud.open(HudState.Unfold.DRAWER)
	_director.advance()
	assert_str(String(_director.active_target().anchor_control)).is_equal("TabInfantry")


func test_a_next_beat_has_its_own_anchor_as_the_only_step() -> void:
	var beat: TutorialBeatDef = Lesson.beat(
		"read", NEXT, {"anchor": TutorialBeatDef.Anchor.CONTROL, "anchor_control": &"RadarButton"}
	)
	_director.start(Lesson.lesson("basics", [beat]))
	_director.advance()
	assert_str(String(_director.active_target().anchor_control)).is_equal("RadarButton")
	_director.next()
	assert_object(_director.active_target()).is_null()
