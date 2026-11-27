extends GdUnitTestSuite
## The gestures of the lesson beats (ADR 0048 section 6, plan row P594): `gesture` and
## `gesture_vector_dp` in `data/tutorial/{basics,strikes,air,support}.tres`. A separate suite from
## `test_lesson_data.gd`, which is at gdlint's public-method cap:
## - every beat carries the gesture of the table, and no other beat has one;
## - a gesture fits its kind and its anchor;
## - the box surrounds the squads;
## - every beat that asks for a map action has a hint.

const LESSON_DIR: String = "res://data/tutorial/"
const LESSONS: Array[StringName] = [&"basics", &"strikes", &"air", &"support"]
const GESTURE = TutorialBeatDef.Gesture
## Lesson, beat, gesture, diagonal in dp. Every other beat stays `AUTO` with no vector.
const TABLE: Array[Array] = [
	[&"basics", &"pan", GESTURE.DRAG, Vector2i(-160, 0)],
	[&"basics", &"box", GESTURE.BOX, Vector2i(140, 100)],
	[&"basics", &"double", GESTURE.DOUBLE_TAP, Vector2i.ZERO],
	[&"basics", &"move", GESTURE.TAP, Vector2i.ZERO],
	[&"basics", &"across", GESTURE.TAP, Vector2i.ZERO],
	[&"basics", &"field", GESTURE.TAP, Vector2i.ZERO],
	[&"strikes", &"aim", GESTURE.TAP, Vector2i.ZERO],
	[&"air", &"select-squads", GESTURE.DOUBLE_TAP, Vector2i.ZERO],
	[&"support", &"select-plant", GESTURE.TAP, Vector2i.ZERO],
	[&"support", &"tanks", GESTURE.DOUBLE_TAP, Vector2i.ZERO],
]
const SELECTING: Array[TutorialConditions.Kind] = [
	TutorialConditions.Kind.SELECTED,
	TutorialConditions.Kind.UNITS_IN_AREA,
]


func test_every_beat_carries_the_gesture_of_the_table() -> void:
	var rows: Dictionary[String, Array] = {}
	for row: Array in TABLE:
		rows["%s/%s" % [row[0], row[1]]] = row
	var seen: int = 0
	for id: StringName in LESSONS:
		for beat: TutorialBeatDef in _lesson(id).beats:
			var label: String = "%s/%s" % [id, beat.id]
			var want: int = GESTURE.AUTO
			var vector: Vector2i = Vector2i.ZERO
			if rows.has(label):
				seen += 1
				want = rows[label][2]
				vector = rows[label][3]
			assert_int(beat.gesture).override_failure_message(label).is_equal(want)
			assert_object(beat.gesture_vector_dp).override_failure_message(label).is_equal(vector)
	assert_int(seen).is_equal(TABLE.size())


## PINCH only with `ZOOM_LEVEL`, DRAG with `CAMERA_PANNED` or a vector of its own, a vector only on
## a DRAG or BOX; BOX and DOUBLE_TAP only on a selecting beat on a tile; a tap never on a camera
## beat, a NEXT beat or a control.
func test_a_gesture_fits_its_kind_and_its_anchor() -> void:
	for id: StringName in LESSONS:
		for beat: TutorialBeatDef in _lesson(id).beats:
			var label: String = "%s/%s" % [id, beat.id]
			var vector: bool = beat.gesture_vector_dp != Vector2i.ZERO
			var moves: bool = beat.gesture == GESTURE.DRAG or beat.gesture == GESTURE.BOX
			assert_bool(vector and not moves).override_failure_message(label + " vector").is_false()
			var camera: bool = (
				beat.kind == TutorialConditions.Kind.CAMERA_PANNED
				or beat.kind == TutorialConditions.Kind.ZOOM_LEVEL
			)
			match beat.gesture:
				GESTURE.PINCH_OUT, GESTURE.PINCH_IN:
					assert_int(beat.kind).override_failure_message(label).is_equal(
						TutorialConditions.Kind.ZOOM_LEVEL
					)
				GESTURE.DRAG:
					var pans: bool = beat.kind == TutorialConditions.Kind.CAMERA_PANNED
					assert_bool(pans or vector).override_failure_message(label).is_true()
				GESTURE.BOX, GESTURE.DOUBLE_TAP:
					assert_bool(SELECTING.has(beat.kind)).override_failure_message(label).is_true()
					assert_int(beat.anchor).override_failure_message(label).is_equal(
						TutorialBeatDef.Anchor.TILE
					)
					assert_bool(beat.gesture != GESTURE.BOX or vector).is_true()
				GESTURE.TAP, GESTURE.LONG_PRESS:
					assert_bool(camera).override_failure_message(label + " on camera").is_false()
					(
						assert_int(beat.kind)
						. override_failure_message(label + " asks nothing")
						. is_not_equal(TutorialConditions.Kind.NEXT)
					)
					assert_int(beat.anchor).override_failure_message(label).is_not_equal(
						TutorialBeatDef.Anchor.CONTROL
					)


## The box starts left of and above the four squads (tiles 9 to 10.5 by 5 to 6.5, spawned at
## origin (9, 5), 2 columns, 1500 spacing) and its diagonal reaches past them lower right, in the
## screen px of `IsoProjection` (dp about equals base px at zoom 1).
func test_the_box_surrounds_the_squads() -> void:
	var box: TutorialBeatDef = null
	for beat: TutorialBeatDef in _lesson(&"basics").beats:
		if beat.id == &"box":
			box = beat
	assert_object(box).is_not_null()
	var from: Vector2 = IsoProjection.cell_centre_px(box.anchor_tile.x, box.anchor_tile.y)
	var end: Vector2 = from + Vector2(box.gesture_vector_dp)
	for at: Vector2 in [Vector2(9, 5), Vector2(10.5, 5), Vector2(9, 6.5), Vector2(10.5, 6.5)]:
		var px: Vector2 = Vector2(
			(at.x - at.y) * IsoProjection.HALF_W, (at.x + at.y + 1.0) * IsoProjection.HALF_H
		)
		assert_bool(px.x > from.x and px.y > from.y).override_failure_message(str(at)).is_true()
		assert_bool(px.x < end.x and px.y < end.y).override_failure_message(str(at)).is_true()


## Every beat that asks for something on the map (a condition other than NEXT, on a tile, a unit or
## with no anchor) has a hint: a named gesture, or `AUTO` where the guide resolves it from the kind
## (a pan, a zoom) or from the anchor (a tap on a unit, as on a control). A control beat is tapped
## by `AUTO`, so it needs none. There is no exception list.
func test_every_map_action_beat_has_a_hint() -> void:
	var checked: int = 0
	var unit_beats: int = 0
	for id: StringName in LESSONS:
		for beat: TutorialBeatDef in _lesson(id).beats:
			if beat.anchor == TutorialBeatDef.Anchor.CONTROL:
				continue
			if beat.kind == TutorialConditions.Kind.NEXT:
				continue
			var label: String = "%s/%s" % [id, beat.id]
			var from_kind: bool = (
				beat.kind == TutorialConditions.Kind.CAMERA_PANNED
				or beat.kind == TutorialConditions.Kind.ZOOM_LEVEL
			)
			var on_unit: bool = beat.anchor == TutorialBeatDef.Anchor.UNIT
			unit_beats += int(on_unit)
			var hinted: bool = (
				beat.gesture != GESTURE.NONE
				and (beat.gesture != GESTURE.AUTO or from_kind or on_unit)
			)
			checked += 1
			assert_bool(hinted).override_failure_message(label + " has no hint").is_true()
	assert_int(unit_beats).is_equal(3)  # attack, tap-air, select-truck.
	assert_int(checked).is_equal(TABLE.size() + 1 + unit_beats)  # The table, the zoom, the units.


func _lesson(id: StringName) -> TutorialLessonDef:
	return load("%s%s.tres" % [LESSON_DIR, id]) as TutorialLessonDef
