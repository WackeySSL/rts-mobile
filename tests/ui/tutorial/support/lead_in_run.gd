extends RefCounted
## The lead-in states run of plan row P595 (ADR 0048 sections 5 and 13). Not a test suite. The chain
## sweep judges a chain in the start states the beats before it leave. This run judges each beat
## that has a lead-in in two more states, at every size and phone of the sweep:
## - `closed`: the build drawer is shut and nothing is selected (a player who tapped the map, or
##   closed the drawer, before the beat showed), whatever the beats before it left;
## - `regressed`: the lead-in's condition was met and then undone. For each step of the chain, the
##   steps up to it are satisfied (BUILD tapped, the tab opened, a type selected) and then it is
##   undone (the selection dropped, the drawer shut, another tab opened, the aim released). The
##   ring must come back to a step at or before it, and the rest of the chain is walked to the
##   beat's target.
## Both are judged with the sweep's checks (`ChainRig.drive`): the ring is on the control or unit
## the chain names, in the safe rect, the card does not hide it, and a unit step takes a real
## viewport touch. With `hand` on, the hand is also set on every step that has a control or a unit
## (`ChainRig.hand_problems`). A beat with a mid-play fixture gets a fresh match for each state.
## `states` counts what was judged, so a loop over an empty set fails the suite that reads it.

const ChainRig: GDScript = preload("res://tests/ui/tutorial/support/chain_rig.gd")
const MidPlay: GDScript = preload("res://tests/ui/tutorial/support/midplay_fixture.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")

## The problems, one line each, of every state judged.
var problems: Array[String] = []
## States judged, by variant: `closed` and `regressed`.
var closed: int = 0
var regressed: int = 0
## States judged by the kind of the step that was undone (`TutorialConditions.Kind` -> count).
var undone_kinds: Dictionary[int, int] = {}
## Beats ("lesson/beat") that were judged at least once.
var beats: Array[String] = []

var _suite: GdUnitTestSuite
var _rig: RefCounted
var _dir: String = ""


func _init(suite: GdUnitTestSuite) -> void:
	_suite = suite
	_rig = ChainRig.new(suite)


## Before each test, as the sweep does it: a clean save file and a slide of 0 ms.
func begin() -> void:
	MenuRig.begin()
	_dir = "user://test_lead_in_states_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	SaveService.set_path_override(_dir.path_join("save.cfg"))
	BuildSidebar.set_slide_ms_override(0)


## After each test.
func end() -> void:
	BuildSidebar.clear_slide_ms_override()
	UiScale.clear_override()
	SaveService.clear_path_override()
	MenuRig.end()
	CommandQueue.clear()
	for file_name: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file_name))
	DirAccess.remove_absolute(_dir)


## Judges every beat with a lead-in of the lessons in `lesson_ids`, at every profile.
func play(lesson_ids: Array[StringName]) -> void:
	var profiles: Array[UiMetrics] = _rig.profiles()
	for lesson: TutorialLessonDef in _rig.lessons():
		if not lesson_ids.has(lesson.id):
			continue
		for profile: UiMetrics in profiles:
			await _rig.open(lesson, profile)
			for beat: TutorialBeatDef in lesson.beats:
				if beat.lead_in.is_empty():
					continue
				var pair: String = "%s/%s" % [lesson.id, beat.id]
				if not beats.has(pair):
					beats.append(pair)
				await _judge_beat(lesson, beat, profile, pair)
			_rig.close()


func _judge_beat(
	lesson: TutorialLessonDef, beat: TutorialBeatDef, profile: UiMetrics, pair: String
) -> void:
	var midplay: bool = MidPlay.has(pair)
	var closed_state: Dictionary = {
		"unfold": HudState.Unfold.NONE, "tab": World.Tab.STRUCTURES, "select": ChainRig.NONE
	}
	# The drawer closed.
	if midplay:
		await _midplay(lesson, beat, profile, pair, closed_state)
	else:
		var result: Array = await _rig.judge(lesson, beat, profile, closed_state, "closed", true)
		problems.append_array(result[1] as Array[String])
	closed += 1
	# Each step undone after the steps up to it were met.
	for index: int in beat.lead_in.size():
		for how: int in _ways(beat.lead_in[index]):
			if midplay:
				await _midplay(lesson, beat, profile, pair, closed_state, index, how)
			else:
				await _regress(lesson, beat, profile, closed_state, index, how)
	if midplay:
		await _open_again(lesson, profile)  # The plain match again for the beats after it.


## How many ways the step can be undone: one, and for a drawer tab a second (another tab opened).
func _ways(step: TutorialLeadInDef) -> Array[int]:
	if step.kind == TutorialConditions.Kind.DRAWER_TAB:
		return [0, 1]
	return [0]


## A fresh match with the beat's fixture, then the state judged (the closed drawer, or the step
## `index` undone the way `how` says).
func _midplay(
	lesson: TutorialLessonDef,
	beat: TutorialBeatDef,
	profile: UiMetrics,
	pair: String,
	state: Dictionary,
	index: int = -1,
	how: int = 0
) -> void:
	_rig.close()
	await _rig.open(lesson, profile, MidPlay.scenario_for(pair, lesson.scenario))
	var fixture: Object = MidPlay.new(_suite, _rig.main, _rig.selection, _rig.sidebar)
	_rig.feed.state.close(_rig.feed.state.current)
	await fixture.prepare(pair)
	var label: String = (
		"%s %s %dx%d" % [pair, profile.os_name, profile.window_size.x, profile.window_size.y]
	)
	if not String(fixture.failure).is_empty():
		problems.append("%s: fixture: %s" % [label, fixture.failure])
		return
	_rig.feed.state.close(_rig.feed.state.current)  # A fixture may leave the drawer open.
	if index < 0:
		await _rig.show(lesson, beat)
		if _rig.director.active_target() == null:
			problems.append("%s closed: the beat ended before it showed its ring" % label)
			return
		var driven: Array = await _rig.drive(lesson, beat, profile, state, "closed", true)
		problems.append_array(driven[1] as Array[String])
		return
	await _regress(lesson, beat, profile, state, index, how, false)


## Shows the beat, meets its steps up to `index`, undoes step `index` the way `how` says and walks
## the chain from where the ring is to the beat's target.
func _regress(
	lesson: TutorialLessonDef,
	beat: TutorialBeatDef,
	profile: UiMetrics,
	state: Dictionary,
	index: int,
	how: int,
	enter_first: bool = true
) -> void:
	var step: TutorialLeadInDef = beat.lead_in[index]
	var label: String = (
		"%s/%s %s %dx%d regressed step %d (kind %d, way %d)"
		% [
			lesson.id,
			beat.id,
			profile.os_name,
			profile.window_size.x,
			profile.window_size.y,
			index,
			step.kind,
			how
		]
	)
	if enter_first:
		await _rig.enter(state)
	else:
		_rig.selection.clear()  # The fixture's start: nothing selected, so the steps are to do.
	await _rig.show(lesson, beat)
	for met: int in index + 1:
		if _rig.director.active_target() == null:
			return  # The beat's own condition held already: it ended, nothing to show.
		if not await _rig.satisfy(beat.lead_in[met]):
			problems.append(
				"%s: no hand for step %d (kind %d)" % [label, met, beat.lead_in[met].kind]
			)
			return
	if _rig.director.active_target() == null:
		return
	if not await _undo(step, how):
		problems.append("%s: no way to undo a step of kind %d" % [label, step.kind])
		return
	var active: TutorialLeadInDef = _rig.director.active_target()
	if active == null:
		problems.append("%s: no ring after the step was undone" % label)
		return
	var at: int = beat.lead_in.find(active) if beat.lead_in.has(active) else beat.lead_in.size()
	if at > index:
		problems.append(
			"%s: the ring is on step %d, not back on step %d or before" % [label, at, index]
		)
		return
	var driven: Array = await _rig.drive(
		lesson, beat, profile, state, "regressed %d/%d" % [index, how], true
	)
	problems.append_array(driven[1] as Array[String])
	regressed += 1
	undone_kinds[step.kind] = int(undone_kinds.get(step.kind, 0)) + 1


## Undoes what `satisfy` did for `step`. `how` 1 on a drawer tab opens another tab with the drawer
## still open; otherwise the drawer is shut, the selection dropped or the strike aim released.
func _undo(step: TutorialLeadInDef, how: int) -> bool:
	match step.kind:
		TutorialConditions.Kind.SELECTED:
			_rig.selection.clear()
		TutorialConditions.Kind.UNFOLD_OPEN:
			_rig.feed.state.close(_rig.feed.state.current)
		TutorialConditions.Kind.DRAWER_TAB:
			if how == 1:
				var other: int = World.Tab.VEHICLES
				if step.value == other:
					other = World.Tab.INFANTRY
				_rig.sidebar.select_tab(other)
			else:
				_rig.feed.state.close(_rig.feed.state.current)
		TutorialConditions.Kind.STRIKE_AIMING:
			var button: BaseButton = _rig.strike_button()
			if button == null:
				return false
			button.button_pressed = false
		_:
			return false
	for _frame: int in 3:
		await _suite.await_idle_frame()
	return true


## The plain match again, for the beats after a mid-play one.
func _open_again(lesson: TutorialLessonDef, profile: UiMetrics) -> void:
	_rig.close()
	await _rig.open(lesson, profile)


## Plays the lessons `ids` and asserts on `_suite`: every beat with a lead-in was judged closed at
## every profile (the floor: a loop over an empty set fails), every step of its chain was undone at
## every profile and each kind of step at least once, and no state had a problem.
func judge_lessons(ids: Array[StringName]) -> void:
	var expected: Dictionary = _expected(ids)
	await play(ids)
	for line: String in problems:
		print("LEAD-IN ", line)
	print("LEAD-IN ", ids, " closed ", closed, " regressed ", regressed, " kinds ", undone_kinds)
	var count: int = _rig.profiles().size()
	var beat_ids: Array = expected["beats"]
	_suite.assert_array(beats).override_failure_message("beats judged").is_equal(beat_ids)
	_suite.assert_int(closed).override_failure_message("closed states").is_equal(
		beat_ids.size() * count
	)
	# One undo per step and way at each profile; a beat that ended before its steps were met (its own
	# condition held at the start) is not counted, so the floor is what the data gives.
	_suite.assert_int(regressed).override_failure_message("regressed states").is_greater_equal(
		int(expected["regressed"]) * count
	)
	for kind: int in expected["kinds"]:
		(
			_suite
			. assert_int(int(undone_kinds.get(kind, 0)))
			. override_failure_message("no regressed state undid a step of kind %d" % kind)
			. is_greater(0)
		)
	_suite.assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


## From the lesson files: the beats with a lead-in ("lesson/beat"), the undoes one profile makes
## (a drawer tab twice) and the kinds of step they are.
func _expected(ids: Array[StringName]) -> Dictionary:
	var found: Array[String] = []
	var undoes: int = 0
	var kinds: Array[int] = []
	for id: StringName in ids:
		var lesson: TutorialLessonDef = (
			load("res://data/tutorial/%s.tres" % id) as TutorialLessonDef
		)
		for beat: TutorialBeatDef in lesson.beats:
			if beat.lead_in.is_empty():
				continue
			found.append("%s/%s" % [lesson.id, beat.id])
			for step: TutorialLeadInDef in beat.lead_in:
				undoes += 2 if step.kind == TutorialConditions.Kind.DRAWER_TAB else 1
				if not kinds.has(step.kind):
					kinds.append(step.kind)
	return {"beats": found, "regressed": undoes, "kinds": kinds}
