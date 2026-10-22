extends GdUnitTestSuite
## The perf arena's card on the real viewport (plan P63b, ADR 0015, ADR 0011 section 5): the web
## preview cannot lock the screen, so an arena whose viewport is portrait at a recorded frame makes
## the run INVALID with `portrait`, and one whose viewport is landscape is valid, at each of the six
## test sizes (ADR 0015 section 6). The HUD's default `view_size_source` reads the viewport's
## visible rect here, so this proves the wiring that test_perf_hud_portrait.gd injects. A new run
## ("Run again", a layer-mode step) judges the viewport anew. What the arena does with the display
## server's orientation: test_perf_arena_orientation.gd. The rig's seams stand in for the slow
## preflight, as in the other arena suites.

const Rig: GDScript = preload("res://tests/ui/support/arena_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")

var _calls: Array[String] = []
var _window_size_before: Vector2i


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func after_test() -> void:
	_calls.clear()
	CommandQueue.clear()


func test_a_recorded_frame_at_a_portrait_size_is_invalid_and_at_a_landscape_size_is_not() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		var arena: Node2D = await _open(size)
		var hud: PerfHud = arena.hud
		var seen: Vector2i = Vector2i(arena.get_viewport().get_visible_rect().size)
		assert_that(hud.view_size_source.call()).is_equal(seen)  # The viewport, as it is.
		(
			assert_array(hud.summary()["invalid_reasons"])
			. override_failure_message(str(size))
			. is_empty()
		)
		_frame(hud)  # The first frame is judged, not the start of the run.
		var portrait: bool = ScreenSizes.PORTRAIT.has(size)
		var want: Array = [PerfHud.REASON_PORTRAIT] if portrait else []
		(
			assert_array(hud.summary()["invalid_reasons"])
			. override_failure_message("%s (seen %s)" % [size, seen])
			. is_equal(want)
		)
		assert_bool(hud.summary()["gate_pass"]).is_false()  # Not finished: no pass in any case.
		Rig.close(self, arena)


func test_a_new_run_in_portrait_is_judged_again_and_one_turned_to_landscape_is_clean() -> void:
	var arena: Node2D = await _open(ScreenSizes.PORTRAIT[1])
	var hud: PerfHud = arena.hud
	var again: Button = hud.get_node("Column/Buttons/RunAgain")
	_frame(hud)
	assert_array(hud.summary()["invalid_reasons"]).is_equal([PerfHud.REASON_PORTRAIT])
	again.pressed.emit()
	assert_array(hud.summary()["invalid_reasons"]).is_empty()  # The new run has recorded nothing.
	_frame(hud)
	assert_array(hud.summary()["invalid_reasons"]).is_equal([PerfHud.REASON_PORTRAIT])
	(arena.layers_button as Button).pressed.emit()  # A layer-mode step is a new run as well.
	assert_array(hud.summary()["invalid_reasons"]).is_empty()
	get_window().size = ScreenSizes.LANDSCAPE[1]  # The phone is turned before the next one records.
	await await_idle_frame()
	await await_idle_frame()
	again.pressed.emit()
	_frame(hud)
	assert_array(hud.summary()["invalid_reasons"]).is_empty()
	Rig.close(self, arena)


## The arena in the tree at window size `size`, after two frames of layout.
func _open(size: Vector2i) -> Node2D:
	get_window().size = size
	await await_idle_frame()
	var arena: Node2D = Rig.open(self, _calls)
	auto_free(arena)
	await await_idle_frame()
	await await_idle_frame()
	return arena


## One recorded frame of a run that would pass, so the HUD judges the view.
func _frame(hud: PerfHud) -> void:
	hud.record_frame(16667, 3000, 1000, 40, 140, false, 25, -1)
