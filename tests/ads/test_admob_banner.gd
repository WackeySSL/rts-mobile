extends GdUnitTestSuite
## P405: AdMobBackend's banner against fake Poing singletons: its size, its height only once loaded,
## the reload after a failure, and the new banner after a turn of the phone (ADR 0039 section 5).

signal resized

var _set: FakePoingSet
var _view: FakePoingPlugin
var _backend: AdMobBackend
var _now: int = 0
var _width: int = 360
var _later: Array[Array] = []
var _height_signals: int = 0


func before_test() -> void:
	_set = FakePoingSet.new()
	_view = _set.of(AdMobBackend.S_VIEW)
	_now = 0
	_width = 360
	_later = []
	_height_signals = 0
	_backend = AdMobBackend.new(
		AdIds.new(),
		_set.lookup,
		func() -> int: return _width,
		func() -> int: return _now,
		func(ms: int, callback: Callable) -> void: _later.append([ms, callback]),
		resized
	)
	_backend.banner_reload_min_ms = 30000
	_backend.banner_height_changed.connect(func() -> void: _height_signals += 1)


func _banner_uid() -> int:
	var uid: int = -1
	for entry: Array in _set.calls:
		if entry[0] == "create":
			uid = int(entry[2])
	return uid


func _load_banner() -> void:
	_view.on_ad_loaded.emit(_banner_uid())
	await get_tree().process_frame


func test_the_banner_is_created_once_at_the_bottom_with_the_adaptive_size() -> void:
	_backend.show_banner()
	_backend.show_banner()
	assert_array(_set.names()).is_equal(["adaptive_size", "create", "load_ad"])
	assert_array(_set.args_of("adaptive_size")).is_equal([360])
	var view: Dictionary = _set.args_of("create")[0]
	assert_str(view["ad_unit_id"]).is_equal(AdIds.TEST_BANNER)
	assert_int(view["ad_position"]).is_equal(AdMobBackend.POSITION_BOTTOM)


func test_the_banner_has_no_height_until_it_loads_and_none_after_a_failure() -> void:
	_backend.show_banner()
	assert_int(_backend.banner_height_dp()).is_equal(0)
	await _load_banner()
	assert_int(_backend.banner_height_dp()).is_equal(56)
	assert_int(_height_signals).is_equal(1)
	_view.on_ad_failed_to_load.emit(_banner_uid(), {})
	await get_tree().process_frame
	assert_int(_backend.banner_height_dp()).is_equal(0)
	assert_int(_height_signals).is_equal(2)


func test_hide_and_show_toggle_the_same_banner() -> void:
	_backend.show_banner()
	await _load_banner()
	var uid: int = _banner_uid()
	_backend.hide_banner()
	_backend.hide_banner()
	assert_int(_backend.banner_height_dp()).is_equal(0)
	assert_int(_set.count("hide")).is_equal(1)
	_backend.show_banner()
	assert_array(_set.args_of("show")).is_equal([uid])
	assert_int(_set.count("create")).is_equal(1)
	assert_int(_backend.banner_height_dp()).is_equal(56)


func test_destroy_banner_takes_the_view_away_and_a_later_show_waits_for_the_gap() -> void:
	_backend.show_banner()
	await _load_banner()
	var uid: int = _banner_uid()
	_backend.destroy_banner()
	assert_array(_set.args_of("destroy")).is_equal([uid])
	assert_int(_backend.banner_height_dp()).is_equal(0)
	_backend.destroy_banner()
	assert_int(_set.count("destroy")).is_equal(1)
	_backend.show_banner()
	assert_int(_set.count("create")).is_equal(1)
	assert_int(_later.size()).is_equal(1)
	assert_int(_later[0][0]).is_equal(30000)
	_now = 30000
	(_later[0][1] as Callable).call()
	assert_int(_set.count("create")).is_equal(2)


func test_a_failed_banner_reloads_itself_once_per_gap_even_when_the_timer_is_early() -> void:
	_backend.show_banner()
	_view.on_ad_failed_to_load.emit(_banner_uid(), {})
	await get_tree().process_frame
	assert_int(_later.size()).is_equal(1)
	assert_int(_later[0][0]).is_equal(30000)
	_now = 29999
	(_later[0][1] as Callable).call()
	assert_int(_set.count("load_ad")).is_equal(1)
	assert_int(_later.size()).is_equal(2)
	assert_int(_later[1][0]).is_equal(1)
	_now = 30000
	(_later[1][1] as Callable).call()
	assert_int(_set.count("load_ad")).is_equal(2)
	assert_int(_later.size()).is_equal(2)


func test_a_turn_after_the_gap_makes_it_again_at_the_new_width() -> void:
	_backend.show_banner()
	await _load_banner()
	var old_uid: int = _banner_uid()
	_now = 40000
	_set.of(AdMobBackend.S_SIZE).banner_size = {"width": 640, "height": 50}
	_width = 640
	resized.emit()
	assert_array(_set.args_of("destroy")).is_equal([old_uid])
	assert_int(_set.count("create")).is_equal(2)
	var sizes: Array = _set.calls.filter(func(e: Array) -> bool: return e[0] == "adaptive_size")
	assert_array(sizes[1]).is_equal(["adaptive_size", 640, AdMobBackend.S_SIZE])
	assert_int(_backend.banner_height_dp()).is_equal(0)
	await _load_banner()
	assert_int(_backend.banner_height_dp()).is_equal(50)
	resized.emit()
	assert_int(_set.count("create")).is_equal(2)


func test_a_turn_while_the_banner_is_hidden_is_handled_at_the_next_show() -> void:
	_backend.show_banner()
	_backend.hide_banner()
	_width = 640
	resized.emit()
	assert_int(_set.count("create")).is_equal(1)
	_now = 40000
	_backend.show_banner()
	assert_int(_set.count("create")).is_equal(2)
	assert_int(_set.count("destroy")).is_equal(1)


func test_turns_inside_the_gap_take_the_banner_down_now_and_remake_it_once_at_its_end() -> void:
	_backend.initialize()
	_backend.show_banner()
	await _load_banner()
	_height_signals = 0
	_now = 1000
	_width = 640
	resized.emit()
	assert_int(_set.count("destroy")).is_equal(1)
	assert_int(_backend.banner_height_dp()).is_equal(0)
	assert_int(_height_signals).is_equal(1)
	assert_int(_set.count("create")).is_equal(1)
	_now = 5000
	_width = 480
	resized.emit()
	assert_int(_set.count("create")).is_equal(1)
	assert_int(_later.size()).is_equal(1)
	assert_int(_later[0][0]).is_equal(29000)
	_now = 29999
	(_later[0][1] as Callable).call()
	assert_int(_set.count("create")).is_equal(1)
	assert_int(_later.size()).is_equal(2)
	_now = 30000
	(_later[1][1] as Callable).call()
	assert_int(_set.count("create")).is_equal(2)
	assert_int(_set.count("destroy")).is_equal(1)
	var sizes: Array = _set.calls.filter(func(e: Array) -> bool: return e[0] == "adaptive_size")
	assert_array(sizes.back()).is_equal(["adaptive_size", 480, AdMobBackend.S_SIZE])


func test_a_pending_create_does_nothing_once_the_banner_is_no_longer_wanted() -> void:
	_backend.show_banner()
	_now = 1000
	_width = 640
	resized.emit()
	assert_int(_later.size()).is_equal(1)
	_backend.destroy_banner()
	_now = 30000
	(_later[0][1] as Callable).call()
	assert_int(_set.count("create")).is_equal(1)


func test_no_banner_is_made_while_the_service_has_no_request() -> void:
	var wanted: Array[bool] = [true]
	_backend.banner_wanted = func() -> bool: return wanted[0]
	_backend.show_banner()
	await _load_banner()
	wanted[0] = false
	_now = 40000
	_width = 640
	resized.emit()
	assert_int(_set.count("create")).is_equal(1)
	assert_int(_later.size()).is_equal(0)


func test_the_preview_height_is_the_adaptive_size_before_the_first_load() -> void:
	assert_int(_backend.banner_height_preview_dp()).is_equal(0)
	_backend.initialize()
	assert_int(_backend.banner_height_preview_dp()).is_equal(56)
	assert_int(_set.count("create")).is_equal(0)
	_backend.show_banner()
	assert_int(_backend.banner_height_preview_dp()).is_equal(56)
	await _load_banner()
	assert_int(_backend.banner_height_dp()).is_equal(56)
	assert_int(_backend.banner_height_preview_dp()).is_equal(56)
