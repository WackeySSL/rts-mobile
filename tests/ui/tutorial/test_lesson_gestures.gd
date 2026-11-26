extends GdUnitTestSuite
## The gestures of the lesson beats (ADR 0048 section 6, plan row P594): `gesture` and
## `gesture_vector_dp` in `data/tutorial/{basics,strikes,air,support}.tres`. A separate suite from
## `test_lesson_data.gd`, which is at gdlint's public-method cap:
## - a gesture fits its kind and its anchor;
## - the beats the ADR names carry the gestures it names;
## - every beat that asks for a map action has a hint.

const LESSON_DIR: String = "res://data/tutorial/"
const LESSONS: Array[StringName] = [&"basics", &"strikes", &"air", &"support"]
const GESTURE = TutorialBeatDef.Gesture


## PINCH only with `ZOOM_LEVEL`, DRAG with `CAMERA_PANNED` or a vector of its own, BOX with a
## vector and a tile, a vector only on a DRAG or BOX, and a tap, double tap or long press only on a
## beat that asks for an action and is not on a control (a control is tapped by `AUTO`).
func test_a_gesture_fits_its_kind_and_its_anchor() -> void:
	var named: int = 0
	for id: StringName in LESSONS:
		for beat: TutorialBeatDef in _lesson(id).beats:
			var label: String = "%s/%s" % [id, beat.id]
			var vector: bool = beat.gesture_vector_dp != Vector2i.ZERO
			var moves: bool = beat.gesture == GESTURE.DRAG or beat.gesture == GESTURE.BOX
			(
				assert_bool(GESTURE.values().has(beat.gesture))
				. override_failure_message(label)
				. is_true()
			)
			assert_bool(vector and not moves).override_failure_message(label + " vector").is_false()
			if beat.gesture != GESTURE.AUTO:
				named += 1
			match beat.gesture:
				GESTURE.PINCH_OUT, GESTURE.PINCH_IN:
					assert_int(beat.kind).override_failure_message(label).is_equal(
						TutorialConditions.Kind.ZOOM_LEVEL
					)
				GESTURE.DRAG:
					var pans: bool = beat.kind == TutorialConditions.Kind.CAMERA_PANNED
					assert_bool(pans or vector).override_failure_message(label).is_true()
				GESTURE.BOX:
					assert_bool(vector).override_failure_message(label + " box vector").is_true()
					assert_int(beat.anchor).override_failure_message(label).is_equal(
						TutorialBeatDef.Anchor.TILE
					)
				GESTURE.TAP, GESTURE.DOUBLE_TAP, GESTURE.LONG_PRESS:
					(
						assert_int(beat.kind)
						. override_failure_message(label + " asks nothing")
						. is_not_equal(TutorialConditions.Kind.NEXT)
					)
					assert_int(beat.anchor).override_failure_message(label).is_not_equal(
						TutorialBeatDef.Anchor.CONTROL
					)
	assert_int(named).is_greater(10)


## The beats ADR 0048 section 6 names: pan, zoom, box, double, move and across.
func test_the_named_beats_carry_the_gestures_of_the_adr() -> void:
	var beats: Dictionary[StringName, TutorialBeatDef] = {}
	for beat: TutorialBeatDef in _lesson(&"basics").beats:
		beats[beat.id] = beat
	assert_int(beats[&"pan"].gesture).is_equal(GESTURE.DRAG)
	assert_int(beats[&"zoom"].gesture).is_equal(GESTURE.AUTO)
	assert_int(beats[&"box"].gesture).is_equal(GESTURE.BOX)
	assert_int(beats[&"double"].gesture).is_equal(GESTURE.DOUBLE_TAP)
	assert_int(beats[&"move"].gesture).is_equal(GESTURE.TAP)
	assert_int(beats[&"across"].gesture).is_equal(GESTURE.TAP)


## Every beat that asks for something on the map (a condition other than NEXT, on a tile or with no
## anchor) has a hint: a named gesture, or `AUTO` where the guide resolves it from the kind (a pan,
## a zoom). A control beat is tapped by `AUTO`, so it needs none.
func test_every_map_action_beat_has_a_hint() -> void:
	var checked: int = 0
	for id: StringName in LESSONS:
		for beat: TutorialBeatDef in _lesson(id).beats:
			if beat.anchor == TutorialBeatDef.Anchor.CONTROL:
				continue
			if beat.kind == TutorialConditions.Kind.NEXT:
				continue
			checked += 1
			var from_kind: bool = (
				beat.kind == TutorialConditions.Kind.CAMERA_PANNED
				or beat.kind == TutorialConditions.Kind.ZOOM_LEVEL
			)
			var hinted: bool = (
				beat.gesture != GESTURE.NONE and (beat.gesture != GESTURE.AUTO or from_kind)
			)
			(
				assert_bool(hinted)
				. override_failure_message("%s/%s has no hint" % [id, beat.id])
				. is_true()
			)
	assert_int(checked).is_greater(10)


func _lesson(id: StringName) -> TutorialLessonDef:
	return load("%s%s.tres" % [LESSON_DIR, id]) as TutorialLessonDef
