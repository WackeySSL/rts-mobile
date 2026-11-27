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

const ChainRig: GDScript = preload("res://tests/ui/tutorial/support/chain_rig.gd")
const MidPlay: GDScript = preload("res://tests/ui/tutorial/support/midplay_fixture.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const LESSON_DIR: String = "res://data/tutorial/"
const GROUPS: int = 3
## The beats with a UNIT step (a beat's own or a lead-in), each touch-proved at every size.
const UNIT_BEATS: Array[String] = [
	"basics/attack", "air/tap-air", "air/home", "support/select-truck", "support/mine"
]
const NONE: int = ChainRig.NONE

var _window_size_before: Vector2i
var _dir: String = ""
var _rig: RefCounted  ## The chain rig (support/chain_rig.gd): the main scene, director and mark.


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_rig = ChainRig.new(self)
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
	var profiles: Array[UiMetrics] = _rig.profiles()
	var found: Array[String] = []
	var judged: int = 0
	var chained: int = 0
	_rig.proofs.clear()
	_rig.button_hits.clear()
	for lesson: TutorialLessonDef in _rig.lessons():
		for profile: UiMetrics in profiles:
			await _rig.open(lesson, profile)
			var carried: Dictionary = {"unfold": HudState.Unfold.NONE, "tab": 0, "select": NONE}
			for beat: TutorialBeatDef in lesson.beats:
				if beat.anchor != TutorialBeatDef.Anchor.NONE:
					var pair: String = "%s/%s" % [lesson.id, beat.id]
					var result: Array
					if MidPlay.has(pair):
						result = await _rig.judge_midplay(lesson, beat, profile, pair)
						_rig.close()
						await _rig.open(lesson, profile)  # Back to the plain match for the beats after it.
					else:
						result = await _rig.judge(lesson, beat, profile, carried)
					var problems: Array[String] = result[1] as Array[String]
					judged += 1
					chained += int(result[0])
					found.append_array(problems)
				carried = _rig.after(beat, carried)
			_rig.close()
	assert_int(judged).is_greater(100)
	assert_int(chained).override_failure_message("no chained beat was driven").is_greater(8)
	var missing: Array[String] = []
	for profile: UiMetrics in profiles:
		for beat_pair: String in UNIT_BEATS:
			var key: String = "%s %dx%d" % [beat_pair, profile.window_size.x, profile.window_size.y]
			if not _rig.proofs.has(key):
				missing.append(key)
	assert_array(missing).override_failure_message("no touch proof: %s" % [missing]).is_empty()
	(
		assert_array(_rig.button_hits)
		. override_failure_message("no unit met a card button")
		. is_not_empty()
	)
	(
		assert_array(_rig.button_hits)
		. override_failure_message("support/mine at 2400x912 no longer meets Next")
		. contains(["support/mine 2400x912"])
	)
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
		await _rig.open(lesson, _rig.profile_of(size))
		var open: Dictionary = {
			"unfold": HudState.Unfold.DRAWER, "tab": World.Tab.INFANTRY, "select": NONE
		}
		await _rig.enter(open)
		await _rig.show(lesson, train)
		assert_str(String(_rig.director.active_target().anchor_control)).is_equal(card)
		assert_str(String(_rig.mark.target_control().name)).is_equal(card)
		assert_array(_rig.ring_problems("open tab", _rig.director.active_target())).is_empty()
		var shut: Dictionary = {
			"unfold": HudState.Unfold.NONE, "tab": World.Tab.STRUCTURES, "select": NONE
		}
		await _rig.enter(shut)
		await _rig.show(lesson, train)
		assert_str(String(_rig.director.active_target().anchor_control)).is_equal("BuildButton")
		assert_bool(await _rig.satisfy(_rig.director.active_target())).is_true()
		assert_str(String(_rig.director.active_target().anchor_control)).is_equal("TabInfantry")
		assert_bool(await _rig.satisfy(_rig.director.active_target())).is_true()
		assert_str(String(_rig.director.active_target().anchor_control)).is_equal(card)
		(
			assert_array(_rig.ring_problems("shut then opened", _rig.director.active_target()))
			. is_empty()
		)
		_rig.close()


## A beat that asks the player to build or train something ends on the item's card, never on the tab
## that holds it: the frame has to follow the player to the thing they must tap.
func test_a_beat_that_asks_for_units_ends_on_their_card_not_on_a_tab() -> void:
	for lesson: TutorialLessonDef in _rig.lessons():
		for beat: TutorialBeatDef in lesson.beats:
			if beat.kind == TutorialConditions.Kind.OWN_AT_LEAST and beat.anchor_control != &"":
				var ends: String = "%s/%s ends on %s" % [lesson.id, beat.id, beat.anchor_control]
				(
					assert_bool(String(beat.anchor_control).begins_with("Tab"))
					. override_failure_message(ends)
					. is_false()
				)


## Every selection lead-in is driven both ways: with nothing selected the ring stands on the
## lead-in's own anchor (the AllArmy control, or the tile where the type stands), and once exactly
## the lead-in's type is selected it moves on to the beat's target. The mid-play beats get their
## fixture first and the selection is cleared after it. A typo in an anchor tile or a type id fails.
func test_a_selection_lead_in_points_at_its_anchor_and_then_moves_on() -> void:
	var profiles: Array[UiMetrics] = _rig.profiles()
	var found: Array[String] = []
	var driven: int = 0
	for lesson: TutorialLessonDef in _rig.lessons():
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
				await _rig.open(lesson, profile, scenario)
				if MidPlay.has(pair):
					_rig.feed.state.close(_rig.feed.state.current)
					var fixture: Object = MidPlay.new(self, _rig.main, _rig.selection, _rig.sidebar)
					await fixture.prepare(pair)
					if not String(fixture.failure).is_empty():
						found.append("%s: fixture: %s" % [label, fixture.failure])
						_rig.close()
						continue
				_rig.feed.state.close(_rig.feed.state.current)
				_rig.selection.clear()
				await _rig.show(lesson, beat)
				found.append_array(await _drive_selection(beat, lead, label))
				driven += 1
				_rig.close()
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
	if _rig.director.active_target() != lead:
		lines.append("%s: with nothing selected the ring is not on the selection step" % label)
		return lines
	lines.append_array(_rig.ring_problems(label + " selection step", lead))
	var ids: PackedInt32Array = _rig.own_of(lead.type_id)
	if ids.is_empty():
		lines.append("%s: no own %s to select" % [label, lead.type_id])
		return lines
	if lead.anchor == TutorialBeatDef.Anchor.TILE:  # The ring is on a unit of the type, as drawn.
		var runner: MatchRunner = _rig.main.get_node("MatchRunner") as MatchRunner
		var row: int = runner.snapshot.index_of(ids[0])
		var at: Vector2 = _rig.mark.camera.world_to_screen(
			IsoProjection.ground_to_px(runner.snapshot.pos_x[row], runner.snapshot.pos_y[row])
		)
		var ring: Rect2 = _rig.mark.ring_rect()
		if not ring.grow(ring.size.y / 4.0).has_point(at):  # A unit stands off its tile centre.
			lines.append("%s: the ring %s is not on the %s at %s" % [label, ring, lead.type_id, at])
	if not await _rig.satisfy(lead):
		lines.append("%s: the selection step could not be satisfied" % label)
		return lines
	var next: TutorialLeadInDef = _rig.director.active_target()
	if next == null or beat.lead_in.has(next) and next == lead:
		lines.append(
			"%s: the ring stayed on the selection step after its type was selected" % label
		)
		return lines
	lines.append_array(_rig.ring_problems(label + " after the selection", next))
	return lines
