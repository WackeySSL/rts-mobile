extends RefCounted
## The rig of the guide's chain suites (plan rows P591, P595). Not a test suite. It builds the main
## scene at a profile with a director and a coach mark on it, puts the HUD into a start state, shows
## a beat and judges the ring on each step of the beat's chain (`ring_problems`: a ring on the
## control or unit the chain names, in the safe rect, not hidden by the card; `touch_proof`: a real
## viewport touch at a unit step's point works). `test_coach_mark_chain_sweep.gd` (the plain start
## states) and the lead-in states suites (the drawer closed, a step undone) share it, so both judge
## by the same checks.

const Lesson: GDScript = preload("res://tests/ui/tutorial/support/lesson_rig.gd")
const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MidPlay: GDScript = preload("res://tests/ui/tutorial/support/midplay_fixture.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const LESSON_DIR: String = "res://data/tutorial/"
const MAIN_SCENE: String = "res://scenes/main.tscn"
const TOLERANCE_PX: float = 0.5
const DRAG_STEPS: int = 4  ## Moves of a pushed touch-drag.
const OVERLAP_PX2: float = 4.0
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

var main: Node
var feed: HudStateFeed
var sidebar: BuildSidebar
var mark: CoachMark
var director: TutorialDirector
var selection: SelectionModel
var camera: RtsCamera
var air: AirLayer
var proofs: Array[String] = []  ## The "lesson/beat WxH" of every touch proof that ran.
var button_hits: Array[String] = []  ## The proof keys where a unit stood under a card button.
var proof_key: String = ""
var sent: Array[Command] = []  ## What the controller sent since the last touch proof.
var own: PackedInt32Array = PackedInt32Array()
var own_buildings: PackedInt32Array = PackedInt32Array()

var _suite: GdUnitTestSuite
var _pressed: int = 0  ## Presses of the card's buttons during a proof's touch-drag.


## `suite` owns the frames, the window and the tree the main scene is added to.
func _init(suite: GdUnitTestSuite) -> void:
	_suite = suite


## The profiles of the sweep: the six sizes of ScreenSizes, then the two small real phones.
func profiles() -> Array[UiMetrics]:
	var found: Array[UiMetrics] = []
	for size: Vector2i in ScreenSizes.ALL:
		found.append(profile_of(size))
	for profile_name: StringName in EXTRA_PROFILES:
		found.append(UiProfiles.by_name(profile_name))
	return found


## Judges `beat` in the mid-play state its fixture builds: a fresh match with the fixture's units
## in the scenario, then the fixture's own taps, then the chain of the beat.
func judge_midplay(
	lesson: TutorialLessonDef, beat: TutorialBeatDef, profile: UiMetrics, pair: String
) -> Array:
	close()
	await open(lesson, profile, MidPlay.scenario_for(pair, lesson.scenario))
	var fixture: Object = MidPlay.new(_suite, main, selection, sidebar)
	feed.state.close(feed.state.current)
	await fixture.prepare(pair)
	var label: String = (
		"%s %s %dx%d" % [pair, profile.os_name, profile.window_size.x, profile.window_size.y]
	)
	if not String(fixture.failure).is_empty():
		return [false, ["%s: fixture: %s" % [label, fixture.failure]] as Array[String]]
	await show(lesson, beat)
	if director.active_target() == null:
		return [false, ["%s: the beat ended before it showed its ring" % label] as Array[String]]
	return await drive(lesson, beat, profile, {"unfold": 0, "tab": 0, "select": NONE})


## Judges `beat` in the first start state that shows its ring and drives its chain to the end.
## Returns [whether a chain of two steps or more was driven, the problems of the first state when
## none was clean].
func judge(
	lesson: TutorialLessonDef,
	beat: TutorialBeatDef,
	profile: UiMetrics,
	carried: Dictionary,
	tag: String = "",
	hand: bool = false
) -> Array:
	var first: Array[String] = []
	for state: Dictionary in states(carried):
		await enter(state)
		await show(lesson, beat)
		var driven: Array = await drive(lesson, beat, profile, state, tag, hand)
		if (driven[1] as Array[String]).is_empty():
			return driven
		if first.is_empty():
			first = driven[1] as Array[String]
	return [false, first]


## Walks the chain of the beat on show: checks the ring on the active step, satisfies it, checks
## the next, up to the beat's own target. The result: [a chain of two steps or more was driven,
## the problems, the steps judged].
func drive(
	lesson: TutorialLessonDef,
	beat: TutorialBeatDef,
	profile: UiMetrics,
	state: Dictionary,
	tag: String = "",
	hand: bool = false
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
	if not tag.is_empty():
		label += " " + tag
	var steps: int = 0
	for _round: int in beat.lead_in.size() + 1:
		var step: TutorialLeadInDef = director.active_target()
		if step == null:  # The state met the beat's condition already: it ended, nothing to show.
			return [false, lines]
		var problems: Array[String] = ring_problems("%s step %d" % [label, steps], step)
		if hand:
			problems.append_array(hand_problems("%s step %d" % [label, steps], beat, step))
		lines.append_array(problems)
		if not problems.is_empty():
			break
		steps += 1
		if step.anchor == TutorialBeatDef.Anchor.UNIT:
			proof_key = (
				"%s/%s %dx%d" % [lesson.id, beat.id, profile.window_size.x, profile.window_size.y]
			)
			lines.append_array(await touch_proof("%s step %d" % [label, steps - 1], beat, step))
			if beat.lead_in.has(step) and director.active_target() != step:
				continue  # The touch passed the lead-in step: the next step is judged.
		if not beat.lead_in.has(step):  # The beat's own target: the end of the chain.
			break
		if not await satisfy(step):
			break
		var next: TutorialLeadInDef = director.active_target()
		if next == step:
			lines.append("%s: the ring stayed on step %d after it was satisfied" % [label, steps])
			break
	return [steps >= 2, lines, steps]


## What is wrong with the hand on `step` (ADR 0048 section 6), one line each: a step on a control or
## a unit has a hand, drawn, with a box in the safe rect, unless the beat or step says NONE. A
## lead-in step is always a TAP, or the DRAG that brings a unit out from under the HUD.
func hand_problems(label: String, beat: TutorialBeatDef, step: TutorialLeadInDef) -> Array[String]:
	var lines: Array[String] = []
	var anchor: TutorialBeatDef.Anchor = step.anchor
	if anchor != TutorialBeatDef.Anchor.CONTROL and anchor != TutorialBeatDef.Anchor.UNIT:
		return lines
	var lead: bool = beat.lead_in.has(step)
	var explicit_none: bool = (
		step.gesture == TutorialBeatDef.Gesture.NONE
		and (not lead or anchor == TutorialBeatDef.Anchor.UNIT)
	)
	if explicit_none:
		return lines
	var plan: GuideHintPlan = mark.gesture_plan()
	var hand: Control = mark.find_child("GestureHint", true, false) as Control
	if plan.kind == TutorialBeatDef.Gesture.NONE:
		lines.append("%s: no hand for %s" % [label, step.anchor_control])
	elif hand == null or not hand.visible:
		lines.append("%s: the hand is set (%d) but not drawn" % [label, plan.kind])
	else:
		var safe: Rect2 = SafeAreaMargin.rect_inside(
			_suite.get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
		)
		if not plan.bounds.has_area() or not safe.grow(TOLERANCE_PX).encloses(plan.bounds):
			lines.append(
				"%s: the hand's box %s is not in the safe rect %s" % [label, plan.bounds, safe]
			)
	return lines


## What is wrong with the ring on `step`, one line each.
func ring_problems(label: String, step: TutorialLeadInDef) -> Array[String]:
	var lines: Array[String] = []
	if not mark.visible:
		lines.append("%s: the mark is not showing" % label)
		return lines
	var ring: Rect2 = mark.ring_rect()
	if not ring.has_area():
		lines.append("%s: no ring for %s" % [label, step.anchor_control])
		return lines
	var safe: Rect2 = SafeAreaMargin.rect_inside(
		_suite.get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
	)
	if not safe.grow(TOLERANCE_PX).encloses(ring):
		lines.append("%s: the ring %s is outside the safe rect %s" % [label, ring, safe])
	if step.anchor == TutorialBeatDef.Anchor.CONTROL:
		var target: Control = mark.target_control()
		if target == null:
			lines.append("%s: no control %s under the ring" % [label, step.anchor_control])
		else:
			if target.name != step.anchor_control:
				lines.append("%s: the ring is on %s" % [label, target.name])
			var button: BaseButton = target as BaseButton
			if not target.is_visible_in_tree() or (button != null and button.disabled):
				lines.append("%s: %s is hidden or disabled" % [label, target.name])
	if step.anchor == TutorialBeatDef.Anchor.UNIT:
		var unit: GuideUnitAnchor = mark.unit_anchor()
		if unit.unit_id < 0:
			lines.append("%s: no unit under the ring (selector %s)" % [label, step.unit.type_id])
		elif unit.in_field and not ring.grow(ring.size.y / 4.0).has_point(unit.point):
			lines.append("%s: the ring %s is not on the unit at %s" % [label, ring, unit.point])
	if mark.card_open() and not mark.see_through():
		if mark.card_rect().intersection(ring).get_area() > OVERLAP_PX2:
			lines.append("%s: the card %s hides the ring %s" % [label, mark.card_rect(), ring])
	return lines


## Does what the player does to pass `step`; false when the sweep has no hand for its kind.
func satisfy(step: TutorialLeadInDef) -> bool:
	match step.kind:
		TutorialConditions.Kind.UNFOLD_OPEN:
			feed.state.open(step.value as HudState.Unfold)
		TutorialConditions.Kind.DRAWER_TAB:
			feed.state.open(HudState.Unfold.DRAWER)
			sidebar.select_tab(step.value)
		TutorialConditions.Kind.SELECTED:
			var ids: PackedInt32Array = own_of(step.type_id)
			if ids.is_empty():
				return false  # A type that is not in the match: a typo in the data.
			selection.set_ids(ids)
		TutorialConditions.Kind.STRIKE_AIMING:
			var button: BaseButton = strike_button()
			if button == null or not button.is_visible_in_tree() or button.disabled:
				return false
			button.button_pressed = true  # The real strike button, as a finger toggles it.
		_:
			return false
	for _frame: int in 3:
		await _suite.await_idle_frame()
	return true


## The player's rows of `type_id` (any unit when empty): the whole type for units, the first one
## for a building (a tap picks one building).
func own_of(type_id: StringName) -> PackedInt32Array:
	if type_id == &"":
		return own
	var runner: MatchRunner = main.get_node("MatchRunner") as MatchRunner
	var snap: MatchSnapshot = runner.snapshot
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in snap.unit_count():
		if snap.owner[row] == 1 and snap.type_ids[snap.type_index[row]] == type_id:
			ids.append(snap.unit_id[row])
	if not ids.is_empty() and snap.type_foot_w[snap.type_ids.find(type_id)] > 0:
		return PackedInt32Array([ids[0]])
	return ids


func strike_button() -> BaseButton:
	return main.get_node("Hud").find_child("StrikeButton", true, false) as BaseButton


func profile_of(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	return null


func lessons() -> Array[TutorialLessonDef]:
	var found: Array[TutorialLessonDef] = []
	var names: PackedStringArray = DirAccess.get_files_at(LESSON_DIR)
	names.sort()
	for file_name: String in names:
		if file_name.ends_with(".tres"):
			var lesson: TutorialLessonDef = load(LESSON_DIR + file_name) as TutorialLessonDef
			if lesson != null:
				found.append(lesson)
	return found


## What a beat leaves behind it: the unfold and the drawer's tab its condition waits for.
func after(beat: TutorialBeatDef, carried: Dictionary) -> Dictionary:
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
func states(carried: Dictionary) -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for select: int in [NONE, UNITS, BUILDINGS, BUILDINGS + 1, BUILDINGS + 2, BUILDINGS + 3]:
		var state: Dictionary = carried.duplicate()
		state["select"] = select
		states.append(state)
	return states


func enter(state: Dictionary) -> void:
	var strike: BaseButton = strike_button()
	if strike != null and strike.button_pressed:
		strike.button_pressed = false  # A beat before left the strike aim on.
	feed.state.close(HudState.Unfold.PAUSE)
	sidebar.select_tab(int(state["tab"]))
	selection.clear()
	var select: int = int(state["select"])
	if select == UNITS:
		selection.set_ids(own)
	elif select >= BUILDINGS:  # One building at a time: Mend and Sell show for one.
		selection.set_ids(own_buildings.slice(select - BUILDINGS, select - BUILDINGS + 1))
	var unfold: HudState.Unfold = state["unfold"] as HudState.Unfold
	if unfold == HudState.Unfold.NONE:
		feed.state.close(feed.state.current)
	else:
		feed.state.open(unfold)
	await _suite.await_idle_frame()


## Shows `beat` as the second beat of a two-beat lesson on the director, as the game does.
func show(lesson: TutorialLessonDef, beat: TutorialBeatDef) -> void:
	var shown: TutorialBeatDef = beat.duplicate() as TutorialBeatDef
	shown.delay_ticks = 0
	shown.after_ai_step = &""
	shown.pause = false
	director.skip()
	var first: TutorialBeatDef = Lesson.beat("first", TutorialConditions.Kind.NEXT)
	director.start(Lesson.lesson(String(lesson.id), [first, shown]))
	director.advance()
	director.next()
	director.advance()
	for _frame: int in 3:
		await _suite.await_idle_frame()
	if not mark.visible and not director.running():
		mark.show_beat(shown)  # The state met the condition already: judged all the same.
		for _frame: int in 3:
			await _suite.await_idle_frame()


func open(lesson: TutorialLessonDef, profile: UiMetrics, scenario: ScenarioDef = null) -> void:
	UiScale.set_override(profile)
	_suite.get_window().size = profile.window_size
	await _suite.await_idle_frame()
	main = (load(MAIN_SCENE) as PackedScene).instantiate()
	var runner: MatchRunner = main.get_node("MatchRunner")
	runner.scenario = lesson.scenario if scenario == null else scenario
	runner.paused = true
	_suite.add_child(main)
	await _suite.await_idle_frame()
	await _suite.await_idle_frame()
	feed = main.find_children("*", "HudStateFeed", true, false)[0] as HudStateFeed
	sidebar = main.find_children("*", "BuildSidebar", true, false)[0] as BuildSidebar
	selection = (
		(main.find_children("*", "PlayerController", true, false)[0] as PlayerController).selection
	)
	own = MatchRig.units_of(main, lesson.scenario.local_player)
	own_buildings = _buildings_of(runner, lesson.scenario.local_player)
	director = TutorialDirector.new()
	director.runner = runner
	director.hud = feed.state
	director.selection = selection
	director.camera = main.get_node("Camera") as RtsCamera
	director.sidebar = sidebar
	director.strike_aim = main.find_children("*", "StrikeAim", true, false)[0] as StrikeAim
	main.add_child(director)
	camera = director.camera
	air = main.find_children("*", "AirLayer", true, false)[0] as AirLayer
	var controller: PlayerController = (
		main.find_children("*", "PlayerController", true, false)[0] as PlayerController
	)
	sent.clear()
	controller.command_sink = _take_command
	mark = CoachMark.new()
	mark.director = director
	mark.camera = director.camera
	mark.runner = runner
	mark.ground_layer = main.find_children("*", "UnitLayer", true, false)[0] as UnitLayer
	mark.air_layer = air
	mark.hud_root = feed.get_parent()
	feed.get_parent().add_child(mark)
	await _suite.await_idle_frame()


## What a finger does on a `UNIT` step: the unit is panned into the field when it is not in it (as
## the bot does), a real screen touch is pushed at `target_point()` and the unit must answer: a
## selecting step selects it, `attack` (the army selected) sends an ATTACK on it. For a flyer the
## point is its hull, `rig.lift` times the zoom above the shadow's.
func touch_proof(label: String, beat: TutorialBeatDef, step: TutorialLeadInDef) -> Array[String]:
	var lines: Array[String] = []
	var unit: GuideUnitAnchor = mark.unit_anchor()
	var id: int = unit.unit_id
	if id < 0:
		return lines  # `_ring_problems` told it.
	proofs.append(proof_key)
	# Under a visible card button the unit is not in the field and the hand is not a TAP: it drags
	# (ADR 0048 section 13.5). A finger then pans a unit that is out of the field to where it can be
	# tapped: first centred, then on the lower part of the screen.
	# The check here uses the plain rect, while the anchor keeps "under" out to the 8 dp band. They
	# agree where it matters: `in_field` is true only outside the grown rect, hence outside the plain
	# one, so the pan loop (ends on `in_field`) and the final check (plain rect) cannot disagree.
	if _under_a_card_button(unit.point):
		button_hits.append(proof_key)
		if unit.in_field:
			lines.append("%s: unit %d is in the field under a card button" % [label, id])
		if mark.gesture_plan().kind == TutorialBeatDef.Gesture.TAP:
			lines.append("%s: the hand taps unit %d under a card button" % [label, id])
		lines.append_array(await _drag_proof(label, id))
	var view: Rect2 = _suite.get_viewport().get_visible_rect()
	for want: Vector2 in [Vector2(0.5, 0.5), Vector2(0.5, 0.65), Vector2(0.25, 0.65)]:
		if unit.in_field:
			break
		var aim: Vector2 = view.position + view.size * want
		var home: Vector2 = camera.screen_to_world(unit.point)
		camera.centre_on(home + (view.get_center() - aim) / camera.zoom.x)
		camera.force_update_scroll()
		for _frame: int in 3:
			await _suite.await_idle_frame()
	if not unit.in_field or unit.unit_id != id or _under_a_card_button(unit.point):
		lines.append(
			"%s: unit %d is not in the field after centring (%s)" % [label, id, unit.point]
		)
		return lines
	if unit.flyer:
		var rig: AirLayer.Rig = air.rig_of(id)
		var shadow: Vector2 = camera.world_to_screen(rig.global_position)
		var gap: Vector2 = shadow - unit.point
		if absf(gap.x) > TOLERANCE_PX or absf(gap.y - rig.lift * camera.zoom.y) > TOLERANCE_PX:
			lines.append(
				"%s: the point %s is not the hull (shadow %s)" % [label, unit.point, shadow]
			)
	var attack: bool = (
		beat.kind == TutorialConditions.Kind.ENEMY_LOSSES and not beat.lead_in.has(step)
	)
	if not attack:
		selection.clear()
	sent.clear()
	var at: Vector2 = unit.point
	TouchEvents.press(_suite.get_viewport(), 0, at)
	TouchEvents.release(_suite.get_viewport(), 0, at)
	for _frame: int in 3:
		await _suite.await_idle_frame()
	if attack:
		var hit: bool = false
		for command: Command in sent:
			hit = hit or (command.type == Command.Type.ATTACK and command.target_id == id)
		if not hit:
			lines.append("%s: a touch at %s sent no ATTACK on unit %d" % [label, at, id])
	elif not selection.selected.has(id):
		lines.append("%s: a touch at %s did not select unit %d" % [label, at, id])
	return lines


## The hand's drag for a unit under a card button (plan row P593b-4): it starts outside every
## visible button grown by the band and outside every HUD rect, and a real touch-drag from there
## along its vector pans the camera and presses nothing: no button's `pressed` fires, the beat and
## its step stay.
func _drag_proof(label: String, id: int) -> Array[String]:
	var lines: Array[String] = []
	var plan: GuideHintPlan = mark.gesture_plan()
	if plan.kind != TutorialBeatDef.Gesture.DRAG:
		lines.append("%s: the hand over unit %d under a card button is not a drag" % [label, id])
		return lines
	var dp: float = mark._dp
	var band: float = GuideUnitAnchor.THROUGH_BAND_DP * dp
	var buttons: Array[BaseButton] = []
	for node: Node in mark.find_children("*", "BaseButton", true, false):
		var button: BaseButton = node as BaseButton
		if button.is_visible_in_tree():
			buttons.append(button)
			if button.get_global_rect().grow(band).has_point(plan.point):
				lines.append(
					"%s: the drag starts at %s under %s" % [label, plan.point, button.name]
				)
	for key: StringName in mark._dock_rects:
		var rect: Rect2 = mark._dock_rects[key]
		if key != HudCorners.CARD and rect.has_point(plan.point):
			lines.append("%s: the drag starts at %s under HUD part %s" % [label, plan.point, key])
	# What the hint draws at the start (plan row P593b-5): the press ring and the hand's box.
	var side: float = mark.settings.hint_size_dp * dp
	var reach: float = GestureHint.ring_reach_dp(mark.settings.hint_size_dp, 1) * dp
	var ring: Rect2 = Rect2(plan.point - Vector2(reach, reach), Vector2(reach, reach) * 2.0)
	var hand: Rect2 = Rect2(plan.point - GestureHint.POINT_TIP * side, Vector2(side, side))
	for box: Rect2 in [ring, hand]:
		for button: BaseButton in buttons:
			if box.intersects(button.get_global_rect()):
				lines.append("%s: the hint drawn at %s meets %s" % [label, plan.point, button.name])
		for key: StringName in mark._dock_rects:
			if key != HudCorners.CARD and box.intersects(mark._dock_rects[key]):
				lines.append(
					"%s: the hint drawn at %s meets HUD part %s" % [label, plan.point, key]
				)
	var before: Vector2 = camera.position
	var beat: TutorialBeatDef = director.current_beat()
	var progress: Vector2i = director.progress()
	var aim: TutorialLeadInDef = director.active_target()
	var step: Vector2 = plan.vector_dp * dp / DRAG_STEPS
	var at: Vector2 = plan.point
	_pressed = 0
	for button: BaseButton in buttons:
		button.pressed.connect(_count_press)
	var view: Viewport = _suite.get_viewport()
	TouchEvents.press(view, 0, at)
	for _move: int in DRAG_STEPS:
		at += step
		TouchEvents.drag(view, 0, at, step)
		await _suite.await_idle_frame()
	TouchEvents.release(view, 0, at)
	for _frame: int in 3:
		await _suite.await_idle_frame()
	for button: BaseButton in buttons:
		if is_instance_valid(button):
			button.pressed.disconnect(_count_press)
	if camera.position.is_equal_approx(before):
		lines.append("%s: a touch-drag from %s did not pan the camera" % [label, plan.point])
	if _pressed > 0:
		lines.append("%s: a touch-drag from %s fired a card button's pressed" % [label, plan.point])
	var held: bool = director.current_beat() == beat and director.progress() == progress
	if not held or director.active_target() != aim:
		lines.append(
			"%s: the beat or its step changed after a touch-drag from %s" % [label, plan.point]
		)
	return lines


func _count_press() -> void:
	_pressed += 1


## Whether a button of the card (Next, Skip, the tab) stands at screen point `at`.
func _under_a_card_button(at: Vector2) -> bool:
	for node: Node in mark.find_children("*", "BaseButton", true, false):
		var button: BaseButton = node as BaseButton
		if button.is_visible_in_tree() and button.get_global_rect().has_point(at):
			return true
	return false


## The controller's sink: a copy kept for the touch proof, and the queue takes it as it would.
func _take_command(command: Command) -> void:
	sent.append(command)
	CommandQueue.submit(command)


func _buildings_of(runner: MatchRunner, player: int) -> PackedInt32Array:
	var snap: MatchSnapshot = runner.snapshot
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in snap.unit_count():
		if snap.owner[row] == player and WorldSort.is_building(snap, snap.type_index[row]):
			ids.append(snap.unit_id[row])
	return ids


func close() -> void:
	director.skip()
	main.get_parent().remove_child(main)
	main.free()
	main = null
	mark = null
	director = null
