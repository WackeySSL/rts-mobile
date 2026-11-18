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


func test_touches_outside_the_buttons_go_through_to_the_target() -> void:
	await _open(
		_profile(ScreenSizes.LANDSCAPE[0]),
		_control_beat("hit", TutorialConditions.Kind.CAMERA_PANNED)
	)
	assert_int(_mark.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(_mark.find_child("Ring", true, false).mouse_filter).is_equal(
		Control.MOUSE_FILTER_IGNORE
	)
	assert_int(_mark.find_child("Card", true, false).mouse_filter).is_equal(
		Control.MOUSE_FILTER_IGNORE
	)
	var at: Vector2 = _target.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()
	assert_int(_taps).is_equal(1)
	# The card's own text lets a touch through too.
	var on_card: Vector2 = _mark.card_rect().get_center()
	_put_target_at(on_card)
	await await_idle_frame()
	_taps = 0
	TouchEvents.press(get_viewport(), 0, on_card)
	TouchEvents.release(get_viewport(), 0, on_card)
	await await_idle_frame()
	assert_int(_taps).is_equal(1)


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


func test_the_ring_pulses_without_reduced_effects_and_stops_when_hidden() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	await await_idle_frame()
	assert_bool(_mark.ring_pulsing()).is_true()
	_mark.hide_mark()
	assert_bool(_mark.ring_pulsing()).is_false()


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
	add_child(_mark)  # `_ready` reads the player's switch, then the test's own is set.
	_mark.reduced = reduced
	_director.start(Lesson.lesson("basics", beats if not beats.is_empty() else [beat]))
	_director.advance()
	await await_idle_frame()
	await await_idle_frame()


func _close() -> void:
	_free_nodes()
	_director.skip()


func _free_nodes() -> void:
	for item: Variant in [_mark, _hud_root, _camera]:
		if is_instance_valid(item):
			var node: Node = item as Node
			node.get_parent().remove_child(node)
			node.free()
	_mark = null
	_hud_root = null
	_camera = null


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
	(
		assert_bool(card.intersects(ring.grow(-TOLERANCE_PX)))
		. override_failure_message(label + " card over ring")
		. is_false()
	)
