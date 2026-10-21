extends GdUnitTestSuite
## PerfHud part 2 (plan P50a2, ADR 0011 section 5), the card: it is hidden while a run records (so
## it adds no draw call to a measured frame), shows at `run_ticks` with the verdict and the run on
## top and pauses the runner, and `restart()` hides it and resumes the runner. Its rows are the
## verdict lines, the rows without a verdict and GATE last, and every format of the table prints.
## The layout cases put it in a SafeAreaMargin, as the HUD roots are, at every UiProfiles entry and
## on Michael's phone (2424x1080 with the cutout Rect2i(152, 0, 2272, 1080), as test_army_bar and
## test_selection_panel build it): the whole card lies inside the safe area, its text is 14 sp or
## more, every button of it is at least dp(48), and a finger drag scrolls the text. The look is the
## `PerfCard` variation of game/ui/theme.tres. "Copy report" and "Run again" are P50a3's.

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")
const HudThemes: GDScript = preload("res://tests/support/hud_theme.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const MICHAEL: Dictionary = {"window": Vector2i(2424, 1080), "safe": Rect2i(152, 0, 2272, 1080)}

var _window_size_before: Vector2i


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_the_card_is_hidden_while_the_run_records_and_shows_at_run_ticks_with_the_runner_paused(
) -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var hud: PerfHud = auto_free(Rig.hud())
	hud.runner = runner
	hud.run_ticks = 150
	assert_bool(hud.visible).is_false()
	Rig.pass_frames(hud)
	Rig.ticks(hud, 149)
	assert_bool(hud.visible).is_false()
	assert_bool(runner.paused).is_false()
	hud.record_snapshot(Rig.snapshot(150))  # The tick that reaches run_ticks.
	assert_bool(hud.visible).is_true()
	assert_bool(runner.paused).is_true()
	var header: Label = hud.get_node("Column/Header")
	var body: Label = hud.get_node("Column/Scroll/Body")
	assert_str(header.text).starts_with("GATE: ")
	assert_str(header.text).contains("PERF run 1 | WORKER | release build | all")
	assert_str(body.text).contains("heavy_frames_min: PASS")
	assert_str(body.text).contains("held_ticks 0 (no verdict)")
	assert_bool(body.text.contains("GATE:")).is_false()  # The verdict is the header's.
	hud.restart()  # A new run: the card goes, the runner runs.
	assert_bool(hud.visible).is_false()
	assert_bool(runner.paused).is_false()


func test_the_header_carries_the_verdict_and_the_rows_that_failed() -> void:
	var cases: Array = [  # debug template, paused, the header's start
		[false, false, "GATE: PASS | PERF run 1"],
		[true, false, "GATE: FAIL (build) | PERF run 1"],
		[true, true, "GATE: FAIL (INVALID: app_paused, build) | PERF run 1"],
	]
	for c: Array in cases:
		var hud: PerfHud = auto_free(Rig.hud())
		hud.debug_build = c[0]  # A debug template fails the build verdict.
		Rig.pass_frames(hud)
		if c[1]:
			hud.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		Rig.ticks(hud, 900)
		var header: Label = hud.get_node("Column/Header")
		assert_str(header.text).override_failure_message(str(c)).starts_with(c[2])


func test_the_card_rows_are_the_verdicts_then_the_rows_without_a_verdict_and_gate() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.run(hud)
	var lines: PackedStringArray = hud.card_lines()
	var verdicts: int = hud.summary()["verdicts"].size()
	# The run line, the verdicts, held_ticks, the implementation line, the table, the phases and GATE.
	assert_int(lines.size()).is_equal(1 + verdicts + 1 + 1 + PerfHud.CARD_ROWS.size() + 1 + 1)
	assert_str(lines[0]).starts_with("PERF run 1 |")
	assert_str(lines[lines.size() - 1]).is_equal("GATE: PASS")
	for line: String in lines.slice(1 + verdicts, lines.size() - 1):
		assert_bool(line.contains(": PASS (") or line.contains(": FAIL (")).is_false()
	var text: String = "\n".join(lines)
	for part: String in [
		"refresh 60.00 to 60.00 Hz", "extra slots [", "ref peak 25.0 us", "latency max"
	]:
		assert_str(text).contains(part)
	assert_str(text).contains("job ms mean 10.00 p50 10.00 p95 10.00 p99 10.00 max 10.00")


func test_the_look_is_the_perf_card_variation_of_the_theme() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	var theme: Theme = HudThemes.source()
	assert_str(str(hud.theme_type_variation)).is_equal("PerfCard")
	assert_str(str(theme.get_type_variation_base("PerfCard"))).is_equal("PanelContainer")
	hud.theme = theme
	add_child(hud)  # A theme item resolves in the tree only.
	assert_object(hud.get_theme_stylebox("panel")).is_same(theme.get_stylebox("panel", "PerfCard"))
	assert_float((hud.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a).is_greater(0.5)
	var header: Label = hud.get_node("Column/Header")
	assert_str(str(header.theme_type_variation)).is_equal("NumberLabel")  # The HUD number size.


func test_the_whole_card_lies_inside_the_safe_area_at_every_profile() -> void:
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	for profile_name: StringName in profiles:
		await _check_layout(profiles[profile_name])
	for profile_name: StringName in profiles:  # And with a 100 px cutout on the left.
		var m: UiMetrics = profiles[profile_name]
		var cutout: Rect2i = Rect2i(100, 0, m.window_size.x - 100, m.window_size.y)
		await _check_layout(UiProfiles.with_safe_area(m, cutout))


func test_the_whole_card_lies_inside_the_safe_area_on_michaels_phone() -> void:
	var michael: UiMetrics = UiMetrics.create(
		"Android", 420, 1.0, 1.5, MICHAEL["window"], MICHAEL["safe"]
	)
	await _check_layout(michael)


## The text is a ScrollContainer's, so the engine scrolls it by a finger drag on a touch screen (not
## testable headless: `is_touchscreen_available()` is false) and by the wheel; this case proves the
## card puts nothing between the input and the scroll and that there is more text than it shows.
func test_the_wheel_scrolls_the_text_of_a_card_that_does_not_fit() -> void:
	var hud: PerfHud = await _open(UiProfiles.by_name(&"android_6in"))
	var scroll: ScrollContainer = hud.get_node("Column/Scroll")
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	assert_float(bar.max_value).is_greater(bar.page)  # More text than the card shows at once.
	assert_int(scroll.scroll_vertical).is_equal(0)
	TouchEvents.wheel(
		get_viewport(), MOUSE_BUTTON_WHEEL_DOWN, scroll.get_global_rect().get_center()
	)
	await await_idle_frame()
	assert_int(scroll.scroll_vertical).is_greater(0)


## `metrics` shown: the card in its SafeAreaMargin, laid out.
func _check_layout(metrics: UiMetrics) -> void:
	var hud: PerfHud = await _open(metrics)
	var safe: Rect2 = UiScale.safe_rect_base()
	var card: Rect2 = hud.get_global_rect()
	var label: String = "%s with %s" % [metrics.window_size, metrics.safe_area]
	(
		assert_bool(safe.encloses(card))
		. override_failure_message("%s: card %s in %s" % [label, card, safe])
		. is_true()
	)
	assert_float(card.size.x).override_failure_message(label).is_greater(0.7 * safe.size.x)
	assert_float(card.size.y).override_failure_message(label).is_greater(0.7 * safe.size.y)
	var column: Node = hud.get_node("Column")
	for child: Control in [column.get_node("Header"), column.get_node("Scroll")]:
		(
			assert_bool(card.encloses(child.get_global_rect()))
			. override_failure_message(label)
			. is_true()
		)
	var body: Label = column.get_node("Scroll/Body")
	var scroll: ScrollContainer = column.get_node("Scroll")
	assert_float(body.size.x).override_failure_message(label).is_less_equal(scroll.size.x + 0.5)
	var floor_px: int = roundi(UiScale.dp(14.0))  # 14 sp: the text of the HUD is dp.
	for text: Label in [column.get_node("Header"), body]:
		var size_px: int = text.get_theme_font_size("font_size")
		assert_int(size_px).override_failure_message(label).is_greater_equal(floor_px)
	var touch_px: float = UiScale.dp(48.0)
	for button: BaseButton in hud.find_children("*", "BaseButton", true, false):
		var rect: Vector2 = button.get_global_rect().size
		assert_bool(rect.x >= touch_px - 0.5 and rect.y >= touch_px - 0.5).is_true()
		assert_bool(card.encloses(button.get_global_rect())).is_true()


## A finished run on a card in a new SafeAreaMargin, at `metrics`, after two frames of layout.
func _open(metrics: UiMetrics) -> PerfHud:
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	var safe: SafeAreaMargin = auto_free(SafeAreaMargin.new())
	safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	var hud: PerfHud = auto_free(Rig.hud())
	hud.theme = HudThemes.scaled()  # Outside main.tscn nothing is inherited (P58).
	Rig.run(hud)  # The card shows when the run ends.
	safe.add_child(hud)
	add_child(safe)
	await await_idle_frame()
	await await_idle_frame()
	return hud
