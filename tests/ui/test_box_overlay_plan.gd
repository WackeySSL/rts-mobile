extends GdUnitTestSuite
## What BoxOverlay paints (plan row P58, fix round 1): `_draw` only plays `draw_plan()`, so this is
## the whole picture, as pixels cannot be read headless: which shape, in which theme colour, how
## wide, in which order. The numbers are those of the code of main at 32bfb89 (STROKE_DP 3,
## OUTLINE_DP 2, BOX_DP 2, the anchor ring 48 dp at once and 32 dp at rest), at 1.75 px per dp.

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const PX_PER_DP: float = 1.75
const STROKE_PX: float = 3.0 * PX_PER_DP
const EDGE_PX: float = 2.0 * PX_PER_DP
const BOX_PX: float = 2.0 * PX_PER_DP
const ANCHOR: Vector2 = Vector2(300.0, 200.0)
const BOX: Rect2 = Rect2(100.0, 50.0, 300.0, 200.0)

var _now_ms: int = 0


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))
	_now_ms = 0


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()


func test_nothing_is_painted_until_the_anchor_or_the_box_shows() -> void:
	var overlay: BoxOverlay = _overlay()
	assert_array(overlay.draw_plan()).is_empty()
	overlay.show_anchor(ANCHOR)
	overlay.hide_all()
	assert_array(overlay.draw_plan()).is_empty()
	overlay.show_rect(Rect2(10.0, 20.0, 0.0, 50.0))  # No area: no box.
	assert_array(overlay.draw_plan()).is_empty()


func test_the_anchor_is_a_fill_then_a_dark_pass_then_a_stroke_on_one_circle() -> void:
	var overlay: BoxOverlay = _overlay()
	overlay.show_anchor(ANCHOR)
	_now_ms = 1000  # Long after the ring has shrunk: it is at rest.
	assert_array(_kinds(overlay)).is_equal(["circle fill", "circle outline", "circle stroke"])
	assert_array(_widths(overlay)).is_equal([-1.0, STROKE_PX + EDGE_PX, STROKE_PX])
	for step: BoxOverlay.Step in overlay.draw_plan():
		assert_that(step.center).is_equal(ANCHOR)
		assert_float(step.radius).is_equal_approx(32.0 * PX_PER_DP, 0.0001)


func test_the_anchor_ring_shrinks_from_48_dp_to_32_dp_as_it_appears() -> void:
	var overlay: BoxOverlay = _overlay()
	overlay.show_anchor(Vector2.ZERO)
	assert_float(overlay.draw_plan()[0].radius).is_equal_approx(48.0 * PX_PER_DP, 0.0001)
	_now_ms = 150
	assert_float(overlay.draw_plan()[0].radius).is_equal_approx(32.0 * PX_PER_DP, 0.0001)


func test_the_box_is_a_fill_of_the_rect_then_a_dark_pass_and_a_stroke_on_its_inner_line() -> void:
	var overlay: BoxOverlay = _overlay()
	overlay.show_rect(BOX)
	assert_array(_kinds(overlay)).is_equal(["rect fill", "rect outline", "rect stroke"])
	assert_array(_widths(overlay)).is_equal([-1.0, BOX_PX + EDGE_PX, BOX_PX])
	var plan: Array[BoxOverlay.Step] = overlay.draw_plan()
	var line: Rect2 = BOX.grow(-PX_PER_DP)  # The centre line of the stroke is 1 dp inside.
	assert_that(plan[0].area).is_equal(BOX)
	assert_that(plan[1].area).is_equal(line)
	assert_that(plan[2].area).is_equal(line)


func test_the_anchor_is_painted_before_the_box() -> void:
	var overlay: BoxOverlay = _overlay()
	overlay.show_rect(BOX)  # Shown first, painted last.
	overlay.show_anchor(ANCHOR)
	(
		assert_array(_kinds(overlay))
		. is_equal(
			[
				"circle fill",
				"circle outline",
				"circle stroke",
				"rect fill",
				"rect outline",
				"rect stroke",
			]
		)
	)


## Every step names a colour that the theme type has, and the three are all in use.
func test_each_step_names_a_theme_colour_and_the_three_colours_are_used() -> void:
	var overlay: BoxOverlay = _overlay()
	overlay.show_anchor(ANCHOR)
	overlay.show_rect(BOX)
	var colors: Dictionary[StringName, Color] = overlay.draw_colors()
	var used: Array[StringName] = []
	for step: BoxOverlay.Step in overlay.draw_plan():
		assert_bool(colors.has(step.item)).override_failure_message(str(step.item)).is_true()
		if not used.has(step.item):
			used.append(step.item)
	assert_array(used).contains_exactly_in_any_order(colors.keys())


## -1.0 is a fill and any other width a stroke: the one rule `_draw` has for the two.
func test_only_the_fills_have_the_width_of_a_fill() -> void:
	var overlay: BoxOverlay = _overlay()
	overlay.show_anchor(ANCHOR)
	overlay.show_rect(BOX)
	for step: BoxOverlay.Step in overlay.draw_plan():
		var filled: bool = step.width < 0.0
		assert_bool(filled).override_failure_message(str(step.item)).is_equal(step.item == &"fill")


func _overlay() -> BoxOverlay:
	var overlay: BoxOverlay = auto_free(BoxOverlay.new())
	overlay.visible = false  # As main.tscn has it: opening it reads the dp factor.
	overlay.clock = func() -> int: return _now_ms
	return overlay


## The plan as "shape item" lines, and as the widths in px.
func _kinds(overlay: BoxOverlay) -> Array[String]:
	var kinds: Array[String] = []
	for step: BoxOverlay.Step in overlay.draw_plan():
		kinds.append("%s %s" % [step.shape, step.item])
	return kinds


func _widths(overlay: BoxOverlay) -> Array[float]:
	var widths: Array[float] = []
	for step: BoxOverlay.Step in overlay.draw_plan():
		widths.append(step.width)
	return widths
