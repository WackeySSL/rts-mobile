extends GdUnitTestSuite
## IntroPlayer (ADR 0043 section 2, plan P521) on a fake clock, a fake loader and a fake consent.
## The headless renderer draws nothing: the still frame is checked as a layout (the rects the
## splash PNG has under the engine's Keep stretch), the look is a phone check.

const SETTINGS_PATH: String = "res://data/intro_settings.tres"
const MENU_PATH: String = "res://scenes/menu/menu.tscn"
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const Harness: GDScript = preload("res://tests/ads/ad_service_harness.gd")


class FakeConsent:
	extends RefCounted
	signal release
	var calls: int = 0

	func wait() -> bool:
		calls += 1
		await release
		return true


var _now: int = 0
var _loader: FakeIntroLoader
var _consent: FakeConsent
var _host: Control
var _logs: Array[String] = []
var _harness: RefCounted


func before_test() -> void:
	_now = 0
	_logs.clear()
	_loader = FakeIntroLoader.new()
	_loader.scene = load(MENU_PATH) as PackedScene
	_consent = FakeConsent.new()
	_host = auto_free(Control.new())
	add_child(_host)


func after_test() -> void:
	UiScale.clear_override()
	if _harness != null:
		_harness.call("dispose")
		_harness = null


func _make(reduced: bool = false, wait_consent: bool = false) -> IntroPlayer:
	var player: IntroPlayer = IntroPlayer.new()
	player.clock = func() -> int: return _now
	player.loader = _loader
	player.reduced = reduced
	player.host = _host
	player.log_line = func(text: String) -> void: _logs.append(text)
	player.consent = _consent.wait if wait_consent else Callable()
	player.size = Vector2(ScreenSizes.ALL[0])
	add_child(auto_free(player))
	return player


func _at(player: IntroPlayer, ms: int) -> void:
	_now = ms
	player.step()


func test_settings_match_the_art_and_the_splash() -> void:
	var settings: IntroSettings = load(SETTINGS_PATH) as IntroSettings
	var rects: Dictionary[String, Rect2i] = ArtIntro.lockup(ArtIntro.wordmark_size())
	assert_that(settings.icon_rect).is_equal(rects["icon"])
	assert_that(settings.wordmark_rect).is_equal(rects["wordmark"])
	assert_int(settings.splash_side).is_equal(ArtIntro.SPLASH_SIDE)
	assert_that(settings.background).is_equal(Color.html(ArtIntro.SPLASH_BG))
	var stems: Array[String] = []
	stems.append_array(settings.background_layers)
	stems.append_array(settings.foreground_layers)
	assert_array(stems).is_equal(ArtIntro.order())
	assert_int(settings.min_ms).is_equal(600)
	assert_int(settings.max_ms).is_equal(3000)


func test_still_frame_sits_where_the_splash_does_at_the_six_sizes() -> void:
	var player: IntroPlayer = _make()
	var rects: Dictionary[String, Rect2i] = ArtIntro.lockup(ArtIntro.wordmark_size())
	for screen: Vector2i in ScreenSizes.ALL:
		player.apply_layout(Vector2(screen), Rect2(Vector2.ZERO, Vector2(screen)))
		var want: Dictionary[String, Rect2] = ArtIntro.placed(rects, screen)
		assert_that(Rect2(player.icon_box.position, player.icon_box.size)).is_equal(want["icon"])
		assert_that(Rect2(player.wordmark.position, player.wordmark.size)).is_equal(
			want["wordmark"]
		)
		var layer: TextureRect = player.icon_box.get_child(0) as TextureRect
		assert_float(layer.size.x * layer.scale.x).is_equal_approx(want["icon"].size.x, 0.01)
		var line_end: float = player.line.position.y + player.line.size.y
		assert_float(line_end).is_less_equal(float(screen.y))


func test_requests_the_menu_and_the_loads_and_starts_the_consent() -> void:
	var player: IntroPlayer = _make(false, true)
	assert_array(_loader.requested).contains([MENU_PATH])
	assert_int(_consent.calls).is_equal(1)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.DRIVE)


func test_opens_out_at_min_ms_when_everything_is_ready() -> void:
	var player: IntroPlayer = _make()
	_loader.finish()
	_at(player, 0)
	_at(player, 599)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.DRIVE)
	_at(player, 600)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.OPEN)


func test_waits_for_slow_loads_then_settles_and_shows_the_line() -> void:
	var player: IntroPlayer = _make()
	_at(player, 0)
	_at(player, 2999)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.DRIVE)
	assert_bool(player.line.visible).is_false()
	_at(player, 3000)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.SETTLED)
	assert_bool(player.line.visible).is_true()
	assert_float(player.line.size.x).is_greater(0.0)
	_loader.finish()
	_at(player, 9000)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.OPEN)
	assert_bool(player.line.visible).is_false()


func test_never_ends_before_the_consent_returns() -> void:
	var player: IntroPlayer = _make(false, true)
	_loader.finish()
	_at(player, 0)
	_at(player, 5000)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.SETTLED)
	_consent.release.emit()
	_at(player, 5001)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.OPEN)


func test_awaits_ad_service_consent_in_fake_mode() -> void:
	_harness = Harness.new()
	var service: Node = _harness.call("make")
	add_child(auto_free(service))
	service.fake_auto_close = true
	var player: IntroPlayer = _make()
	player.consent = Callable(service, "ensure_consent")
	player.begin()
	for _i: int in 30:
		if player.is_loaded() or true:
			await get_tree().process_frame
	_loader.finish()
	assert_bool(player.is_loaded()).is_true()


func test_a_failed_load_does_not_hang_and_leaves_the_still_frame() -> void:
	var player: IntroPlayer = _make()
	_loader.finish(IntroLoader.State.FAILED)
	_loader.scene = null
	_at(player, 0)
	assert_bool(player.is_loaded()).is_true()
	_at(player, 700)
	_at(player, 800)  # Said once: the still frame and the line stay.
	assert_array(_logs).is_equal(["boot_error: %s did not load" % MENU_PATH])
	assert_int(player.phase).is_equal(IntroPlayer.Phase.SETTLED)
	assert_bool(player.line.visible).is_true()
	assert_array(_host.get_children()).is_empty()


func test_skip_before_loading_ends_the_motion_but_not_the_intro() -> void:
	var player: IntroPlayer = _make()
	_at(player, 0)
	player.skip()
	_at(player, 100)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.SETTLED)
	assert_bool(player.line.visible).is_true()
	_loader.finish()
	_at(player, 200)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.OPEN)


func test_skip_after_loading_opens_out_before_min_ms() -> void:
	var player: IntroPlayer = _make()
	_loader.finish()
	_at(player, 0)
	_at(player, 100)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.DRIVE)
	player.skip()
	_at(player, 120)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.OPEN)


func test_a_touch_and_back_skip() -> void:
	var player: IntroPlayer = _make()
	_at(player, 0)
	TouchEvents.press(get_viewport(), 0, Vector2(100.0, 100.0))
	assert_int(player.phase).is_equal(IntroPlayer.Phase.SETTLED)
	var other: IntroPlayer = _make()
	other.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_int(other.phase).is_equal(IntroPlayer.Phase.SETTLED)


func test_the_drive_moves_the_tank_layers() -> void:
	var player: IntroPlayer = _make()
	_at(player, 0)
	var before: Vector2 = player.tank.position
	_at(player, 130)
	assert_that(player.tank.position).is_not_equal(before)
	var cleats: TextureRect = player.tank.get_child(3) as TextureRect
	assert_that(cleats.position).is_not_equal(Vector2.ZERO)
	var sweep: TextureRect = player.icon_box.get_child(2) as TextureRect
	assert_float(sweep.rotation).is_greater(0.0)


func test_open_out_reaches_the_menu_and_logs_boot_ms() -> void:
	var player: IntroPlayer = _make()
	var got: Array[Node] = []
	player.finished.connect(func(menu: Node) -> void: got.append(menu))
	_loader.finish()
	_at(player, 0)
	_at(player, 600)
	assert_int(_host.get_child_count()).is_equal(1)
	var menu: Control = _host.get_child(0) as Control
	assert_str(menu.scene_file_path).is_equal(MENU_PATH)
	assert_float(menu.modulate.a).is_equal(0.0)
	_at(player, 800)
	assert_float(player.icon_box.scale.x).is_greater(1.0)
	assert_float(player.wordmark.modulate.a).is_equal(0.0)
	assert_float(menu.modulate.a).is_between(0.0, 1.0)
	_at(player, 1000)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.DONE)
	assert_float(menu.modulate.a).is_equal(1.0)
	assert_array(got).is_equal([menu])
	assert_array(_logs).is_equal(["boot_ms=1000"])


func test_reduced_effects_fade_without_the_drive() -> void:
	var player: IntroPlayer = _make(true)
	_loader.finish()
	_at(player, 0)
	_at(player, 300)
	assert_that(player.tank.position).is_equal(Vector2.ZERO)
	_at(player, 600)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.FADE)
	var menu: Control = _host.get_child(0) as Control
	_at(player, 725)
	assert_float(menu.modulate.a).is_equal_approx(0.5, 0.01)
	assert_float(player.icon_box.scale.x).is_equal(1.0)
	_at(player, 850)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.DONE)
	assert_array(_logs).is_equal(["boot_ms=850"])
