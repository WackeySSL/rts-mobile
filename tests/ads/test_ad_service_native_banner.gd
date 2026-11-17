extends GdUnitTestSuite
## P405c: AdService over the real AdMobBackend and fake Poing singletons. The last released band
## destroys the native AdView (ADR 0039 section 6), a reparent in one frame keeps it, and the
## preview height is useful before the first load (the pause foot's first fit check).

signal resized

var _harness: AdServiceHarness
var _set: FakePoingSet
var _service: Node
var _now: int = 0
var _width: int = 360
var _later: Array[Callable] = []


func before_test() -> void:
	_harness = AdServiceHarness.new()
	_set = FakePoingSet.new()
	_now = 0
	_width = 360
	_later = []
	_service = auto_free(_harness.make())
	var backend: AdMobBackend = AdMobBackend.new(
		AdIds.new(),
		_set.lookup,
		func() -> int: return _width,
		func() -> int: return _now,
		func(_ms: int, callback: Callable) -> void: _later.append(callback),
		resized
	)
	backend.can_request_ads = func() -> bool: return _service._can_request_ads
	backend.banner_wanted = func() -> bool: return _service._banner_requests > 0
	backend.banner_height_changed.connect(_service._refresh_banner)
	_service._backend = backend
	_service._initialised = true
	backend.initialize()


func after_test() -> void:
	_harness.dispose()


## The uids of the AdViews created and not destroyed.
func _alive_views() -> Array[int]:
	var uids: Array[int] = []
	for entry: Array in _set.calls:
		if entry[entry.size() - 1] != AdMobBackend.S_VIEW:
			continue
		if entry[0] == "create":
			uids.append(int(entry[2]))
		elif entry[0] == "destroy":
			uids.erase(int(entry[1]))
	return uids


func test_the_last_released_band_destroys_the_native_view() -> void:
	_service.show_banner()
	_service.show_banner()
	assert_array(_alive_views()).has_size(1)
	_service.hide_banner()
	await get_tree().process_frame
	assert_array(_alive_views()).has_size(1)
	_service.hide_banner()
	assert_array(_alive_views()).has_size(1)
	await get_tree().process_frame
	assert_int(_set.count("destroy")).is_equal(1)
	assert_int(_set.count("hide")).is_equal(0)
	assert_array(_alive_views()).is_empty()
	assert_int(_service.banner_height_dp()).is_equal(0)


func test_a_reparent_in_one_frame_keeps_the_native_view() -> void:
	_service.show_banner()
	_service.hide_banner()
	_service.show_banner()
	await get_tree().process_frame
	assert_int(_set.count("destroy")).is_equal(0)
	assert_array(_alive_views()).has_size(1)


func test_the_preview_is_useful_before_the_first_load_and_makes_no_request() -> void:
	_set.of(AdMobBackend.S_SIZE).banner_size = {"width": 360, "height": 56}
	assert_int(_service.banner_height_preview_dp()).is_equal(56)
	assert_int(_set.count("create")).is_equal(0)
	assert_int(_service.banner_height_dp()).is_equal(0)


func test_the_preview_is_zero_where_no_banner_may_show() -> void:
	_service._set_can_request(false)
	assert_int(_service.banner_height_preview_dp()).is_equal(0)
	_service._set_can_request(true)
	assert_int(_service.banner_height_preview_dp()).is_greater(0)
	_service._ledger.remove_ads = true
	assert_int(_service.banner_height_preview_dp()).is_equal(0)
	_service._ledger.remove_ads = false
	_service._initialised = false
	assert_int(_service.banner_height_preview_dp()).is_equal(0)


func _creates() -> int:
	return _set.count("create")


## Closes a band and lets the idle destroy run, then opens one in a later frame.
func _round_trip() -> void:
	_service.hide_banner()
	await get_tree().process_frame
	_service.show_banner()
	await get_tree().process_frame


func test_menu_round_trips_inside_the_gap_make_one_create_and_one_at_its_end() -> void:
	_service.show_banner()
	await get_tree().process_frame
	for i: int in 5:
		_now += 3000
		await _round_trip()
	assert_int(_creates()).is_equal(1)
	assert_int(_set.count("destroy")).is_equal(1)
	assert_int(_service.banner_height_dp()).is_equal(0)
	assert_int(_later.size()).is_equal(1)
	_now = 30000
	for callback: Callable in _later:
		callback.call()
	assert_int(_creates()).is_equal(2)
	assert_array(_alive_views()).is_equal([2])


func test_pause_style_hides_and_turns_inside_the_gap_make_one_create_at_its_end() -> void:
	_service.show_banner()
	_service.hide_banner()
	_service.show_banner()
	await get_tree().process_frame
	assert_int(_set.count("destroy")).is_equal(0)
	_now = 1000
	_width = 640
	resized.emit()
	assert_array(_alive_views()).is_empty()
	_width = 360
	resized.emit()
	_width = 480
	resized.emit()
	await _round_trip()
	assert_int(_creates()).is_equal(1)
	assert_int(_later.size()).is_equal(1)
	_now = 30000
	for callback: Callable in _later:
		callback.call()
	assert_int(_creates()).is_equal(2)
	assert_array(_alive_views()).has_size(1)


func test_a_pending_create_then_the_last_release_then_the_timer_creates_nothing() -> void:
	_service.show_banner()
	await get_tree().process_frame
	_service.hide_banner()
	await get_tree().process_frame
	_now = 1000
	_service.show_banner()
	assert_int(_later.size()).is_equal(1)
	_service.hide_banner()
	await get_tree().process_frame
	_now = 30000
	for callback: Callable in _later:
		callback.call()
	assert_int(_creates()).is_equal(1)
	assert_array(_alive_views()).is_empty()


func test_a_turn_between_the_last_release_and_the_idle_destroy_makes_no_view() -> void:
	_service.show_banner()
	_now = 40000
	_service.hide_banner()
	_width = 640
	resized.emit()
	assert_int(_creates()).is_equal(1)
	await get_tree().process_frame
	assert_array(_alive_views()).is_empty()
	assert_int(_later.size()).is_equal(0)


func test_a_late_callback_of_a_destroyed_banner_changes_nothing() -> void:
	var view: FakePoingPlugin = _set.of(AdMobBackend.S_VIEW)
	_service.show_banner()
	_service.hide_banner()
	await get_tree().process_frame
	_now = 30000
	_service.show_banner()
	assert_array(_alive_views()).is_equal([2])
	view.on_ad_loaded.emit(1)
	view.on_ad_failed_to_load.emit(1, {})
	await get_tree().process_frame
	assert_int(_service.banner_height_dp()).is_equal(0)
	assert_int(_set.count("load_ad")).is_equal(2)
	view.on_ad_loaded.emit(2)
	await get_tree().process_frame
	assert_int(_service.banner_height_dp()).is_equal(56)


## A create made pending: shown at 0, released and destroyed, shown again at 1000 (inside the gap).
func _pending_create() -> void:
	_service.show_banner()
	await get_tree().process_frame
	_service.hide_banner()
	await get_tree().process_frame
	_now = 1000
	_service.show_banner()
	assert_int(_later.size()).is_equal(1)


func test_a_timer_that_fires_while_no_band_asks_is_made_good_by_the_next_show() -> void:
	await _pending_create()
	_service.hide_banner()
	_now = 30000
	for callback: Callable in _later:
		callback.call()
	assert_int(_creates()).is_equal(1)
	_service.show_banner()
	assert_int(_creates()).is_equal(2)
	await get_tree().process_frame
	assert_array(_alive_views()).is_equal([2])


func test_a_timer_made_banner_reaches_a_real_height_and_announces_it() -> void:
	var heights: Array[int] = []
	_service.banner_changed.connect(func(height: int) -> void: heights.append(height))
	await _pending_create()
	_now = 30000
	for callback: Callable in _later:
		callback.call()
	assert_array(_alive_views()).is_equal([2])
	assert_int(_service.banner_height_dp()).is_equal(0)
	_set.of(AdMobBackend.S_VIEW).on_ad_loaded.emit(2)
	await get_tree().process_frame
	assert_int(_service.banner_height_dp()).is_equal(56)
	assert_array(heights).is_equal([56])


func test_consent_lost_while_a_create_is_pending_means_no_create() -> void:
	await _pending_create()
	_service._set_can_request(false)
	_now = 30000
	for callback: Callable in _later:
		callback.call()
	assert_int(_creates()).is_equal(1)
	assert_array(_alive_views()).is_empty()


func test_remove_ads_while_a_create_is_pending_means_no_create() -> void:
	await _pending_create()
	_service._ledger.remove_ads = true
	_service._refresh_banner()
	_now = 30000
	for callback: Callable in _later:
		callback.call()
	assert_int(_creates()).is_equal(1)
	assert_array(_alive_views()).is_empty()
