# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## The coach mark (plan row P542, ADR 0044 section 2): the ring finds the named control, a world
## tile projects through the camera, the card stays in the safe rect and off the ring at the six
## sizes and through turns, a touch goes through to the target, Next and Skip call the director,
## the stalled hint, and no Tween with reduced effects.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const Lesson: GDScript = preload("res://tests/ui/tutorial/support/lesson_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const NEXT: TutorialConditions.Kind = TutorialConditions.Kind.NEXT
const TOLERANCE_PX: float = 0.5

var _world: World
var _loop: MatchLoop
var _runner: MatchRunner
var _director: TutorialDirector
var _mark: CoachMark
var _hud_root: Control
var _target: Control
var _camera: RtsCamera
var _taps: int = 0
var _map_taps: int = 0
var _offset: Control
var _dir: String = ""
var _window_size_before: Vector2i


func before() -> void:
	assert_bool(UiScale.has_override()).override_failure_message("override leaked").is_false()
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_dir = "user://test_coach_mark_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	SaveService.set_path_override(_dir.path_join("save.cfg"))
	_world = Rig.start()
	_loop = Rig.loop_of(_world)
	_runner = auto_free(MatchRunner.new())
	_runner.snapshot = Lesson.snapshot(_world)
	_director = auto_free(TutorialDirector.new())
	_director.runner = _runner
	_director.hud = HudState.new()
	_director.selection = SelectionModel.new()
	_taps = 0


func after_test() -> void:
	UiScale.clear_override()
	_free_nodes()
	_mark = null
	_hud_root = null
	_camera = null
	SaveService.clear_path_override()
	for file_name: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file_name))
	DirAccess.remove_absolute(_dir)


func test_the_ring_finds_the_named_control() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	assert_object(_mark.target_control()).is_same(_target)
	var ring: Rect2 = _mark.ring_rect()
	assert_bool(ring.encloses(_target.get_global_rect())).is_true()
	assert_bool(_mark.visible).is_true()


func test_a_missing_control_gives_a_card_alone() -> void:
	var beat: TutorialBeatDef = _control_beat("hit", NEXT)
	beat.anchor_control = &"NoSuchControl"
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beat)
	assert_object(_mark.target_control()).is_null()
	assert_bool(_mark.ring_rect().has_area()).is_false()
	assert_bool(_safe().grow(TOLERANCE_PX).encloses(_mark.card_rect())).is_true()


func test_a_world_tile_projects_through_the_camera() -> void:
	var beat: TutorialBeatDef = Lesson.beat(
		"tile", NEXT, {"anchor": TutorialBeatDef.Anchor.TILE, "anchor_tile": Vector2i(7, 5)}
	)
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beat, true)
	_camera.centre_on(IsoProjection.cell_centre_px(7, 5))
	await await_idle_frame()
	var ring: Rect2 = _mark.ring_rect()
	var at: Vector2 = _camera.world_to_screen(IsoProjection.cell_centre_px(7, 5))
	assert_vector(ring.get_center()).is_equal_approx(at, Vector2.ONE * 1.0)
	_camera.zoom = Vector2(2.0, 2.0)
	_camera.centre_on(IsoProjection.cell_centre_px(7, 5))
	await await_idle_frame()
	assert_float(_mark.ring_rect().size.x).is_greater_equal(
		IsoProjection.ellipse_px(ViewScale.MILLI_PER_TILE).x * 4.0 - 1.0
	)


func test_a_tile_off_the_screen_pins_its_ring_inside_the_safe_rect() -> void:
	var beat: TutorialBeatDef = Lesson.beat(
		"tile", NEXT, {"anchor": TutorialBeatDef.Anchor.TILE, "anchor_tile": Vector2i(60, 60)}
	)
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beat, true)
	assert_bool(_safe().grow(TOLERANCE_PX).encloses(_mark.ring_rect())).is_true()


func test_the_card_is_inside_the_safe_rect_and_off_the_ring_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile(size), _control_beat("hit", NEXT))
		for corner: Vector2 in [Vector2(0.5, 0.5), Vector2(0.1, 0.1), Vector2(0.9, 0.9)]:
			_put_target(corner)
			await await_idle_frame()
			await await_idle_frame()
			_expect_card_placed(str(size) + str(corner))
		_close()


func test_a_turn_keeps_the_card_inside_and_off_the_ring() -> void:
	for index: int in ScreenSizes.LANDSCAPE.size():
		await _open(_profile(ScreenSizes.LANDSCAPE[index]), _control_beat("hit", NEXT))
		_put_target(Vector2(0.3, 0.6))
		await await_idle_frame()
		UiScale.set_override(_profile(ScreenSizes.PORTRAIT[index]))
		get_window().size = ScreenSizes.PORTRAIT[index]
		await await_idle_frame()
		_put_target(Vector2(0.3, 0.6))
		await await_idle_frame()
		await await_idle_frame()
		_expect_card_placed("turned %d" % index)
		_close()


func test_the_card_buttons_are_48_dp() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile(size), _control_beat("hit", NEXT))
		var floor_px: float = UiScale.dp(48.0) - TOLERANCE_PX
		for button_name: String in ["Next", "Skip"]:
			var button: Button = _mark.find_child(button_name, true, false) as Button
			assert_bool(button.size.x >= floor_px and button.size.y >= floor_px).is_true()
		_close()


func test_next_shows_only_for_a_read_only_beat_and_calls_the_director() -> void:
	var read: TutorialBeatDef = _control_beat("read", NEXT)
	var zoom: TutorialBeatDef = Lesson.beat("zoom", TutorialConditions.Kind.ZOOM_LEVEL, {})
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), read, false, [read, zoom])
	var next: Button = _mark.find_child("Next", true, false) as Button
	assert_bool(next.is_visible_in_tree()).is_true()
	next.pressed.emit()
	_director.advance()
	assert_bool(_director.current == zoom or _director.current == null).is_true()
	assert_int(_director.progress().x).is_equal(1)


func test_next_is_hidden_on_an_action_beat() -> void:
	var beat: TutorialBeatDef = _control_beat("pan", TutorialConditions.Kind.CAMERA_PANNED)
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beat)
	assert_bool((_mark.find_child("Next", true, false) as Button).visible).is_false()


func test_skip_calls_the_director_and_hides_the_mark() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("read", NEXT))
	var skipped: Array[StringName] = []
	_director.lesson_skipped.connect(func(id: StringName) -> void: skipped.append(id))
	(_mark.find_child("Skip", true, false) as Button).pressed.emit()
	assert_array(skipped).is_equal([&"basics"])
	assert_bool(_director.running()).is_false()
	assert_bool(_mark.visible).is_false()


func test_a_beat_done_hides_the_card_until_the_next_prompt() -> void:
	var read: TutorialBeatDef = _control_beat("read", NEXT)
	var late: TutorialBeatDef = _control_beat("late", NEXT)
	late.delay_ticks = 30
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), read, false, [read, late])
	_director.next()
	assert_bool(_mark.visible).is_false()  # In the gap.
	for _i: int in 30:
		Rig.step(_world, _loop)
	_runner.snapshot = Lesson.snapshot(_world)
	_director.advance()
	assert_bool(_mark.visible).is_true()


func test_a_tap_on_the_ring_target_reaches_it_and_the_ring_and_root_ignore() -> void:
	await _open(
		_profile(ScreenSizes.LANDSCAPE[0]),
		_control_beat("hit", TutorialConditions.Kind.CAMERA_PANNED)
	)
	assert_int(_mark.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(_mark.find_child("Ring", true, false).mouse_filter).is_equal(
		Control.MOUSE_FILTER_IGNORE
	)
	var at: Vector2 = _target.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()
	assert_int(_taps).is_equal(1)


func test_a_tap_on_the_card_body_does_not_reach_the_map() -> void:
	await _open(
		_profile(ScreenSizes.LANDSCAPE[0]),
		_control_beat("hit", TutorialConditions.Kind.CAMERA_PANNED)
	)
	var card: Control = _mark.find_child("Card", true, false) as Control
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	var on_card: Vector2 = _mark.card_rect().get_center()
	_map_taps = 0
	var map: Control = Control.new()  # Stands in for the map under the whole HUD.
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.gui_input.connect(func(_e: InputEvent) -> void: _map_taps += 1)
	add_child(map)
	move_child(map, 0)
	TouchEvents.press(get_viewport(), 0, on_card)
	TouchEvents.release(get_viewport(), 0, on_card)
	await await_idle_frame()
	map.free()
	assert_int(_map_taps).is_equal(0)


func test_a_card_that_cannot_clear_the_ring_lets_a_tap_through_to_the_target() -> void:
	await _open(
		_profile(ScreenSizes.LANDSCAPE[0]),
		_control_beat("hit", TutorialConditions.Kind.CAMERA_PANNED)
	)
	# A ring as wide as the safe rect leaves no room: the card overlaps it.
	_target.size = _safe().size * 0.95
	_target.position = _safe().position + _safe().size * 0.025
	await await_idle_frame()
	await await_idle_frame()
	var card: Control = _mark.find_child("Card", true, false) as Control
	assert_bool(_mark.card_rect().intersects(_mark.ring_rect())).is_true()
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	var at: Vector2 = _mark.card_rect().position + Vector2.ONE * UiScale.dp(24.0)  # On the prompt.
	assert_bool(_target.get_global_rect().has_point(at)).is_true()
	_taps = 0
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()
	assert_int(_taps).is_equal(1)
	_put_target(Vector2(0.5, 0.5))  # Back to a small target: the card clears it and stops again.
	_target.size = Vector2.ONE * UiScale.dp(56.0)
	_put_target(Vector2(0.5, 0.5))
	await await_idle_frame()
	await await_idle_frame()
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)


func test_a_stalled_beat_shows_the_hint_and_a_read_only_one_does_not() -> void:
	var beat: TutorialBeatDef = _control_beat("pan", TutorialConditions.Kind.CAMERA_PANNED)
	beat.budget_s = 2
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beat)
	var hint: Label = _mark.find_child("Hint", true, false) as Label
	assert_bool(hint.visible).is_false()
	for _i: int in 2 * Sim.TICK_RATE:
		Rig.step(_world, _loop)
	_runner.snapshot = Lesson.snapshot(_world)
	assert_bool(_director.stalled()).is_true()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(hint.visible).is_true()
	_expect_card_placed("stalled")


func test_reduced_effects_make_no_tween() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT), false, [], true)
	await await_idle_frame()
	assert_bool(_mark.ring_pulsing()).is_false()
	assert_int(get_tree().get_processed_tweens().size()).is_equal(0)
	_close()
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	await await_idle_frame()
	assert_bool(_mark.ring_pulsing()).is_true()  # Without reduced effects it pulses...
	_mark.hide_mark()
	assert_bool(_mark.ring_pulsing()).is_false()  # ...and stops when hidden.


func test_a_mark_under_an_offset_parent_keeps_global_geometry() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	_offset = Control.new()
	_offset.position = Vector2(80.0, 60.0)
	add_child(_offset)
	_mark.get_parent().remove_child(_mark)
	_offset.add_child(_mark)
	_put_target(Vector2(0.3, 0.4))
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_mark.ring_rect().encloses(_target.get_global_rect())).is_true()
	(
		assert_bool(
			_mark.find_child("Ring", true, false).get_global_rect().position == Vector2.ZERO
		)
		. is_true()
	)
	_expect_card_placed("offset parent")


func test_with_no_ring_the_card_is_clear_of_the_top_hud_at_the_real_sizes() -> void:
	var profiles: Array[UiMetrics] = []
	for size: Vector2i in ScreenSizes.ALL:
		profiles.append(_profile(size))
	for profile_name: StringName in [
		&"web_phone_portrait", &"web_phone_small", &"notch_design", &"notch_design_portrait"
	]:
		profiles.append(UiProfiles.by_name(profile_name))
	for profile: UiMetrics in profiles:
		var beat: TutorialBeatDef = _control_beat("hit", NEXT)
		beat.anchor_control = &"NoSuchControl"
		await _open(profile, beat)
		var label: String = "%s %s" % [profile.os_name, profile.window_size]
		var safe: Rect2 = _safe()
		var shown: HudCorners.Shown = HudCorners.Shown.new()
		shown.toast = true
		var placed: Dictionary[StringName, Rect2] = HudCorners.place(
			safe, HudLayout.is_portrait(), UiScale.base_px_per_dp(), false, shown
		)
		var card: Rect2 = _mark.card_rect()
		for part: StringName in [HudCorners.PILL, HudCorners.SCOPE, HudCorners.TOAST]:
			var rect: Rect2 = placed[part]  # `place` gives screen px, safe origin included.
			(
				assert_bool(card.intersects(rect))
				. override_failure_message(label + " " + part)
				. is_false()
			)
		(
			assert_bool(safe.grow(TOLERANCE_PX).encloses(card))
			. override_failure_message(label)
			. is_true()
		)
		_close()
		UiScale.clear_override()


func test_the_pause_button_stays_tappable_under_a_no_ring_card_upright() -> void:
	for profile_name: StringName in [&"web_phone_portrait", &"notch_design_portrait"]:
		var beat: TutorialBeatDef = _control_beat("hit", NEXT)
		beat.anchor_control = &"NoSuchControl"
		await _open(UiProfiles.by_name(profile_name), beat)
		var pill: Rect2 = Rect2(_safe().position, HudCorners.PILL_DP * UiScale.base_px_per_dp())
		_put_target_at(pill.get_center())  # Stands in for the pill's menu button.
		_taps = 0
		TouchEvents.press(get_viewport(), 0, pill.get_center())
		TouchEvents.release(get_viewport(), 0, pill.get_center())
		await await_idle_frame()
		assert_int(_taps).override_failure_message(str(profile_name)).is_equal(1)
		_close()
		UiScale.clear_override()


func test_the_real_phones_place_a_two_line_prompt_off_the_ring() -> void:
	for profile_name: StringName in [
		&"web_phone_portrait", &"web_phone_small", &"notch_design", &"notch_design_portrait"
	]:
		var beat: TutorialBeatDef = _control_beat("hit", NEXT)
		beat.prompt_key = &"Tap the glowing button at the edge of the screen to open the build menu."
		await _open(UiProfiles.by_name(profile_name), beat)
		for corner: Vector2 in [Vector2(0.5, 0.5), Vector2(0.1, 0.12), Vector2(0.9, 0.9)]:
			_put_target(corner)
			await await_idle_frame()
			await await_idle_frame()
			_expect_card_placed("%s %s" % [profile_name, corner])
		var floor_px: float = UiScale.dp(48.0) - TOLERANCE_PX
		for button_name: String in ["Next", "Skip"]:
			var button: Button = _mark.find_child(button_name, true, false) as Button
			assert_bool(button.size.x >= floor_px and button.size.y >= floor_px).is_true()
		var skip: Rect2 = (_mark.find_child("Skip", true, false) as Button).get_global_rect()
		var next: Rect2 = (_mark.find_child("Next", true, false) as Button).get_global_rect()
		assert_float(next.position.x - skip.end.x).is_greater_equal(UiScale.dp(8.0) - TOLERANCE_PX)
		_close()
		UiScale.clear_override()


func test_in_the_overlap_fallback_a_real_touch_on_skip_ends_the_lesson() -> void:
	await _open(
		UiProfiles.by_name(&"web_phone_small"),
		_control_beat("hit", TutorialConditions.Kind.CAMERA_PANNED)
	)
	_target.size = _safe().size * 0.95
	_target.position = _safe().position + _safe().size * 0.025
	await await_idle_frame()
	await await_idle_frame()
	var card: Control = _mark.find_child("Card", true, false) as Control
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	var skip: Button = _mark.find_child("Skip", true, false) as Button
	var at: Vector2 = skip.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()
	assert_bool(_director.running()).is_false()


func test_the_fallback_prefers_a_card_whose_button_row_misses_the_ring() -> void:
	var room: Rect2 = Rect2(0.0, 0.0, 220.0, 160.0)
	var card: Vector2 = Vector2(200.0, 140.0)
	var ring: Rect2 = Rect2(0.0, 0.0, 220.0, 40.0)
	var row_h: float = 60.0
	var placed: Rect2 = CoachMark.place_card(ring, card, room, 8.0, row_h)
	var row: Rect2 = Rect2(placed.position.x, placed.end.y - row_h, placed.size.x, row_h)
	assert_bool(row.intersects(ring)).is_false()
	assert_bool(room.encloses(placed)).is_true()


func test_freeing_the_target_mid_beat_gives_a_card_alone() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	assert_bool(_mark.ring_rect().has_area()).is_true()
	_target.get_parent().remove_child(_target)
	_target.free()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_mark.ring_rect().has_area()).is_false()
	assert_bool(_mark.ring_pulsing()).is_false()
	assert_object(_mark.target_control()).is_null()
	assert_bool(_safe().grow(TOLERANCE_PX).encloses(_mark.card_rect())).is_true()


func test_a_turn_mid_beat_at_360_dp_keeps_the_card_inside() -> void:
	await _open(UiProfiles.by_name(&"web_phone_portrait"), _control_beat("hit", NEXT))
	_put_target(Vector2(0.3, 0.5))
	await await_idle_frame()
	var turned: UiMetrics = UiProfiles.by_name(&"web_phone")
	UiScale.set_override(turned)
	get_window().size = turned.window_size
	await await_idle_frame()
	_put_target(Vector2(0.3, 0.5))
	await await_idle_frame()
	await await_idle_frame()
	_expect_card_placed("turned at 360 dp")


func test_a_rebind_or_a_null_director_puts_the_old_card_away() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	assert_bool(_mark.visible).is_true()
	var other: TutorialDirector = auto_free(TutorialDirector.new())
	_mark.bind(other)
	assert_bool(_mark.visible).is_false()
	_mark.show_beat(_control_beat("again", NEXT))
	_mark.bind(null)
	assert_bool(_mark.visible).is_false()


func test_a_beat_shown_before_the_mark_is_in_the_tree_shows_when_it_enters() -> void:
	UiScale.set_override(_profile(ScreenSizes.LANDSCAPE[0]))
	_mark = CoachMark.new()
	_mark.hud_root = null
	_mark.bind(_director)
	_mark.show_beat(_control_beat("early", NEXT))  # No viewport yet: no error.
	assert_bool(_mark.visible).is_true()  # A new Control is visible by default.
	add_child(_mark)
	await await_idle_frame()
	assert_bool(_mark.visible).is_true()
	assert_bool(_mark.card_rect().has_area()).is_true()


func test_a_reduced_switch_set_before_ready_is_kept() -> void:
	var mark: CoachMark = CoachMark.new()
	mark.reduced = true
	add_child(mark)
	assert_bool(mark.reduced).is_true()
	remove_child(mark)
	mark.free()


func _control_beat(id: String, kind: TutorialConditions.Kind) -> TutorialBeatDef:
	return Lesson.beat(
		id, kind, {"anchor": TutorialBeatDef.Anchor.CONTROL, "anchor_control": &"CoachTarget"}
	)


func _profile(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	return null


## A mark over a HUD root that holds the named target, with `beat` on show (a lesson of `beats`).
func _open(
	profile: UiMetrics,
	beat: TutorialBeatDef,
	with_camera: bool = false,
	beats: Array = [],
	reduced: bool = false
) -> void:
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_hud_root = Control.new()
	_hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud_root)
	_target = Control.new()
	_target.name = "CoachTarget"
	_target.size = Vector2.ONE * UiScale.dp(56.0)
	_target.gui_input.connect(_on_target_input)
	_hud_root.add_child(_target)
	_put_target(Vector2(0.5, 0.5))
	if with_camera:
		_camera = RtsCamera.new()
		add_child(_camera)
	_mark = CoachMark.new()
	_mark.hud_root = _hud_root
	_mark.camera = _camera
	_mark.director = _director
	_mark.reduced = reduced
	add_child(_mark)
	_director.start(Lesson.lesson("basics", beats if not beats.is_empty() else [beat]))
	_director.advance()
	await await_idle_frame()
	await await_idle_frame()


func _close() -> void:
	_free_nodes()
	_director.skip()


func _free_nodes() -> void:
	for item: Variant in [_mark, _hud_root, _camera, _offset]:
		if is_instance_valid(item):
			var node: Node = item as Node
			node.get_parent().remove_child(node)
			node.free()
	_mark = null
	_hud_root = null
	_camera = null
	_offset = null


## The target's centre at `fraction` of the screen.
func _put_target(fraction: Vector2) -> void:
	_put_target_at(get_viewport().get_visible_rect().size * fraction)


func _put_target_at(centre: Vector2) -> void:
	_target.position = centre - _target.size * 0.5


func _on_target_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null and touch.pressed:
		_taps += 1


func _safe() -> Rect2:
	return SafeAreaMargin.rect_inside(
		get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
	)


func _expect_card_placed(label: String) -> void:
	var card: Rect2 = _mark.card_rect()
	assert_bool(_safe().grow(TOLERANCE_PX).encloses(card)).override_failure_message(label).is_true()
	var ring: Rect2 = _mark.ring_rect()
	assert_bool(ring.has_area()).override_failure_message(label).is_true()
	if not card.intersects(ring.grow(-TOLERANCE_PX)):
		return
	# No room on a short screen (the fallback): the card lets touches through and its buttons
	# keep off the ring.
	var panel: Control = _mark.find_child("Card", true, false) as Control
	assert_int(panel.mouse_filter).override_failure_message(label).is_equal(
		Control.MOUSE_FILTER_IGNORE
	)
	for button_name: String in ["Next", "Skip"]:
		var button: Button = _mark.find_child(button_name, true, false) as Button
		if button.is_visible_in_tree():
			(
				assert_bool(button.get_global_rect().intersects(ring.grow(-TOLERANCE_PX)))
				. override_failure_message(label + " " + button_name)
				. is_false()
			)
