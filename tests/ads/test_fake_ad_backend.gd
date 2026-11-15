extends GdUnitTestSuite
## P403: the fake backend's script switches and the mode choice (ADR 0039 section 2).


func test_admob_mode_needs_android_a_non_editor_build_the_plugin_and_the_play_tag() -> void:
	assert_bool(AdBackend.is_admob_mode("Android", false, true, true)).is_true()
	assert_bool(AdBackend.is_admob_mode("iOS", false, true, true)).is_false()
	assert_bool(AdBackend.is_admob_mode("Android", true, true, true)).is_false()
	assert_bool(AdBackend.is_admob_mode("Android", false, false, true)).is_false()
	assert_bool(AdBackend.is_admob_mode("Android", false, true, false)).is_false()
	assert_bool(AdBackend.is_admob_mode("Linux", false, false, false)).is_false()


func test_the_service_uses_the_fake_backend_for_now() -> void:
	var service: Node = auto_free(load(AdServiceHarness.SCRIPT_PATH).new())
	assert_object(service._backend).is_instanceof(FakeAdBackend)


func test_the_service_hands_its_auto_close_to_the_fake() -> void:
	var service: Node = auto_free(load(AdServiceHarness.SCRIPT_PATH).new())
	var fake: FakeAdBackend = AdServiceHarness.fake(service)
	service.fake_auto_close = false
	service.rewarded_ready(&"any")
	assert_bool(fake.auto_close).is_false()
	assert_bool(fake.draw_placeholders).is_true()
	service.fake_auto_close = true
	service.rewarded_ready(&"any")
	assert_bool(fake.auto_close).is_true()
	assert_bool(fake.draw_placeholders).is_false()


func test_the_base_backend_never_fills_and_shows_nothing() -> void:
	var backend: AdBackend = AdBackend.new()
	backend.request_load(AdBackend.KIND_REWARDED)
	assert_int(backend.load_state(AdBackend.KIND_REWARDED)).is_equal(AdBackend.LoadState.FAILED)
	assert_int(backend.banner_height_dp()).is_equal(0)


func test_the_fake_loads_per_its_script() -> void:
	var fake: FakeAdBackend = FakeAdBackend.new()
	assert_int(fake.load_state(&"interstitial")).is_equal(AdBackend.LoadState.IDLE)
	fake.request_load(&"interstitial")
	assert_int(fake.load_state(&"interstitial")).is_equal(AdBackend.LoadState.READY)
	fake.fill = false
	fake.request_load(&"rewarded")
	assert_int(fake.load_state(&"rewarded")).is_equal(AdBackend.LoadState.FAILED)
	fake.load_never_answers = true
	fake.request_load(&"rewarded")
	assert_int(fake.load_state(&"rewarded")).is_equal(AdBackend.LoadState.LOADING)


func test_a_show_without_a_loaded_ad_does_nothing() -> void:
	var fake: FakeAdBackend = FakeAdBackend.new()
	var seen: Array[String] = []
	fake.opened.connect(func(_kind: StringName) -> void: seen.append("opened"))
	fake.show_ad(AdBackend.KIND_INTERSTITIAL)
	assert_array(seen).is_empty()
	assert_array(fake.shows).is_empty()


func test_a_cancelled_show_cannot_open_late_unless_the_backend_ignores_the_cancel() -> void:
	var fake: FakeAdBackend = FakeAdBackend.new()
	var seen: Array[String] = []
	fake.opened.connect(func(_kind: StringName) -> void: seen.append("opened"))
	fake.show_never_opens = true
	fake.request_load(AdBackend.KIND_INTERSTITIAL)
	fake.show_ad(AdBackend.KIND_INTERSTITIAL)
	fake.cancel_show(AdBackend.KIND_INTERSTITIAL)
	fake.open_late()
	assert_array(seen).is_empty()
	fake.ignore_cancel = true
	fake.request_load(AdBackend.KIND_INTERSTITIAL)
	fake.show_ad(AdBackend.KIND_INTERSTITIAL)
	fake.cancel_show(AdBackend.KIND_INTERSTITIAL)
	fake.open_late()
	assert_array(seen).contains_exactly(["opened"])


func test_without_auto_close_and_without_a_host_a_show_closes_as_scripted() -> void:
	var fake: FakeAdBackend = FakeAdBackend.new()
	fake.auto_close = false
	fake.draw_placeholders = true
	var seen: Array[String] = []
	fake.opened.connect(func(_kind: StringName) -> void: seen.append("opened"))
	fake.closed.connect(func(_kind: StringName) -> void: seen.append("closed"))
	fake.request_load(AdBackend.KIND_INTERSTITIAL)
	fake.show_ad(AdBackend.KIND_INTERSTITIAL)
	assert_array(seen).contains_exactly(["opened", "closed"])


func test_a_rewarded_and_an_interstitial_show_can_be_pending_at_once() -> void:
	var fake: FakeAdBackend = FakeAdBackend.new()
	fake.show_never_opens = true
	var seen: Array[String] = []
	fake.opened.connect(func(kind: StringName) -> void: seen.append("opened:" + kind))
	fake.request_load(AdBackend.KIND_INTERSTITIAL)
	fake.request_load(AdBackend.KIND_REWARDED)
	fake.show_ad(AdBackend.KIND_INTERSTITIAL)
	fake.show_ad(AdBackend.KIND_REWARDED)
	fake.open_late(AdBackend.KIND_INTERSTITIAL)
	assert_array(seen).contains_exactly(["opened:interstitial"])
	fake.open_late()
	assert_array(seen).contains_exactly(["opened:interstitial", "opened:rewarded"])
