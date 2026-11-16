extends GdUnitTestSuite
## IntroPlayer (ADR 0043 section 2, plan P521): skip, Back, the drive, the open-out, the reduced
## fade, the blocker over the faded menu and the production hand-over, on the fakes of IntroRig.

const MENU_PATH: String = "res://scenes/menu/menu.tscn"
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")

var _rig: IntroRig = IntroRig.new()
var _size: Vector2 = Vector2(ScreenSizes.ALL[0])


func before_test() -> void:
	_rig.setup(self, load(MENU_PATH) as PackedScene, _size)


func after_test() -> void:
	_rig.teardown(self)


func test_a_failed_load_does_not_hang_and_leaves_the_still_frame() -> void:
	var player: IntroPlayer = _rig.make(self, _size)
	_rig.loader.finish(IntroLoader.State.FAILED)
	_rig.loader.scene = null
	_rig.at(player, 0)
	assert_bool(player.is_loaded()).is_true()
	_rig.at(player, 700)
	assert_array(_rig.loader.taken).contains([MENU_PATH])
	_rig.at(player, 800)  # Said once: the still frame and the line stay.
	assert_array(_rig.logs).is_equal(["boot_error: %s did not load" % MENU_PATH])
	assert_int(player.phase).is_equal(IntroPlayer.Phase.SETTLED)
	assert_bool(player.line.visible).is_true()
	assert_array(_rig.host.get_children()).is_empty()


func test_skip_before_loading_ends_the_motion_but_not_the_intro() -> void:
	var player: IntroPlayer = _rig.make(self, _size)
	_rig.at(player, 0)
	player.skip()
	_rig.at(player, 100)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.SETTLED)
	assert_bool(player.line.visible).is_true()
	_rig.loader.finish()
	_rig.at(player, 200)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.OPEN)


func test_skip_after_loading_opens_out_before_min_ms() -> void:
	var player: IntroPlayer = _rig.make(self, _size)
	_rig.loader.finish()
	_rig.at(player, 0)
	_rig.at(player, 100)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.DRIVE)
	player.skip()
	_rig.at(player, 120)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.OPEN)


func test_a_touch_and_back_skip() -> void:
	var player: IntroPlayer = _rig.make(self, _size)
	_rig.at(player, 0)
	TouchEvents.press(get_viewport(), 0, Vector2(100.0, 100.0))
	assert_int(player.phase).is_equal(IntroPlayer.Phase.SETTLED)
	var other: IntroPlayer = _rig.make(self, _size)
	other.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_int(other.phase).is_equal(IntroPlayer.Phase.SETTLED)


func test_the_drive_moves_the_tank_layers() -> void:
	var player: IntroPlayer = _rig.make(self, _size)
	_rig.at(player, 0)
	var before: Vector2 = player.tank.position
	_rig.at(player, 130)
	assert_that(player.tank.position).is_not_equal(before)
	var cleats: TextureRect = player.tank.get_child(3) as TextureRect
	assert_that(cleats.position).is_not_equal(Vector2.ZERO)
	var sweep: TextureRect = player.icon_box.get_child(2) as TextureRect
	assert_float(sweep.rotation).is_greater(0.0)


func test_open_out_reaches_the_menu_and_logs_boot_ms() -> void:
	var player: IntroPlayer = _rig.make(self, _size)
	var got: Array[Node] = []
	player.finished.connect(func(menu: Node) -> void: got.append(menu))
	_rig.loader.finish()
	_rig.at(player, 0)
	_rig.at(player, 600)
	assert_int(_rig.host.get_child_count()).is_equal(2)  # The menu and the blocker above it.
	var menu: Control = _rig.host.get_child(0) as Control
	assert_str(menu.scene_file_path).is_equal(MENU_PATH)
	assert_float(menu.modulate.a).is_equal(0.0)
	_rig.at(player, 800)
	assert_float(player.icon_box.scale.x).is_greater(1.0)
	assert_float(player.wordmark.modulate.a).is_equal(0.0)
	assert_float(menu.modulate.a).is_between(0.0, 1.0)
	_rig.at(player, 1000)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.DONE)
	assert_float(menu.modulate.a).is_equal(1.0)
	assert_array(got).is_equal([menu])
	assert_array(_rig.logs).is_equal(["boot_ms=1000"])


func test_reduced_effects_fade_without_the_drive() -> void:
	var player: IntroPlayer = _rig.make(self, _size, true)
	_rig.loader.finish()
	_rig.at(player, 0)
	_rig.at(player, 300)
	assert_that(player.tank.position).is_equal(Vector2.ZERO)
	_rig.at(player, 600)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.FADE)
	var menu: Control = _rig.host.get_child(0) as Control
	_rig.at(player, 725)
	assert_float(menu.modulate.a).is_equal_approx(0.5, 0.01)
	assert_float(player.icon_box.scale.x).is_equal(1.0)
	_rig.at(player, 850)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.DONE)
	assert_array(_rig.logs).is_equal(["boot_ms=850"])


func test_the_loads_beside_the_menu_are_taken_and_a_null_is_ignored() -> void:
	var player: IntroPlayer = _rig.make(self, _size)
	_rig.loader.finish()
	_rig.at(player, 0)
	_rig.at(player, 600)
	for path: String in player.settings.load_paths:
		assert_array(_rig.loader.taken).contains([path])
	assert_int(player.phase).is_equal(IntroPlayer.Phase.OPEN)


func test_back_in_the_intro_does_not_quit_the_app() -> void:
	_rig.make(self, _size)
	assert_bool(get_tree().quit_on_go_back).is_false()


func test_a_click_skips_too() -> void:
	var player: IntroPlayer = _rig.make(self, _size)
	_rig.at(player, 0)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	player._input(click)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.SETTLED)


func test_apply_layout_after_a_drive_leaves_everything_at_rest() -> void:
	var player: IntroPlayer = _rig.make(self, _size)
	_rig.at(player, 0)
	_rig.at(player, 130)
	_rig.at(player, 3000)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.SETTLED)
	player.apply_layout(
		Vector2(ScreenSizes.ALL[3]), Rect2(Vector2.ZERO, Vector2(ScreenSizes.ALL[3]))
	)
	assert_that(player.tank.position).is_equal(Vector2.ZERO)
	assert_float(player.tank.rotation).is_equal(0.0)
	for stem: int in [1, 2]:  # ring, sweep: the background's 2nd and 3rd layers
		var layer: TextureRect = player.icon_box.get_child(stem) as TextureRect
		assert_that(layer.position).is_equal(Vector2.ZERO)
		assert_float(layer.rotation).is_equal(0.0)
		assert_that(layer.pivot_offset).is_equal(Vector2.ZERO)
	for layer: Node in player.tank.get_children():
		assert_float((layer as TextureRect).modulate.a).is_equal(1.0)
		assert_that((layer as TextureRect).position).is_equal(Vector2.ZERO)


func test_the_progress_line_sits_above_the_safe_bottom_at_the_six_sizes() -> void:
	var player: IntroPlayer = _rig.make(self, _size)
	for screen: Vector2i in ScreenSizes.ALL:
		var safe: Rect2 = Rect2(Vector2(40.0, 60.0), Vector2(screen) - Vector2(80.0, 120.0))
		player.apply_layout(Vector2(screen), safe)
		var bottom: float = player.line.position.y + player.line.size.y
		assert_float(bottom).is_equal_approx(
			safe.end.y - UiScale.dp(player.settings.line_bottom_dp), 0.01
		)
		assert_bool(safe.encloses(Rect2(player.line.position, Vector2(1.0, 1.0)))).is_true()


## Headless gui routing is not trusted to reach a button, so the guard is also checked as structure:
## the blocker stands above the menu, takes every touch (STOP) and covers the host.
func _press_at(at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		get_viewport().push_input(event)


func test_the_menu_takes_no_touch_while_the_intro_opens_out() -> void:
	var button: Button = auto_free(Button.new()) as Button
	var scene: PackedScene = PackedScene.new()
	scene.pack(button)
	_rig.loader.scene = scene
	var player: IntroPlayer = _rig.make(self, _size)
	_rig.loader.finish()
	_rig.at(player, 0)
	_rig.at(player, 600)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.OPEN)
	var menu: Button = _rig.host.get_child(0) as Button
	menu.position = Vector2(10.0, 10.0)
	menu.size = Vector2(300.0, 200.0)
	menu.pressed.connect(func() -> void: _rig.presses += 1)
	var blocker: Control = _rig.host.get_child(1) as Control
	assert_int(blocker.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_that(blocker.size).is_equal(_rig.host.size)
	_press_at(Vector2(50.0, 50.0))
	await get_tree().process_frame
	assert_int(_rig.presses).is_equal(0)
	_rig.at(player, 1000)
	await get_tree().process_frame
	assert_bool(is_instance_valid(blocker)).is_false()


func test_the_production_hand_over_makes_the_menu_the_current_scene() -> void:
	var previous: Node = get_tree().current_scene
	var boot: IntroPlayer = (load("res://scenes/boot.tscn") as PackedScene).instantiate()
	boot.clock = func() -> int: return _rig.now
	boot.loader = _rig.loader
	boot.consent = _rig.instant_consent
	boot.log_line = func(text: String) -> void: _rig.logs.append(text)
	var fired: Array[Node] = []
	boot.finished.connect(func(menu: Node) -> void: fired.append(menu))
	get_tree().root.add_child(boot)
	_rig.loader.finish()
	_rig.at(boot, 0)
	_rig.at(boot, 600)
	_rig.at(boot, 1000)
	_rig.at(boot, 1100)
	assert_int(fired.size()).is_equal(1)
	var menu: Node = fired[0]
	assert_object(get_tree().current_scene).is_same(menu)
	await get_tree().process_frame
	assert_bool(is_instance_valid(boot)).is_false()
	assert_bool(menu.get_parent() == get_tree().root).is_true()
	get_tree().current_scene = previous
	menu.free()


func test_back_during_the_open_out_does_not_reach_the_menu() -> void:
	var player: IntroPlayer = _rig.make(self, _size)
	_rig.loader.finish()
	_rig.at(player, 0)
	_rig.at(player, 600)
	var stack: MenuStack = _rig.host.get_child(0).get_node("MenuStack") as MenuStack
	assert_bool(stack.back_enabled).is_false()
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	_rig.at(player, 700)
	await get_tree().process_frame  # The stack defers its back().
	assert_bool(stack.is_asking_to_quit()).is_false()
	_rig.at(player, 1000)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.DONE)
	assert_bool(stack.back_enabled).is_true()
	assert_bool(stack.is_asking_to_quit()).is_false()
