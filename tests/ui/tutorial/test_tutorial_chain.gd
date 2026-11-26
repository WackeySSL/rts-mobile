extends GdUnitTestSuite
## The chain of targets (plan row P586, ADR 0048 section 5): the furthest lead-in whose condition
## holds wins, both ways, and a beat with no lead-in has its anchor alone.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const Lesson: GDScript = preload("res://tests/ui/tutorial/support/lesson_rig.gd")

var _world: World
var _ctx: TutorialContext


func before_test() -> void:
	_world = Rig.start()
	_ctx = Lesson.context(_world)


## The `barracks` beat of the guide: BUILD, the Structures tab, the card (passed by PLACING), then
## the check mark as the beat's own anchor.
func _barracks() -> TutorialBeatDef:
	return (
		Lesson
		. beat(
			"barracks",
			TutorialConditions.Kind.BUILDING_PLACED,
			{
				"anchor": TutorialBeatDef.Anchor.CONTROL,
				"anchor_control": &"PlaceConfirm",
				"lead_in":
				[
					Lesson.lead_in(
						"BuildButton", TutorialConditions.Kind.UNFOLD_OPEN, HudState.Unfold.DRAWER
					),
					Lesson.lead_in(
						"TabStructures", TutorialConditions.Kind.DRAWER_TAB, World.Tab.STRUCTURES
					),
					Lesson.lead_in(
						"Tile_barracks", TutorialConditions.Kind.PLACING, 0, &"barracks"
					),
				],
			}
		)
	)


func test_a_beat_without_lead_ins_is_its_anchor_alone() -> void:
	var beat: TutorialBeatDef = Lesson.beat("a", TutorialConditions.Kind.NEXT)
	assert_int(TutorialChain.active(beat, _ctx)).is_equal(0)
	assert_object(TutorialChain.final_step(beat)).is_not_null()


func test_the_first_step_is_active_when_none_holds() -> void:
	assert_int(TutorialChain.active(_barracks(), _ctx)).is_equal(0)


func test_each_step_hands_over_to_the_next() -> void:
	var beat: TutorialBeatDef = _barracks()
	_ctx.hud.open(HudState.Unfold.DRAWER)
	_ctx.drawer_tab = World.Tab.INFANTRY
	assert_int(TutorialChain.active(beat, _ctx)).is_equal(1)  # The drawer is open, wrong tab.
	_ctx.drawer_tab = World.Tab.STRUCTURES
	assert_int(TutorialChain.active(beat, _ctx)).is_equal(2)
	_ctx.placement_type = Rig.type_of(_world, "barracks")
	assert_int(TutorialChain.active(beat, _ctx)).is_equal(3)  # The beat's own anchor.


func test_placement_closing_the_drawer_keeps_the_ring_on_the_final_step() -> void:
	var beat: TutorialBeatDef = _barracks()
	_ctx.hud.open(HudState.Unfold.DRAWER)
	_ctx.drawer_tab = World.Tab.STRUCTURES
	_ctx.placement_type = Rig.type_of(_world, "barracks")
	_ctx.hud.close(HudState.Unfold.DRAWER)  # Placement closed the drawer: the later step holds.
	assert_int(TutorialChain.active(beat, _ctx)).is_equal(3)


func test_closing_the_drawer_by_hand_sends_the_ring_back() -> void:
	var beat: TutorialBeatDef = _barracks()
	_ctx.hud.open(HudState.Unfold.DRAWER)
	_ctx.drawer_tab = World.Tab.STRUCTURES
	assert_int(TutorialChain.active(beat, _ctx)).is_equal(2)
	_ctx.hud.close(HudState.Unfold.DRAWER)
	assert_int(TutorialChain.active(beat, _ctx)).is_equal(0)


func test_a_later_step_wins_over_an_earlier_one_that_also_holds() -> void:
	var beat: TutorialBeatDef = (
		Lesson
		. beat(
			"aim",
			TutorialConditions.Kind.STRIKE_AIMED,
			{
				"lead_in":
				[
					Lesson.lead_in(
						"StrikeButton", TutorialConditions.Kind.UNFOLD_OPEN, HudState.Unfold.RADAR
					),
					Lesson.lead_in("StrikeButton", TutorialConditions.Kind.STRIKE_AIMING),
				],
			}
		)
	)
	assert_int(TutorialChain.active(beat, _ctx)).is_equal(0)
	_ctx.strike_aiming = true
	assert_int(TutorialChain.active(beat, _ctx)).is_equal(2)
	_ctx.strike_has_point = true  # The final condition itself is not read by the chain.
	assert_int(TutorialChain.active(beat, _ctx)).is_equal(2)


func test_the_final_step_copies_the_beats_anchor_and_gesture() -> void:
	var beat: TutorialBeatDef = _barracks()
	beat.gesture = TutorialBeatDef.Gesture.LONG_PRESS
	var step: TutorialLeadInDef = TutorialChain.final_step(beat)
	assert_str(String(step.anchor_control)).is_equal("PlaceConfirm")
	assert_int(step.anchor).is_equal(TutorialBeatDef.Anchor.CONTROL)
	assert_int(step.kind).is_equal(TutorialConditions.Kind.BUILDING_PLACED)
	assert_int(step.gesture).is_equal(TutorialBeatDef.Gesture.LONG_PRESS)


func test_the_final_step_carries_the_unit_selector() -> void:
	var beat: TutorialBeatDef = Lesson.beat("a", TutorialConditions.Kind.NEXT)
	beat.anchor = TutorialBeatDef.Anchor.UNIT
	beat.unit = TutorialUnitPickDef.new()
	beat.unit.pick = TutorialUnitPickDef.Pick.NEWEST
	var step: TutorialLeadInDef = TutorialChain.final_step(beat)
	assert_int(step.anchor).is_equal(TutorialBeatDef.Anchor.UNIT)
	assert_object(step.unit).is_same(beat.unit)
