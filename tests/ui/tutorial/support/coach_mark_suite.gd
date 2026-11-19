extends GdUnitTestSuite
## The coach mark suites' shared set-up (plan row P542): the director over a fixture world, a HUD
## root with a named target, a mark, and the helpers that open and close them. Not a test suite.
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
