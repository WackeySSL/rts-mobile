extends GdUnitTestSuite
## P405c: AdService over the real AdMobBackend and fake Poing singletons. The last released band
## destroys the native AdView (ADR 0039 section 6), a reparent in one frame keeps it, and the
## preview height is useful before the first load (the pause foot's first fit check).

var _harness: AdServiceHarness
var _set: FakePoingSet
var _service: Node


func before_test() -> void:
	_harness = AdServiceHarness.new()
	_set = FakePoingSet.new()
	_service = auto_free(_harness.make())
	var backend: AdMobBackend = AdMobBackend.new(
		AdIds.new(),
		_set.lookup,
		func() -> int: return 360,
		func() -> int: return 0,
		func(_ms: int, _callback: Callable) -> void: pass,
		Signal()
	)
	backend.can_request_ads = func() -> bool: return _service._can_request_ads
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
