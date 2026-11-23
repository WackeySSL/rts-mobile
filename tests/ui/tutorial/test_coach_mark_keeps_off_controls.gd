extends GdUnitTestSuite
## The sweep of the coach mark's card (plan row P543g): for every beat of every lesson file in
## `data/tutorial/` (read from the folder, so a lesson or a beat added later is covered at once), at
## the six sizes of ADR 0015 section 6, the real HUD in the state the beat expects, the card
## covers no visible, enabled HUD button of its own (the drawer's tabs, items and close button
## included) and not the tile a TILE beat points at.
## The state of a beat is what the beats before it leave (a drawer opened on a tab stays open until
## a beat closes it), plus the state its own condition asks for (DRAWER_TAB: the drawer on that
## tab; UNFOLD_OPEN and UNFOLD_CLOSED: that unfold open), plus, when the named control is not on
## screen in that state, the first state that shows it (a selection, a tab of the drawer, the
## radar, the card, the pause menu).

const Lesson: GDScript = preload("res://tests/ui/tutorial/support/lesson_rig.gd")
const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const LESSON_DIR: String = "res://data/tutorial/"
const MAIN_SCENE: String = "res://scenes/main.tscn"
const OVERLAP_PX2: float = 4.0  ## Less area than this is rounding, not a covered button.
const TILE_MARGIN_DP: float = 8.0
const TABS: int = 5
const TOLERANCE_PX: float = 0.5
## Real phones of ui_profiles.gd run besides the six sizes: where the screen has no free place the
## card may stand on a button (the least it can), but never on the beat's own control or tile.
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
var _fallbacks: Array[String] = []


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
	_fallbacks.clear()
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
						found.append_array(_covered(lesson, beat, profile, now, strict))
						var missing: bool = (
							beat.anchor == TutorialBeatDef.Anchor.CONTROL
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
	for line: String in _fallbacks:
		print("FALLBACK ", line)
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
	return found


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
	_director.start(Lesson.lesson(String(lesson.id), [shown]))
	_director.advance()
	for _frame: int in 3:
		await await_idle_frame()
	if not _mark.visible and not _director.running():
		# The state already met the condition (a saved group): the card is judged all the same.
		_mark.show_beat(shown)
		for _frame: int in 3:
			await await_idle_frame()


## What the card covers in the state on show: the visible, enabled HUD buttons that are not its own,
## and the anchored tile. One line each.
func _covered(
	lesson: TutorialLessonDef,
	beat: TutorialBeatDef,
	profile: UiMetrics,
	state: Dictionary,
	strict: bool
) -> Array[String]:
	var lines: Array[String] = []
	if not _mark.visible:
		return lines  # A menu covers the HUD and the mark stands down.
	var card: Rect2 = _mark.card_rect()
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
	var scope: Node = _layer
	for modal: Node in _layer.find_children("*", "ModalFrame", true, false):
		if (modal as Control).is_visible_in_tree():
			scope = modal  # A menu takes every touch: the buttons behind it cannot be tapped.
	for node: Node in scope.find_children("*", "BaseButton", true, false):
		var button: BaseButton = node as BaseButton
		if button.disabled or _mark.is_ancestor_of(button) or not button.is_visible_in_tree():
			continue
		var shown: Rect2 = _on_screen(button)
		if card.intersection(shown).get_area() > OVERLAP_PX2:
			var line: String = "%s covers %s %s" % [label, _path(button), shown]
			if strict or button == _mark.target_control():
				lines.append(line)  # The anchor is never covered, a fallback or not.
			else:
				_fallbacks.append(line)  # The least-overlap place of a screen with no free one.
	var panel: Rect2 = card.grow(TOLERANCE_PX)
	for part: StringName in [&"Skip", &"Next"]:  # The card's own buttons stand on its panel.
		var own: Button = _mark.find_child(String(part), true, false) as Button
		if own != null and own.is_visible_in_tree() and not panel.encloses(own.get_global_rect()):
			lines.append("%s: %s is outside the card %s" % [label, part, card])
	var least: float = _mark.find_child("Card", true, false).get_combined_minimum_size().y
	if card.size.y + TOLERANCE_PX < least:
		lines.append("%s: the card is %s high, its text needs %s" % [label, card.size.y, least])
	if beat.anchor == TutorialBeatDef.Anchor.TILE:
		var camera: RtsCamera = _main.get_node("Camera") as RtsCamera
		var world: Vector2 = IsoProjection.cell_centre_px(beat.anchor_tile.x, beat.anchor_tile.y)
		var point: Vector2 = camera.world_to_screen(world)
		if card.grow(UiScale.dp(TILE_MARGIN_DP)).has_point(point):
			lines.append("%s covers the tile %s at %s" % [label, beat.anchor_tile, point])
	return lines


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
