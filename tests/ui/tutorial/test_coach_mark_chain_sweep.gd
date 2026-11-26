extends GdUnitTestSuite
## The chain sweep (plan row P591, ADR 0048 section 5; Michael's phone test of Basics 21/28, where
## the frame stayed on the Infantry tab with the tab already open). For every beat of every lesson
## file in `data/tutorial/` that has a target, at the six sizes and the two small real phones, in
## the real HUD in the state the beats before it leave (the first of a few selections that shows its
## control when the plain state does not): the ring stands on the beat's active step, and then, as
## each step is satisfied in turn (BUILD tapped, the tab opened), on the next one, ending on the
## beat's own target. At every step the ring must be:
## - a ring (a box with area) and the mark showing;
## - on a visible control that is not a disabled button, or on a world tile;
## - inside the safe rect;
## - not hidden behind the card: where it meets the card the card is see-through.
## A beat with a target and no visible ring fails.

const Lesson: GDScript = preload("res://tests/ui/tutorial/support/lesson_rig.gd")
const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MidPlay: GDScript = preload("res://tests/ui/tutorial/support/midplay_fixture.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const LESSON_DIR: String = "res://data/tutorial/"
const MAIN_SCENE: String = "res://scenes/main.tscn"
const TOLERANCE_PX: float = 0.5
const OVERLAP_PX2: float = 4.0
const GROUPS: int = 3
const EXTRA_PROFILES: Array[StringName] = [&"web_phone_small", &"web_phone_portrait"]
## Which selection a start state holds: nothing, the player's units, one building (`BUILDINGS` plus
## its index in the player's list).
const NONE: int = 0
const UNITS: int = 1
const BUILDINGS: int = 2
## Kinds a player ends with a gesture on the map, which folds the drawer (HudState.map_gesture).
const MAP_KINDS: Array[TutorialConditions.Kind] = [
	TutorialConditions.Kind.SELECTED,
	TutorialConditions.Kind.UNITS_IN_AREA,
	TutorialConditions.Kind.BUILDING_PLACED,
	TutorialConditions.Kind.BUILDING_DONE,  # The placing before it closed the drawer.
	TutorialConditions.Kind.PLACING,
	TutorialConditions.Kind.ZOOM_LEVEL,
	TutorialConditions.Kind.CAMERA_PANNED,
	TutorialConditions.Kind.ENEMY_LOSSES,
	TutorialConditions.Kind.HARVESTED,
	TutorialConditions.Kind.STRIKE_AIMED,
	TutorialConditions.Kind.STRIKE_PENDING,
	TutorialConditions.Kind.MATCH_WON,
]

var _window_size_before: Vector2i
var _dir: String = ""
var _main: Node
var _feed: HudStateFeed
var _sidebar: BuildSidebar
var _mark: CoachMark
var _director: TutorialDirector
var _selection: SelectionModel
var _own: PackedInt32Array = PackedInt32Array()
var _own_buildings: PackedInt32Array = PackedInt32Array()


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	_dir = "user://test_coach_chain_sweep_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	SaveService.set_path_override(_dir.path_join("save.cfg"))
	BuildSidebar.set_slide_ms_override(0)


func after_test() -> void:
	BuildSidebar.clear_slide_ms_override()
	UiScale.clear_override()
	SaveService.clear_path_override()
	MenuRig.end()
	CommandQueue.clear()
	for file_name: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file_name))
	DirAccess.remove_absolute(_dir)


func test_the_ring_follows_every_chain_to_a_visible_control_in_every_lesson() -> void:
	var profiles: Array[UiMetrics] = []
	for size: Vector2i in ScreenSizes.ALL:
		profiles.append(_profile(size))
	for profile_name: StringName in EXTRA_PROFILES:
		profiles.append(UiProfiles.by_name(profile_name))
	var found: Array[String] = []
	var judged: int = 0
	var chained: int = 0
	for lesson: TutorialLessonDef in _lessons():
		for profile: UiMetrics in profiles:
			await _open(lesson, profile)
			var carried: Dictionary = {"unfold": HudState.Unfold.NONE, "tab": 0, "select": NONE}
			for beat: TutorialBeatDef in lesson.beats:
				if beat.anchor != TutorialBeatDef.Anchor.NONE:
					var pair: String = "%s/%s" % [lesson.id, beat.id]
					var result: Array
					if MidPlay.has(pair):
						result = await _judge_midplay(lesson, beat, profile, pair)
						_close()
						await _open(lesson, profile)  # Back to the plain match for the beats after it.
					else:
						result = await _judge(lesson, beat, profile, carried)
					var problems: Array[String] = result[1] as Array[String]
					judged += 1
					chained += int(result[0])
					found.append_array(problems)
				carried = _after(beat, carried)
			_close()
	assert_int(judged).is_greater(100)
	assert_int(chained).override_failure_message("no chained beat was driven").is_greater(8)
	for line: String in found:
		print("CHAIN ", line)
	print("CHAIN judged ", judged, " chained ", chained)
	assert_array(found).override_failure_message("\n".join(found)).is_empty()


## already open and the ring stayed on it. With the tab open the ring goes to the Rig Hands card;
## with the drawer shut it starts on BUILD, then the tab, then the card.
## the drawer shut it starts on BUILD, then the tab, then the card.
func test_basics_train_with_the_infantry_tab_already_open_the_ring_goes_to_the_card() -> void:
	var lesson: TutorialLessonDef = load(LESSON_DIR + "basics.tres") as TutorialLessonDef
	var train: TutorialBeatDef = null
	for beat: TutorialBeatDef in lesson.beats:
		if beat.id == &"train":
			train = beat
	assert_object(train).is_not_null()
	var card: String = "Tile_rifle_squad"
	for size: Vector2i in [ScreenSizes.LANDSCAPE[0], ScreenSizes.PORTRAIT[0]]:
		await _open(lesson, _profile(size))
		var open: Dictionary = {
			"unfold": HudState.Unfold.DRAWER, "tab": World.Tab.INFANTRY, "select": NONE
		}
		await _enter(open)
		await _show(lesson, train)
		assert_str(String(_director.active_target().anchor_control)).is_equal(card)
		assert_str(String(_mark.target_control().name)).is_equal(card)
		assert_array(_ring_problems("open tab", _director.active_target())).is_empty()
		var shut: Dictionary = {
			"unfold": HudState.Unfold.NONE, "tab": World.Tab.STRUCTURES, "select": NONE
		}
		await _enter(shut)
		await _show(lesson, train)
		assert_str(String(_director.active_target().anchor_control)).is_equal("BuildButton")
		assert_bool(await _satisfy(_director.active_target())).is_true()
		assert_str(String(_director.active_target().anchor_control)).is_equal("TabInfantry")
		assert_bool(await _satisfy(_director.active_target())).is_true()
		assert_str(String(_director.active_target().anchor_control)).is_equal(card)
		assert_array(_ring_problems("shut then opened", _director.active_target())).is_empty()
		_close()


## A beat that asks the player to build or train something ends on the item's card, never on the tab
## that holds it: the frame has to follow the player to the thing they must tap.
func test_a_beat_that_asks_for_units_ends_on_their_card_not_on_a_tab() -> void:
	for lesson: TutorialLessonDef in _lessons():
		for beat: TutorialBeatDef in lesson.beats:
			if beat.kind == TutorialConditions.Kind.OWN_AT_LEAST and beat.anchor_control != &"":
				var ends: String = "%s/%s ends on %s" % [lesson.id, beat.id, beat.anchor_control]
				(
					assert_bool(String(beat.anchor_control).begins_with("Tab"))
					. override_failure_message(ends)
					. is_false()
				)


## Judges `beat` in the mid-play state its fixture builds: a fresh match with the fixture's units
## in the scenario, then the fixture's own taps, then the chain of the beat.
func _judge_midplay(
	lesson: TutorialLessonDef, beat: TutorialBeatDef, profile: UiMetrics, pair: String
) -> Array:
	_close()
	await _open(lesson, profile, MidPlay.scenario_for(pair, lesson.scenario))
	var fixture: Object = MidPlay.new(self, _main, _selection, _sidebar)
	_feed.state.close(_feed.state.current)
	await fixture.prepare(pair)
	var label: String = (
		"%s %s %dx%d" % [pair, profile.os_name, profile.window_size.x, profile.window_size.y]
	)
	if not String(fixture.failure).is_empty():
		return [false, ["%s: fixture: %s" % [label, fixture.failure]] as Array[String]]
	await _show(lesson, beat)
	if _director.active_target() == null:
		return [false, ["%s: the beat ended before it showed its ring" % label] as Array[String]]
	return await _drive(lesson, beat, profile, {"unfold": 0, "tab": 0, "select": NONE})


## Judges `beat` in the first start state that shows its ring and drives its chain to the end.
## Returns [whether a chain of two steps or more was driven, the problems of the first state when
## none was clean].
func _judge(
	lesson: TutorialLessonDef, beat: TutorialBeatDef, profile: UiMetrics, carried: Dictionary
) -> Array:
	var first: Array[String] = []
	for state: Dictionary in _states(carried):
		await _enter(state)
		await _show(lesson, beat)
		var driven: Array = await _drive(lesson, beat, profile, state)
		if (driven[1] as Array[String]).is_empty():
			return driven
		if first.is_empty():
			first = driven[1] as Array[String]
	return [false, first]


## Walks the chain of the beat on show: checks the ring on the active step, satisfies it, checks
## the next, up to the beat's own target.
func _drive(
	lesson: TutorialLessonDef, beat: TutorialBeatDef, profile: UiMetrics, state: Dictionary
) -> Array:
	var lines: Array[String] = []
	var label: String = (
		"%s/%s %s %dx%d unfold=%d tab=%d select=%d"
		% [
			lesson.id,
			beat.id,
			profile.os_name,
			profile.window_size.x,
			profile.window_size.y,
			state["unfold"],
			state["tab"],
			state["select"]
		]
	)
	var steps: int = 0
	for _round: int in beat.lead_in.size() + 1:
		var step: TutorialLeadInDef = _director.active_target()
		if step == null:  # The state met the beat's condition already: it ended, nothing to show.
			return [false, lines]
		var problems: Array[String] = _ring_problems("%s step %d" % [label, steps], step)
		lines.append_array(problems)
		if not problems.is_empty():
			break
		steps += 1
		if not beat.lead_in.has(step):  # The beat's own target: the end of the chain.
			break
		if not await _satisfy(step):
			break
		var next: TutorialLeadInDef = _director.active_target()
		if next == step:
			lines.append("%s: the ring stayed on step %d after it was satisfied" % [label, steps])
			break
	return [steps >= 2, lines]


## What is wrong with the ring on `step`, one line each.
func _ring_problems(label: String, step: TutorialLeadInDef) -> Array[String]:
	var lines: Array[String] = []
	if not _mark.visible:
		lines.append("%s: the mark is not showing" % label)
		return lines
	var ring: Rect2 = _mark.ring_rect()
	if not ring.has_area():
		lines.append("%s: no ring for %s" % [label, step.anchor_control])
		return lines
	var safe: Rect2 = SafeAreaMargin.rect_inside(
		get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
	)
	if not safe.grow(TOLERANCE_PX).encloses(ring):
		lines.append("%s: the ring %s is outside the safe rect %s" % [label, ring, safe])
	if step.anchor == TutorialBeatDef.Anchor.CONTROL:
		var target: Control = _mark.target_control()
		if target == null:
			lines.append("%s: no control %s under the ring" % [label, step.anchor_control])
		else:
			if target.name != step.anchor_control:
				lines.append("%s: the ring is on %s" % [label, target.name])
			var button: BaseButton = target as BaseButton
			if not target.is_visible_in_tree() or (button != null and button.disabled):
				lines.append("%s: %s is hidden or disabled" % [label, target.name])
	if _mark.card_open() and not _mark.see_through():
		if _mark.card_rect().intersection(ring).get_area() > OVERLAP_PX2:
			lines.append("%s: the card %s hides the ring %s" % [label, _mark.card_rect(), ring])
	return lines


## Does what the player does to pass `step`; false when the sweep has no hand for its kind.
func _satisfy(step: TutorialLeadInDef) -> bool:
	match step.kind:
		TutorialConditions.Kind.UNFOLD_OPEN:
			_feed.state.open(step.value as HudState.Unfold)
		TutorialConditions.Kind.DRAWER_TAB:
			_feed.state.open(HudState.Unfold.DRAWER)
			_sidebar.select_tab(step.value)
		TutorialConditions.Kind.SELECTED:
			var ids: PackedInt32Array = _own_of(step.type_id)
			if ids.is_empty():
				return false  # A type that is not in the match: a typo in the data.
			_selection.set_ids(ids)
		TutorialConditions.Kind.STRIKE_AIMING:
			var button: BaseButton = _strike_button()
			if button == null or not button.is_visible_in_tree() or button.disabled:
				return false
			button.button_pressed = true  # The real strike button, as a finger toggles it.
		_:
			return false
	for _frame: int in 3:
		await await_idle_frame()
	return true


## The player's rows of `type_id` (any unit when empty): the whole type for units, the first one
## for a building (a tap picks one building).
func _own_of(type_id: StringName) -> PackedInt32Array:
	if type_id == &"":
		return _own
	var runner: MatchRunner = _main.get_node("MatchRunner") as MatchRunner
	var snap: MatchSnapshot = runner.snapshot
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in snap.unit_count():
		if snap.owner[row] == 1 and snap.type_ids[snap.type_index[row]] == type_id:
			ids.append(snap.unit_id[row])
	if not ids.is_empty() and snap.type_foot_w[snap.type_ids.find(type_id)] > 0:
		return PackedInt32Array([ids[0]])
	return ids


func _strike_button() -> BaseButton:
	return _main.get_node("Hud").find_child("StrikeButton", true, false) as BaseButton


func _profile(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	return null


func _lessons() -> Array[TutorialLessonDef]:
	var found: Array[TutorialLessonDef] = []
	var names: PackedStringArray = DirAccess.get_files_at(LESSON_DIR)
	names.sort()
	for file_name: String in names:
		if file_name.ends_with(".tres"):
			var lesson: TutorialLessonDef = load(LESSON_DIR + file_name) as TutorialLessonDef
			if lesson != null:
				found.append(lesson)
	return found


## Every selection lead-in is driven both ways: with nothing selected the ring stands on the
## lead-in's own anchor (the AllArmy control, or the tile where the type stands), and once exactly
## the lead-in's type is selected it moves on to the beat's target. The mid-play beats get their
## fixture first and the selection is cleared after it. A typo in an anchor tile or a type id fails.
func test_a_selection_lead_in_points_at_its_anchor_and_then_moves_on() -> void:
	var profiles: Array[UiMetrics] = []
	for size: Vector2i in ScreenSizes.ALL:
		profiles.append(_profile(size))
	for profile_name: StringName in EXTRA_PROFILES:
		profiles.append(UiProfiles.by_name(profile_name))
	var found: Array[String] = []
	var driven: int = 0
	for lesson: TutorialLessonDef in _lessons():
		for beat: TutorialBeatDef in lesson.beats:
			var lead: TutorialLeadInDef = _selection_lead_in(beat)
			if lead == null:
				continue
			var pair: String = "%s/%s" % [lesson.id, beat.id]
			for profile: UiMetrics in profiles:
				var label: String = (
					"%s %s %dx%d"
					% [pair, profile.os_name, profile.window_size.x, profile.window_size.y]
				)
				var scenario: ScenarioDef = lesson.scenario
				if MidPlay.has(pair):
					scenario = MidPlay.scenario_for(pair, scenario)
				await _open(lesson, profile, scenario)
				if MidPlay.has(pair):
					_feed.state.close(_feed.state.current)
					var fixture: Object = MidPlay.new(self, _main, _selection, _sidebar)
					await fixture.prepare(pair)
					if not String(fixture.failure).is_empty():
						found.append("%s: fixture: %s" % [label, fixture.failure])
						_close()
						continue
				_feed.state.close(_feed.state.current)
				_selection.clear()
				await _show(lesson, beat)
				found.append_array(await _drive_selection(beat, lead, label))
				driven += 1
				_close()
	assert_int(driven).override_failure_message("no selection lead-in was driven").is_greater(40)
	for line: String in found:
		print("SELECTION ", line)
	assert_array(found).override_failure_message("\n".join(found)).is_empty()


## The beat's first lead-in of kind SELECTED, null when it has none.
func _selection_lead_in(beat: TutorialBeatDef) -> TutorialLeadInDef:
	for step: TutorialLeadInDef in beat.lead_in:
		if step.kind == TutorialConditions.Kind.SELECTED:
			return step
	return null


func _drive_selection(
	beat: TutorialBeatDef, lead: TutorialLeadInDef, label: String
) -> Array[String]:
	var lines: Array[String] = []
	if _director.active_target() != lead:
		lines.append("%s: with nothing selected the ring is not on the selection step" % label)
		return lines
	lines.append_array(_ring_problems(label + " selection step", lead))
	var ids: PackedInt32Array = _own_of(lead.type_id)
	if ids.is_empty():
		lines.append("%s: no own %s to select" % [label, lead.type_id])
		return lines
	if lead.anchor == TutorialBeatDef.Anchor.TILE:  # The ring is on a unit of the type, as drawn.
		var runner: MatchRunner = _main.get_node("MatchRunner") as MatchRunner
		var row: int = runner.snapshot.index_of(ids[0])
		var at: Vector2 = _mark.camera.world_to_screen(
			IsoProjection.ground_to_px(runner.snapshot.pos_x[row], runner.snapshot.pos_y[row])
		)
		var ring: Rect2 = _mark.ring_rect()
		if not ring.grow(ring.size.y / 4.0).has_point(at):  # A unit stands off its tile centre.
			lines.append("%s: the ring %s is not on the %s at %s" % [label, ring, lead.type_id, at])
	if not await _satisfy(lead):
		lines.append("%s: the selection step could not be satisfied" % label)
		return lines
	var next: TutorialLeadInDef = _director.active_target()
	if next == null or beat.lead_in.has(next) and next == lead:
		lines.append(
			"%s: the ring stayed on the selection step after its type was selected" % label
		)
		return lines
	lines.append_array(_ring_problems(label + " after the selection", next))
	return lines


## What a beat leaves behind it: the unfold and the drawer's tab its condition waits for.
func _after(beat: TutorialBeatDef, carried: Dictionary) -> Dictionary:
	var left: Dictionary = carried.duplicate()
	match beat.kind:
		TutorialConditions.Kind.DRAWER_TAB:
			left["unfold"] = HudState.Unfold.DRAWER
			left["tab"] = beat.value
		TutorialConditions.Kind.UNFOLD_OPEN:
			left["unfold"] = beat.value
		TutorialConditions.Kind.UNFOLD_CLOSED:
			left["unfold"] = HudState.Unfold.NONE
		_:
			if MAP_KINDS.has(beat.kind):
				left["unfold"] = HudState.Unfold.NONE  # A gesture on the map folds the drawer.
	return left


## The start states to try for `beat`: what the beats before it leave, then with the player's
## units selected, then with its buildings selected (the order buttons and the Mend card need one).
func _states(carried: Dictionary) -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for select: int in [NONE, UNITS, BUILDINGS, BUILDINGS + 1, BUILDINGS + 2, BUILDINGS + 3]:
		var state: Dictionary = carried.duplicate()
		state["select"] = select
		states.append(state)
	return states


func _enter(state: Dictionary) -> void:
	var strike: BaseButton = _strike_button()
	if strike != null and strike.button_pressed:
		strike.button_pressed = false  # A beat before left the strike aim on.
	_feed.state.close(HudState.Unfold.PAUSE)
	_sidebar.select_tab(int(state["tab"]))
	_selection.clear()
	var select: int = int(state["select"])
	if select == UNITS:
		_selection.set_ids(_own)
	elif select >= BUILDINGS:  # One building at a time: Mend and Sell show for one.
		_selection.set_ids(_own_buildings.slice(select - BUILDINGS, select - BUILDINGS + 1))
	var unfold: HudState.Unfold = state["unfold"] as HudState.Unfold
	if unfold == HudState.Unfold.NONE:
		_feed.state.close(_feed.state.current)
	else:
		_feed.state.open(unfold)
	await await_idle_frame()


## Shows `beat` as the second beat of a two-beat lesson on the director, as the game does.
func _show(lesson: TutorialLessonDef, beat: TutorialBeatDef) -> void:
	var shown: TutorialBeatDef = beat.duplicate() as TutorialBeatDef
	shown.delay_ticks = 0
	shown.after_ai_step = &""
	shown.pause = false
	_director.skip()
	var first: TutorialBeatDef = Lesson.beat("first", TutorialConditions.Kind.NEXT)
	_director.start(Lesson.lesson(String(lesson.id), [first, shown]))
	_director.advance()
	_director.next()
	_director.advance()
	for _frame: int in 3:
		await await_idle_frame()
	if not _mark.visible and not _director.running():
		_mark.show_beat(shown)  # The state met the condition already: judged all the same.
		for _frame: int in 3:
			await await_idle_frame()


func _open(lesson: TutorialLessonDef, profile: UiMetrics, scenario: ScenarioDef = null) -> void:
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	var runner: MatchRunner = _main.get_node("MatchRunner")
	runner.scenario = lesson.scenario if scenario == null else scenario
	runner.paused = true
	add_child(_main)
	await await_idle_frame()
	await await_idle_frame()
	_feed = _main.find_children("*", "HudStateFeed", true, false)[0] as HudStateFeed
	_sidebar = _main.find_children("*", "BuildSidebar", true, false)[0] as BuildSidebar
	_selection = (
		(_main.find_children("*", "PlayerController", true, false)[0] as PlayerController).selection
	)
	_own = MatchRig.units_of(_main, lesson.scenario.local_player)
	_own_buildings = _buildings_of(runner, lesson.scenario.local_player)
	_director = TutorialDirector.new()
	_director.runner = runner
	_director.hud = _feed.state
	_director.selection = _selection
	_director.camera = _main.get_node("Camera") as RtsCamera
	_director.sidebar = _sidebar
	_director.strike_aim = _main.find_children("*", "StrikeAim", true, false)[0] as StrikeAim
	_main.add_child(_director)
	_mark = CoachMark.new()
	_mark.director = _director
	_mark.camera = _director.camera
	_mark.hud_root = _feed.get_parent()
	_feed.get_parent().add_child(_mark)
	await await_idle_frame()


func _buildings_of(runner: MatchRunner, player: int) -> PackedInt32Array:
	var snap: MatchSnapshot = runner.snapshot
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in snap.unit_count():
		if snap.owner[row] == player and WorldSort.is_building(snap, snap.type_index[row]):
			ids.append(snap.unit_id[row])
	return ids


func _close() -> void:
	_director.skip()
	_main.get_parent().remove_child(_main)
	_main.free()
	_main = null
	_mark = null
	_director = null
