extends GdUnitTestSuite
## IntroPlayer (ADR 0043 section 2, plan P521): the still frame as a layout, the loads, the consent
## and the timing, on a fake clock, a fake loader and a fake consent. The headless renderer draws
## nothing: the look is a phone check. The exits and the input are in test_intro_player_exit.gd.

const SETTINGS_PATH: String = "res://data/intro_settings.tres"
const MENU_PATH: String = "res://scenes/menu/main_menu.tscn"
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const Harness: GDScript = preload("res://tests/ads/ad_service_harness.gd")

var _rig: IntroRig = IntroRig.new()
var _harness: RefCounted
var _size: Vector2 = Vector2(ScreenSizes.ALL[0])


func before_test() -> void:
	_rig.setup(self, load(MENU_PATH) as PackedScene, _size)


func after_test() -> void:
	_rig.teardown(self)
	if _harness != null:
		_harness.call("dispose")
		_harness = null


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
	var player: IntroPlayer = _rig.make(self, _size)
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
	var player: IntroPlayer = _rig.make(self, _size, false, true)
	assert_array(_rig.loader.requested).contains([MENU_PATH])
	assert_int(_rig.consent.calls).is_equal(1)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.DRIVE)


func test_opens_out_at_min_ms_when_everything_is_ready() -> void:
	var player: IntroPlayer = _rig.make(self, _size)
	_rig.loader.finish()
	_rig.at(player, 0)
	_rig.at(player, 599)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.DRIVE)
	_rig.at(player, 600)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.OPEN)


func test_waits_for_slow_loads_then_settles_and_shows_the_line() -> void:
	var player: IntroPlayer = _rig.make(self, _size)
	_rig.at(player, 0)
	_rig.at(player, 2999)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.DRIVE)
	assert_bool(player.line.visible).is_false()
	_rig.at(player, 3000)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.SETTLED)
	assert_bool(player.line.visible).is_true()
	assert_float(player.line.size.x).is_greater(0.0)
	_rig.loader.finish()
	_rig.at(player, 9000)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.OPEN)
	assert_bool(player.line.visible).is_false()


func test_never_ends_before_the_consent_returns() -> void:
	var player: IntroPlayer = _rig.make(self, _size, false, true)
	_rig.loader.finish()
	_rig.at(player, 0)
	_rig.at(player, 5000)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.SETTLED)
	_rig.consent.release.emit()
	_rig.at(player, 5001)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.OPEN)


func test_awaits_ad_service_consent_in_fake_mode() -> void:
	_harness = Harness.new()
	var service: Node = _harness.call("make")
	add_child(auto_free(service))
	service.fake_auto_close = true
	var player: IntroPlayer = _rig.make(
		self, _size, false, false, Callable(service, "ensure_consent")
	)
	assert_bool(player.is_loaded()).is_false()  # The loads are still running.
	for _i: int in 60:
		if player.consent_done():
			break
		await get_tree().process_frame
	assert_bool(player.consent_done()).is_true()
	_rig.loader.finish()
	assert_bool(player.is_loaded()).is_true()
