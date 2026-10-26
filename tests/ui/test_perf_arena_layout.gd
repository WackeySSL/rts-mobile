extends GdUnitTestSuite
## The perf arena's screen (plan P50b, ADR 0011 section 5, touch-ui-rules) at 1280x720, 2400x1080
## (20:9) and 2048x1536 (4:3), their portrait turns (720x1280, 1080x2400 and 1536x2048) and a phone
## browser held upright (plan P63, ADR 0015 section 5), and on Michael's phone with its cutout: the
## Back button and the layer-mode button are at least dp(48) with 14 sp text and lie inside the
## safe area, the card fills what is left under them and covers neither, the HUD takes its look
## from the theme (a HudTheme first under the CanvasLayer, the theme file on the margin), the
## camera starts at the lowest zoom on the centre of the fight, and the two sampling seams the card
## reads (rows drawn and the fog update) report what the view shows. What the scene does is
## test_perf_arena.gd's.

const Rig: GDScript = preload("res://tests/ui/support/arena_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const MICHAEL: Dictionary = {"window": Vector2i(2424, 1080), "safe": Rect2i(152, 0, 2272, 1080)}
const PROFILES: Array[StringName] = [&"desktop", &"android_6in", &"web_tablet"]
const MIN_DP: float = 48.0
## The centre of tile (32, 32) in world px under the 2:1 projection (P117).
const CENTRE: Vector2 = Vector2(0, 1040)
const RUN_TICKS: int = 15
## The sink of the fog clock: every update takes this many us.
const FOG_US: int = 1234

var _window_size_before: Vector2i
var _calls: Array[String] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()
	_calls.clear()
	CommandQueue.clear()


func test_the_buttons_are_big_and_inside_the_safe_area_and_the_card_fills_the_rest() -> void:
	for metrics: UiMetrics in _every_profile():
		await _check_layout(metrics)
	var michael: UiMetrics = UiMetrics.create(
		"Android", 420, 1.0, 1.5, MICHAEL["window"], MICHAEL["safe"]
	)
	await _check_layout(michael)


func test_the_look_is_the_theme_with_the_dp_step_first_under_the_hud() -> void:
	var arena: Node2D = await _open(UiProfiles.by_name(&"android_6in"))
	var hud_layer: CanvasLayer = arena.get_node("Hud")
	assert_object(hud_layer.get_child(0)).is_instanceof(HudTheme)  # Before the roots it scales.
	var safe: SafeAreaMargin = hud_layer.get_node("SafeArea")
	assert_object(safe.theme).is_not_null()
	var source: Theme = safe.theme.get_meta(HudTheme.SOURCE_META)
	assert_str(source.resource_path).is_equal("res://game/ui/theme.tres")
	assert_int(safe.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)  # A finger on the map pans.
	assert_int(arena.layout.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(arena.bar.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	var gap: int = roundi(UiScale.dp(8.0))
	assert_int(arena.layout.get_theme_constant("separation")).is_equal(gap)
	assert_int(arena.bar.get_theme_constant("separation")).is_equal(gap)


func test_the_camera_starts_at_the_lowest_zoom_on_the_fight_at_every_size() -> void:
	for metrics: UiMetrics in _every_profile():
		var profile_name: String = str(metrics.window_size)
		var arena: Node2D = await _open(metrics)
		var camera: RtsCamera = arena.camera
		assert_vector(camera.zoom).is_equal(Vector2(0.75, 0.75))
		assert_vector(camera.position).is_equal(CENTRE)
		assert_int(camera.zoom_level_index()).is_equal(0)
		var runner: MatchRunner = arena.runner
		var view: Rect2 = camera.visible_world_rect()
		var snap: MatchSnapshot = runner.snapshot
		var inside: int = 0
		for row: int in snap.unit_count():
			var at: Vector2 = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])
			inside += int(view.has_point(at))
		var heavy: int = arena.hud.gate.heavy_rigs
		var label: String = "%s: %d of 150 rows in %s" % [profile_name, inside, view]
		# The heavy window needs `heavy_rigs` rows in view: the arena frames the fight for a
		# landscape view (ADR 0011 section 5). A portrait view is 0.45 as wide at the same zoom and
		# shows 69 to 112 rows, so a gate run in portrait cannot reach the heavy window: the gate
		# is a landscape measurement until ADR 0011 says otherwise (plan P63, requests).
		if not UiScale.is_portrait_size(metrics.window_size):
			assert_int(inside).override_failure_message(label).is_greater_equal(heavy)
		assert_int(inside).override_failure_message(label).is_greater(0)
		assert_int(arena.drawn_rigs()).override_failure_message(label).is_equal(inside)
		assert_object(arena.hud.rigs_source).is_not_null()
		assert_int(int(arena.hud.rigs_source.call())).is_equal(inside)
		Rig.close(self, arena)
		UiScale.clear_override()


func test_a_hidden_rig_or_one_outside_the_view_is_not_a_drawn_rig() -> void:
	var arena: Node2D = await _open(UiProfiles.by_name(&"desktop"))
	var rig: Node2D = (arena.unit_layer as UnitLayer).get_child(0)
	rig.position = arena.camera.position  # Inside the view.
	var counted: int = arena.drawn_rigs()
	rig.visible = false
	assert_int(arena.drawn_rigs()).is_equal(counted - 1)
	rig.visible = true
	assert_int(arena.drawn_rigs()).is_equal(counted)
	rig.position = Vector2(-5000, -5000)
	assert_int(arena.drawn_rigs()).is_equal(counted - 1)


func test_the_fog_update_is_read_once_per_upload_and_kept_between_updates() -> void:
	var arena: Node2D = await _open(UiProfiles.by_name(&"desktop"))
	var fog: FogLayer = arena.fog_layer
	var now: Array[int] = [0]
	fog.usec_clock = func() -> int:
		now[0] += FOG_US  # One reading at the start of an update and one at the end.
		return now[0]
	assert_int(arena.fog_update_usec()).is_not_equal(-1)  # The match start's upload, once.
	assert_int(arena.fog_update_usec()).is_equal(-1)  # Kept by the layer, not taken again.
	assert_int(arena.fog_update_usec()).is_equal(-1)
	var uploads: int = fog.upload_count()
	arena.runner.run_ticks(RUN_TICKS)
	assert_int(fog.upload_count()).override_failure_message("no fog upload in 15 ticks").is_greater(
		uploads
	)
	assert_int(arena.fog_update_usec()).is_equal(FOG_US)  # The last update, once for the frame.
	assert_int(arena.fog_update_usec()).is_equal(-1)
	assert_object(arena.hud.fog_source).is_not_null()


## The landscape profiles of PROFILES, then the portrait ones.
func _every_profile() -> Array[UiMetrics]:
	var every: Array[UiMetrics] = []
	for profile_name: StringName in PROFILES:
		every.append(UiProfiles.by_name(profile_name))
	every.append_array(UiProfiles.portrait().values())
	return every


## The arena at `metrics` in the tree, a run of RUN_TICKS ticks, after two frames of layout.
func _open(metrics: UiMetrics) -> Node2D:
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	var arena: Node2D = Rig.open(self, _calls, RUN_TICKS)
	auto_free(arena)
	await await_idle_frame()
	await await_idle_frame()
	return arena


## `metrics` shown: the bar, then the card of a finished run under it.
func _check_layout(metrics: UiMetrics) -> void:
	var arena: Node2D = await _open(metrics)
	var safe: Rect2 = UiScale.safe_rect_base()
	var label: String = "%s with %s" % [metrics.window_size, metrics.safe_area]
	var touch_px: float = UiScale.dp(MIN_DP)
	var floor_px: int = roundi(UiScale.dp(14.0))  # 14 sp: the text of the HUD is dp.
	var buttons: Array[Button] = [arena.back_button, arena.layers_button]
	assert_str(buttons[0].text).is_equal("Back")
	assert_str(buttons[1].text).is_equal("Layers: all")
	for button: Button in buttons:
		var rect: Rect2 = button.get_global_rect()
		(
			assert_bool(rect.size.x >= touch_px - 0.5 and rect.size.y >= touch_px - 0.5)
			. override_failure_message("%s: %s is %s" % [label, button.name, rect.size])
			. is_true()
		)
		(
			assert_bool(safe.encloses(rect))
			. override_failure_message("%s: %s %s in %s" % [label, button.name, rect, safe])
			. is_true()
		)
		assert_int(button.get_theme_font_size("font_size")).is_greater_equal(floor_px)
	assert_bool(buttons[0].get_global_rect().intersects(buttons[1].get_global_rect())).is_false()
	var hud: PerfHud = arena.hud
	assert_bool(hud.visible).is_false()  # Nothing over the map while the run records.
	arena.runner.run_ticks(RUN_TICKS)  # The tick that reaches run_ticks shows the card.
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(hud.visible).is_true()
	var card: Rect2 = hud.get_global_rect()
	(
		assert_bool(safe.encloses(card))
		. override_failure_message("%s: card %s in %s" % [label, card, safe])
		. is_true()
	)
	assert_float(card.size.x).override_failure_message(label).is_greater(0.9 * safe.size.x)
	for button: Button in buttons:
		(
			assert_bool(card.intersects(button.get_global_rect()))
			. override_failure_message("%s: the card covers %s" % [label, button.name])
			. is_false()
		)
	assert_float(card.size.y).override_failure_message(label).is_greater(0.5 * safe.size.y)
	# The buttons stay pressable with the card up: a mode change hides it with the new run.
	(buttons[1] as Button).pressed.emit()
	assert_bool(hud.visible).is_false()
	Rig.close(self, arena)
	UiScale.clear_override()
