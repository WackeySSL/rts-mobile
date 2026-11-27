extends GdUnitTestSuite
## The sweep of the docked card (plan rows P543g and P588, ADR 0048 sections 1, 3 and 9): for every
## beat of every lesson file in `data/tutorial/` (read from the folder, so a lesson or a beat added
## later is covered at once), at the six sizes of ADR 0015 section 6 and the two small real phones,
## the real HUD in the state the beat expects:
## - the card is inside the dock and on no `HudCorners` part but the economy card (and covers no
##   visible, enabled HUD button of its own), and not the tile a TILE beat points at;
## - the prompt fits the dock's height cap without scrolling, at every size and in every beat;
## - the card stands 16 dp from an ad band;
## - where the card covers the beat's control (a modal's button, the ghost's check mark) it is
##   see-through and a pushed touch reaches the control through it, and it is see-through for no
##   other HUD control, but for the hand's reach (P592: the gesture hint stays inside the safe rect
##   and its box joins the see-through test);
## - the dock has room on the six sizes; a fold (small phone only) shows the tab in the safe rect.
## The state of a beat is what the beats before it leave (a drawer opened on a tab stays open until
## a beat closes it), plus the state its own condition asks for (DRAWER_TAB: the drawer on that
## tab; UNFOLD_OPEN and UNFOLD_CLOSED: that unfold open), plus, when the named control is not on
## screen in that state, the first state that shows it (a selection, a tab of the drawer, the
## radar, the card, the pause menu).

const Lesson: GDScript = preload("res://tests/ui/tutorial/support/lesson_rig.gd")
const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const LESSON_DIR: String = "res://data/tutorial/"
const MAIN_SCENE: String = "res://scenes/main.tscn"
const OVERLAP_PX2: float = 4.0  ## Less area than this is rounding, not a covered button.
const TILE_MARGIN_DP: float = 8.0
const AD_GAP_DP: float = 16.0
## Controls that follow the world (ADR 0048 section 3): the card may be see-through over them.
const WORLD_CONTROLS: Array[StringName] = [&"PlaceConfirm"]
const TABS: int = 5
const TOLERANCE_PX: float = 0.5
## Real phones of ui_profiles.gd run besides the six sizes; only these may fold the card to its tab.
const EXTRA_PROFILES: Array[StringName] = [&"web_phone_small", &"web_phone_portrait"]
## Kinds a player ends with a gesture on the map, which folds the drawer (HudState.map_gesture).
const MAP_KINDS: Array[TutorialConditions.Kind] = [
	TutorialConditions.Kind.SELECTED,
	TutorialConditions.Kind.UNITS_IN_AREA,
	TutorialConditions.Kind.BUILDING_PLACED,
	TutorialConditions.Kind.PLACING,
	TutorialConditions.Kind.ZOOM_LEVEL,
	TutorialConditions.Kind.CAMERA_PANNED,
	TutorialConditions.Kind.ENEMY_LOSSES,
	TutorialConditions.Kind.HARVESTED,
	TutorialConditions.Kind.STRIKE_AIMED,
	TutorialConditions.Kind.STRIKE_PENDING,
	TutorialConditions.Kind.MATCH_WON,
]
const GROUPS: int = 3  ## Control groups the column holds.

var _window_size_before: Vector2i
var _dir: String = ""
var _main: Node
var _feed: HudStateFeed
var _sidebar: BuildSidebar
var _layer: Node
var _mark: CoachMark
var _director: TutorialDirector
var _selection: SelectionModel
var _own: PackedInt32Array = PackedInt32Array()
var _pushed: int = 0
var _folds: int = 0
var _tabs: int = 0
var _unfolds: int = 0
var _over: int = 0
var _pushes: int = 0
var _parts_now: Dictionary[StringName, Rect2] = {}


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	_dir = "user://test_coach_sweep_%d" % Time.get_ticks_usec()
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


func test_the_card_covers_no_control_the_beat_needs_in_any_lesson_at_the_six_sizes() -> void:
	var lessons: Array[TutorialLessonDef] = _lessons()
	var profiles: Array[UiMetrics] = []
	for size: Vector2i in ScreenSizes.ALL:
		profiles.append(_profile(size))
	var extras: Array[UiMetrics] = []
	for profile_name: StringName in EXTRA_PROFILES:
		extras.append(UiProfiles.by_name(profile_name))
	profiles.append_array(extras)
	_folds = 0
	_tabs = 0
	_unfolds = 0
	_over = 0
	_pushes = 0
	assert_int(lessons.size()).is_greater_equal(4)
	var seen: int = 0
	var found: Array[String] = []
	for lesson: TutorialLessonDef in lessons:
		for profile: UiMetrics in profiles:
			var strict: bool = not extras.has(profile)
			await _open(lesson, profile)
			var carried: Dictionary = {
				"unfold": HudState.Unfold.NONE, "tab": 0, "select": false, "groups": 0
			}
			for beat: TutorialBeatDef in lesson.beats:
				for state: Dictionary in _states(beat, carried):
					var tried: Array[Dictionary] = [state]
					while not tried.is_empty():
						var now: Dictionary = tried.pop_front()
						await _enter(now)
						await _show(lesson, beat)
						seen += 1
						found.append_array(await _checks(lesson, beat, profile, now, strict))
						var missing: bool = (
							_aimed(beat).anchor == TutorialBeatDef.Anchor.CONTROL
							and _mark.target_control() == null
						)
						if missing and not bool(now["select"]):  # The control may need a selection.
							var picked: Dictionary = now.duplicate()
							picked["select"] = true
							tried.append(picked)
				carried = _after(beat, carried)
			_close()
	assert_int(seen).is_greater(100)
	for line: String in found:
		print("SWEEP ", line)
	print("FOLDS ", _folds, " TABS ", _tabs, " OVER_CAP ", _over, " PUSHES ", _pushes)
	assert_int(_tabs).override_failure_message("no folded tab was exercised").is_greater(100)
	assert_int(_unfolds).override_failure_message("no unfold was exercised").is_greater(100)
	assert_array(found).override_failure_message("\n".join(found)).is_empty()


## The lessons of the folder, every file whose resource is a lesson.
## The profile of the six sizes that has window size `size`.
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
	found.append(_chained_lesson(found[0]))
	return found


## A fixture, not lesson data: one beat that chains BUILD, then the Infantry tab, on `base`'s
## scenario. The sweep fails if the mark ignores the chain (ring on the tab with the drawer shut).
func _chained_lesson(base: TutorialLessonDef) -> TutorialLessonDef:
	var beat: TutorialBeatDef = Lesson.beat(
		"chain",
		TutorialConditions.Kind.DRAWER_TAB,
		{
			"anchor": TutorialBeatDef.Anchor.CONTROL,
			"anchor_control": &"TabInfantry",
			"value": World.Tab.INFANTRY,
			"lead_in":
			[
				Lesson.lead_in(
					"BuildButton", TutorialConditions.Kind.UNFOLD_OPEN, HudState.Unfold.DRAWER
				)
			]
		}
	)
	var made: TutorialLessonDef = Lesson.lesson("chain-fixture", [beat])
	made.scenario = base.scenario
	made.title_key = base.title_key
	return made


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


## The step of `beat`'s chain the player is on in the HUD as the sweep left it: what the ring must
## point at (ADR 0048 section 5). A beat with no lead-in is its own anchor.
func _aimed(beat: TutorialBeatDef) -> TutorialLeadInDef:
	var ctx: TutorialContext = TutorialContext.new()
	ctx.snapshot = _director.runner.snapshot  # A SELECTED step reads the selection's types.
	ctx.hud = _feed.state
	ctx.selection = _selection
	ctx.drawer_tab = _sidebar.tab
	if not _director.running():
		# The state met the beat's condition already (a saved group), so the director shows no
		# chain and the mark judges the card on the beat's own anchor (`_show`).
		return TutorialChain.final_step(beat)
	var step: int = TutorialChain.active(beat, ctx)
	return beat.lead_in[step] if step < beat.lead_in.size() else TutorialChain.final_step(beat)


## The HUD states the card of `beat` is judged in.
func _states(beat: TutorialBeatDef, carried: Dictionary) -> Array[Dictionary]:
	var states: Array[Dictionary] = [carried]
	var own: Dictionary = carried.duplicate()
	match beat.kind:
		TutorialConditions.Kind.DRAWER_TAB:
			own["unfold"] = HudState.Unfold.DRAWER
			own["tab"] = beat.value
		TutorialConditions.Kind.UNFOLD_OPEN, TutorialConditions.Kind.UNFOLD_CLOSED:
			own["unfold"] = beat.value
	if own != carried:
		states.append(own)
	if beat.kind == TutorialConditions.Kind.GROUP_SAVED or beat.anchor_control == &"AddGroup":
		for saved: int in GROUPS + 1:  # The column with 0 to 3 chips: the anchor moves.
			for selected: bool in [true, false]:
				var chips: Dictionary = carried.duplicate()
				chips["select"] = selected
				chips["groups"] = saved
				states.append(chips)
	return states


## Puts the HUD in `state`: the unfold, the drawer's tab and a selection of the player's units.
func _enter(state: Dictionary) -> void:
	_feed.state.close(HudState.Unfold.PAUSE)
	_sidebar.select_tab(int(state["tab"]))
	_selection.clear()
	for slot: int in range(1, GROUPS + 1):
		_selection.assign_group(slot)  # An empty selection empties the group.
	_selection.set_ids(_own)
	for slot: int in range(1, int(state["groups"]) + 1):
		_selection.assign_group(slot)
	if not bool(state["select"]):
		_selection.clear()  # The groups stay saved; nothing is selected.
	var unfold: HudState.Unfold = state["unfold"] as HudState.Unfold
	if unfold == HudState.Unfold.NONE:
		_feed.state.close(_feed.state.current)
	else:
		_feed.state.open(unfold)
	await await_idle_frame()


## Shows `beat` as a one-beat lesson on the director, so its Next button is the real one.
func _show(lesson: TutorialLessonDef, beat: TutorialBeatDef) -> void:
	var shown: TutorialBeatDef = beat.duplicate() as TutorialBeatDef
	shown.delay_ticks = 0
	shown.after_ai_step = &""
	shown.pause = false
	_director.skip()
	if beat == lesson.beats[0]:  # The lesson's first card: Skip shows.
		_director.start(Lesson.lesson(String(lesson.id), [shown]))
		_director.advance()
	else:  # A later card: a read-only first beat is done, so Skip is gone as in the game.
		var first: TutorialBeatDef = shown.duplicate() as TutorialBeatDef
		first.kind = TutorialConditions.Kind.NEXT
		_director.start(Lesson.lesson(String(lesson.id), [first, shown]))
		_director.advance()
		_director.next()
		_director.advance()
	for _frame: int in 3:
		await await_idle_frame()
	if not _mark.visible and not _director.running():
		# The state already met the condition (a saved group): the card is judged all the same.
		_mark.show_beat(shown)
		for _frame: int in 3:
			await await_idle_frame()


## What is wrong with the card in the state on show, one line each.
func _checks(
	lesson: TutorialLessonDef,
	beat: TutorialBeatDef,
	profile: UiMetrics,
	state: Dictionary,
	strict: bool
) -> Array[String]:
	var lines: Array[String] = []
	if not _mark.visible:
		return lines  # A menu covers the HUD and the mark stands down.
	var dp: float = UiScale.base_px_per_dp()
	var label: String = (
		"%s/%s %s %dx%d unfold=%d tab=%d select=%s groups=%d"
		% [
			lesson.id,
			beat.id,
			profile.os_name,
			profile.window_size.x,
			profile.window_size.y,
			state["unfold"],
			state["tab"],
			state["select"],
			state["groups"]
		]
	)
	var aim: TutorialLeadInDef = _aimed(beat)
	var target: Control = _mark.target_control()
	if target != null and target.name != aim.anchor_control:
		lines.append(
			"%s: the ring is on %s, the chain says %s" % [label, target.name, aim.anchor_control]
		)
	if (
		target == null
		and aim.anchor == TutorialBeatDef.Anchor.CONTROL
		and not beat.lead_in.is_empty()
		and _director.running()
	):
		lines.append(
			(
				"%s: a chained beat's step %s has no control under the ring"
				% [label, aim.anchor_control]
			)
		)
	var dock: Rect2 = _mark.dock_rect()
	if not GuideDock.has_room(dock, dp):
		_folds += 1
		if strict:
			lines.append("%s: no room for the card, it folds to its tab" % label)
		lines.append_array(_tab_checks(label, dock))
		return lines
	var card: Rect2 = _mark.card_rect()
	if _mark.prompt_scrolls():
		_over += 1
		lines.append("%s: the prompt scrolls, the dock is %s high" % [label, dock.size.y])
	if not dock.grow(TOLERANCE_PX).encloses(card):
		lines.append("%s: the card %s is outside the dock %s" % [label, card, dock])
	for part: StringName in [&"Skip", &"Next"]:  # The card's own buttons stand on its panel.
		var own: Button = _mark.find_child(String(part), true, false) as Button
		if own != null and own.is_visible_in_tree():
			if not _mark.card_rect().grow(TOLERANCE_PX).encloses(own.get_global_rect()):
				lines.append("%s: %s is outside the card %s" % [label, part, card])
	var needs: float = _mark.find_child("Card", true, false).get_combined_minimum_size().y
	if _mark.card_rect().size.y + TOLERANCE_PX < needs:
		lines.append("%s: the card is %s high, its text needs %s" % [label, card.size.y, needs])
	_read_parts()
	for part: StringName in _parts_now:
		var rect: Rect2 = _parts_now[part]
		if part != HudCorners.CARD and card.intersection(rect).get_area() > OVERLAP_PX2:
			lines.append("%s: the card covers the HUD part %s %s" % [label, part, rect])
	var scope: Node = _layer
	for modal: Node in _layer.find_children("*", "ModalFrame", true, false):
		if (modal as Control).is_visible_in_tree():
			scope = modal  # A menu takes every touch: the buttons behind it cannot be tapped.
	if scope == _layer:  # In a modal the card's body passes touches, so its buttons are no check.
		for node: Node in scope.find_children("*", "BaseButton", true, false):
			var button: BaseButton = node as BaseButton
			if button.disabled or _mark.is_ancestor_of(button) or not button.is_visible_in_tree():
				continue
			var shown: Rect2 = _on_screen(button)
			if card.intersection(shown).get_area() > OVERLAP_PX2:
				lines.append("%s: the card covers %s %s" % [label, _path(button), shown])
	else:  # Over a modal Skip hides and Next stays only 8 dp clear of the menu's buttons.
		for own: Button in [
			_mark.find_child("Skip"), _mark.find_child("Next"), _mark.find_child("Tab")
		]:
			if own == null or not own.is_visible_in_tree():
				continue
			var mine: Rect2 = own.get_global_rect().grow(UiScale.dp(8.0) - 0.01)
			for node: Node in scope.find_children("*", "BaseButton", true, false):
				var other: Control = node as Control
				if other.is_visible_in_tree() and mine.intersects(_on_screen(other)):
					lines.append("%s: %s is under 8 dp from %s" % [label, own.name, _path(other)])
	var apart: Rect2 = card.grow(AD_GAP_DP * dp - TOLERANCE_PX)
	for node: Node in scope.find_children("*", "AdBannerBand", true, false):
		var band: Control = node as Control
		if band.is_visible_in_tree() and apart.intersects(_on_screen(band)):
			lines.append("%s: the card is under %s dp from the ad band" % [label, AD_GAP_DP])
	lines.append_array(await _through(label, beat, card, scope))
	lines.append_array(_tab_checks(label, dock))
	_tab_press()  # Fold the card to its tab: the tab stands in its place and the card is gone.
	await await_idle_frame()
	_folds += 1
	_tabs += 1
	if _mark.card_open():
		lines.append("%s: a tap on the tab did not fold the card" % label)
	if _director.current != null and _mark.visible:  # The beat may have ended meanwhile.
		lines.append_array(_tab_checks(label, dock))
	_tab_press()
	await await_idle_frame()
	_unfolds += 1
	if _director.current != null and _mark.visible and not _mark.card_open():  # Not ended meanwhile.
		lines.append("%s: a second tap on the tab did not unfold the card" % label)
	if aim.anchor == TutorialBeatDef.Anchor.TILE:
		var body: Control = _mark.find_child("Card", true, false) as Control
		var camera: RtsCamera = _main.get_node("Camera") as RtsCamera
		var world: Vector2 = IsoProjection.cell_centre_px(aim.anchor_tile.x, aim.anchor_tile.y)
		var point: Vector2 = camera.world_to_screen(world)
		if card.grow(UiScale.dp(TILE_MARGIN_DP)).has_point(point):  # Allowed: the card is see-through.
			if not _mark.see_through() or body.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				lines.append(
					"%s: the card covers the tile %s at %s" % [label, aim.anchor_tile, point]
				)
	return lines


## The tab, folded or open: at least 48 dp, inside the safe rect, on no `HudCorners` part (the
## economy card and the attack toast's slot aside), and on the dock's scope-side corner when the
## dock has room. `dock` is the one in force.
func _tab_checks(label: String, dock: Rect2) -> Array[String]:
	var lines: Array[String] = []
	var tab: Rect2 = _mark.tab_rect()
	var floor_px: float = UiScale.dp(48.0) - TOLERANCE_PX
	if not tab.has_area():
		lines.append("%s: the tab does not show" % label)
		return lines
	if tab.size.x < floor_px or tab.size.y < floor_px:
		lines.append("%s: the tab %s is under 48 dp" % [label, tab])
	if not _safe().grow(TOLERANCE_PX).encloses(tab):
		lines.append("%s: the tab %s is not inside the safe rect" % [label, tab])
	var has_room: bool = GuideDock.has_room(dock, UiScale.base_px_per_dp())
	for own: Button in [_mark.find_child("Skip"), _mark.find_child("Next")]:
		if own != null and own.is_visible_in_tree():
			if tab.grow(UiScale.dp(8.0) - TOLERANCE_PX).intersects(own.get_global_rect()):
				lines.append(
					(
						"%s: the tab %s is under 8 dp from %s %s"
						% [label, tab, own.name, own.get_global_rect()]
					)
				)
	_read_parts()
	for part: StringName in _parts_now:
		var rect: Rect2 = _parts_now[part]
		var slot_second_look: bool = part == HudCorners.TOAST and not has_room
		if part == HudCorners.CARD or slot_second_look:
			continue
		if tab.intersection(rect).get_area() > OVERLAP_PX2:
			lines.append("%s: the tab %s covers the HUD part %s %s" % [label, tab, part, rect])
	if has_room:
		if not dock.grow(TOLERANCE_PX).encloses(tab):
			lines.append("%s: the tab %s is outside the dock %s" % [label, tab, dock])
	return lines


func _tab_press() -> void:
	(_mark.find_child("Tab", true, false) as Button).pressed.emit()


## The one see-through reason the sweep lets pass for a HUD control (P592): the hand's own bounds
## meet the card while the ring does not. A ring that meets the card is no exemption, whatever
## gesture the hand plays.
static func _hand_alone(ring: Rect2, hand: Rect2, card: Rect2) -> bool:
	return (
		hand.has_area()
		and hand.intersects(card)
		and not (ring.has_area() and ring.intersects(card))
	)


func test_a_ring_meeting_the_card_is_never_excused_by_the_hand() -> void:
	var card: Rect2 = Rect2(0.0, 0.0, 200.0, 100.0)
	var hand: Rect2 = Rect2(150.0, 80.0, 100.0, 100.0)  # A TAP hand reaching the card.
	assert_bool(_hand_alone(Rect2(300.0, 300.0, 50.0, 50.0), hand, card)).is_true()
	assert_bool(_hand_alone(Rect2(180.0, 90.0, 50.0, 50.0), hand, card)).is_false()
	assert_bool(_hand_alone(Rect2(), Rect2(), card)).is_false()
	(
		assert_bool(
			_hand_alone(Rect2(300.0, 300.0, 50.0, 50.0), Rect2(400.0, 400.0, 9.0, 9.0), card)
		)
		. is_false()
	)


## The see-through rules: the card is see-through only over a tile, a modal's button or a control
## that follows the world; where it covers the beat's control a pushed touch reaches it.
func _through(label: String, beat: TutorialBeatDef, card: Rect2, scope: Node) -> Array[String]:
	var lines: Array[String] = []
	var aim: TutorialLeadInDef = _aimed(beat)
	var allowed: bool = (
		aim.anchor == TutorialBeatDef.Anchor.TILE
		or scope != _layer
		or WORLD_CONTROLS.has(aim.anchor_control)
		or _hand_alone(_mark.ring_rect(), _mark.gesture_plan().bounds, card)
	)
	var safe: Rect2 = SafeAreaMargin.rect_inside(
		get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
	)
	var hand: Rect2 = _mark.gesture_plan().bounds
	if hand.has_area() and not safe.grow(0.5).encloses(hand):
		lines.append(
			"%s: the hand %s is outside the safe rect" % [label, _mark.gesture_plan().bounds]
		)
	if _mark.see_through() and not allowed:
		lines.append(
			(
				"%s: the card %s is see-through over a HUD control, ring %s target %s"
				% [label, card, _mark.ring_rect(), _mark.target_control()]
			)
		)
	var target: Control = _mark.target_control()
	if target == null:
		return lines
	var overlap: Rect2 = card.intersection(_on_screen(target))
	if overlap.get_area() <= OVERLAP_PX2:
		return lines
	if not _mark.see_through():
		lines.append("%s: the card covers %s but is not see-through" % [label, _path(target)])
	var body: Control = _mark.find_child("Card", true, false) as Control
	if body.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		lines.append("%s: the card's body takes the touch meant for %s" % [label, _path(target)])
		return lines
	_pushed = 0
	_pushes += 1
	target.gui_input.connect(_on_pushed)
	var at: Vector2 = overlap.get_center()
	TouchEvents.press(get_viewport(), 0, at)
	await await_idle_frame()
	TouchEvents.release(get_viewport(), 0, Vector2.ONE)  # Off the button: no press completes.
	target.gui_input.disconnect(_on_pushed)
	if _pushed == 0:
		lines.append("%s: a touch at %s did not reach %s" % [label, at, _path(target)])
	return lines


func _on_pushed(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		_pushed += 1


## The HUD's parts as `GuideDock.hud_for_dock` places them for what the real nodes show now, read
## from the nodes and not from the mark.
func _read_parts() -> void:
	var portrait: bool = HudLayout.is_portrait()
	var dp: float = UiScale.base_px_per_dp()
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	_feed.state.fill(shown)
	_feed.state.fill_bar(shown)
	var column: GroupColumn = _layer.find_children("*", "GroupColumn", true, false)[0]
	var build: BuildButton = _layer.find_children("*", "BuildButton", true, false)[0]
	var pill: EconomyPill = _layer.find_children("*", "EconomyPill", true, false)[0]
	var aim: StrikeAim = _director.strike_aim
	var dock_shown: HudCorners.Shown = GuideDock.shown_for_dock(
		portrait,
		shown.map,
		shown.drawer,
		column.item_count(),
		aim != null and aim.owned,
		build.ready_type >= 0,
		aim != null and aim.active,
		shown.bar,
		shown.bar_tall
	)
	dock_shown.bar_width = shown.bar_width
	dock_shown.pill_width = pill.size.x / dp
	_parts_now = GuideDock.hud_for_dock(_safe(), portrait, dp, false, dock_shown)


func _safe() -> Rect2:
	return SafeAreaMargin.rect_inside(
		get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
	)


## `button`'s rect as the player sees it: cut by the scroll areas it stands in and by the screen.
func _on_screen(button: Control) -> Rect2:
	var shown: Rect2 = button.get_global_rect()
	var up: Node = button.get_parent()
	while up != null:
		var area: ScrollContainer = up as ScrollContainer
		if area != null:
			shown = shown.intersection(area.get_global_rect())
		up = up.get_parent()
	return shown.intersection(get_viewport().get_visible_rect())


func _path(node: Node) -> String:
	return String(node.get_path()).trim_prefix(String(_layer.get_path()) + "/")


## A main scene of `lesson`'s scenario at `size`, paused, with a coach mark and a director on it.
func _open(lesson: TutorialLessonDef, profile: UiMetrics) -> void:
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	var runner: MatchRunner = _main.get_node("MatchRunner")
	runner.scenario = lesson.scenario
	runner.paused = true
	add_child(_main)
	await await_idle_frame()
	await await_idle_frame()
	_feed = _main.find_children("*", "HudStateFeed", true, false)[0] as HudStateFeed
	_sidebar = _main.find_children("*", "BuildSidebar", true, false)[0] as BuildSidebar
	_layer = _feed.get_parent()
	_selection = (
		(_main.find_children("*", "PlayerController", true, false)[0] as PlayerController).selection
	)
	_own = MatchRig.units_of(_main, lesson.scenario.local_player)
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
	_mark.hud_root = _layer
	_layer.add_child(_mark)
	await await_idle_frame()


func _close() -> void:
	_director.skip()
	_main.get_parent().remove_child(_main)
	_main.free()
	_main = null
	_mark = null
	_director = null
