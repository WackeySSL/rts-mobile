extends GdUnitTestSuite
## P405: AdMobBackend against a fake Poing plugin object: call order, the callbacks mapped, the
## banner, and the mode choice (ADR 0039 section 2). No real plugin is involved.

var _plugin: FakePoingPlugin
var _backend: AdMobBackend
var _now: int = 0
var _later: Array[Array] = []
var _events: Array[String] = []


func before_test() -> void:
	_plugin = FakePoingPlugin.new()
	_now = 0
	_later = []
	_events = []
	_backend = _make(_plugin.lookup)
	_backend.opened.connect(func(kind: StringName) -> void: _events.append("opened " + kind))
	_backend.closed.connect(func(kind: StringName) -> void: _events.append("closed " + kind))
	_backend.reward_earned.connect(func(kind: StringName) -> void: _events.append("reward " + kind))
	_backend.show_failed.connect(func(kind: StringName) -> void: _events.append("failed " + kind))


func _make(lookup: Callable) -> AdMobBackend:
	var backend: AdMobBackend = AdMobBackend.new(
		AdIds.new(),
		lookup,
		func() -> int: return 360,
		func() -> int: return _now,
		func(ms: int, callback: Callable) -> void: _later.append([ms, callback])
	)
	backend.banner_reload_min_ms = 30000
	return backend


func _ready_sdk() -> void:
	_backend.initialize()
	_plugin.on_initialization_complete.emit({})
	await get_tree().process_frame


func _fill(kind: StringName) -> int:
	_backend.request_load(kind)
	var uid: int = int(_plugin.args_of("create")[1])
	if kind == AdBackend.KIND_INTERSTITIAL:
		_plugin.on_interstitial_ad_loaded.emit(uid)
	else:
		_plugin.on_rewarded_ad_loaded.emit(uid)
	await get_tree().process_frame
	return uid


func test_nothing_is_requested_before_initialize() -> void:
	_backend.request_load(AdBackend.KIND_REWARDED)
	assert_int(_backend.load_state(AdBackend.KIND_REWARDED)).is_equal(AdBackend.LoadState.IDLE)
	assert_array(_plugin.calls).is_empty()


func test_initialize_sets_the_request_configuration_before_the_sdk_starts() -> void:
	_backend.initialize()
	_backend.initialize()
	assert_array(_plugin.names()).is_equal(["set_request_configuration", "initialize"])
	var config: Dictionary = _plugin.args_of("set_request_configuration")[0]
	assert_str(config["max_ad_content_rating"]).is_equal("T")
	assert_int(config["tag_for_child_directed_treatment"]).is_equal(0)


func test_a_load_waits_for_the_sdk_and_uses_the_test_unit() -> void:
	_backend.initialize()
	_backend.request_load(AdBackend.KIND_REWARDED)
	assert_int(_plugin.count("create")).is_equal(0)
	assert_int(_backend.load_state(AdBackend.KIND_REWARDED)).is_equal(AdBackend.LoadState.LOADING)
	_plugin.on_initialization_complete.emit({})
	await get_tree().process_frame
	assert_array(_plugin.names()).is_equal(
		["set_request_configuration", "initialize", "create", "load"]
	)
	assert_str(_plugin.args_of("load")[0]).is_equal(AdIds.TEST_REWARDED)
	assert_int(_plugin.args_of("load")[3]).is_equal(_plugin.args_of("create")[1])


func test_a_load_is_not_repeated_while_loading_or_ready() -> void:
	await _ready_sdk()
	await _fill(AdBackend.KIND_INTERSTITIAL)
	_backend.request_load(AdBackend.KIND_INTERSTITIAL)
	assert_int(_plugin.count("create")).is_equal(1)
	assert_int(_backend.load_state(AdBackend.KIND_INTERSTITIAL)).is_equal(AdBackend.LoadState.READY)


func test_a_failed_load_is_failed_and_a_stranger_uid_is_ignored() -> void:
	await _ready_sdk()
	_backend.request_load(AdBackend.KIND_INTERSTITIAL)
	var uid: int = int(_plugin.args_of("create")[1])
	_plugin.on_interstitial_ad_loaded.emit(uid + 50)
	await get_tree().process_frame
	assert_int(_backend.load_state(AdBackend.KIND_INTERSTITIAL)).is_equal(
		AdBackend.LoadState.LOADING
	)
	_plugin.on_interstitial_ad_failed_to_load.emit(uid, {})
	await get_tree().process_frame
	assert_int(_backend.load_state(AdBackend.KIND_INTERSTITIAL)).is_equal(
		AdBackend.LoadState.FAILED
	)
	_backend.request_load(AdBackend.KIND_INTERSTITIAL)
	assert_int(_plugin.count("create")).is_equal(2)


func test_a_rewarded_show_relays_open_then_reward_then_close_and_frees_the_ad() -> void:
	await _ready_sdk()
	var uid: int = await _fill(AdBackend.KIND_REWARDED)
	_backend.show_ad(AdBackend.KIND_REWARDED)
	assert_array(_plugin.args_of("show")).is_equal([uid])
	assert_int(_backend.load_state(AdBackend.KIND_REWARDED)).is_equal(AdBackend.LoadState.IDLE)
	_plugin.on_rewarded_ad_showed_full_screen_content.emit(uid)
	_plugin.on_rewarded_ad_user_earned_reward.emit(uid, {"amount": 1, "type": "x"})
	_plugin.on_rewarded_ad_dismissed_full_screen_content.emit(uid)
	assert_array(_events).is_empty()
	await get_tree().process_frame
	assert_array(_events).is_equal(["opened rewarded", "reward rewarded", "closed rewarded"])
	assert_array(_plugin.args_of("destroy")).is_equal([uid])


func test_a_reward_that_comes_after_the_close_is_relayed_after_it() -> void:
	await _ready_sdk()
	var uid: int = await _fill(AdBackend.KIND_REWARDED)
	_backend.show_ad(AdBackend.KIND_REWARDED)
	_plugin.on_rewarded_ad_dismissed_full_screen_content.emit(uid)
	_plugin.on_rewarded_ad_user_earned_reward.emit(uid, {})
	await get_tree().process_frame
	assert_array(_events).is_equal(["closed rewarded"])


func test_an_interstitial_failing_to_show_reports_it_and_frees_the_ad() -> void:
	await _ready_sdk()
	var uid: int = await _fill(AdBackend.KIND_INTERSTITIAL)
	_backend.show_ad(AdBackend.KIND_INTERSTITIAL)
	_plugin.on_interstitial_ad_failed_to_show_full_screen_content.emit(uid, {})
	await get_tree().process_frame
	assert_array(_events).is_equal(["failed interstitial"])
	assert_array(_plugin.args_of("destroy")).is_equal([uid])


func test_showing_an_ad_that_is_not_loaded_fails_without_calling_the_plugin() -> void:
	await _ready_sdk()
	_backend.show_ad(AdBackend.KIND_REWARDED)
	assert_array(_events).is_equal(["failed rewarded"])
	assert_int(_plugin.count("show")).is_equal(0)


func test_cancel_show_does_nothing() -> void:
	await _ready_sdk()
	var uid: int = await _fill(AdBackend.KIND_INTERSTITIAL)
	_backend.show_ad(AdBackend.KIND_INTERSTITIAL)
	var before: int = _plugin.calls.size()
	_backend.cancel_show(AdBackend.KIND_INTERSTITIAL)
	assert_int(_plugin.calls.size()).is_equal(before)
	_plugin.on_interstitial_ad_showed_full_screen_content.emit(uid)
	await get_tree().process_frame
	assert_array(_events).is_equal(["opened interstitial"])


func test_the_banner_is_created_once_at_the_bottom_with_the_adaptive_size() -> void:
	_backend.show_banner()
	_backend.show_banner()
	assert_array(_plugin.names()).is_equal(["adaptive_size", "create", "load_ad"])
	assert_array(_plugin.args_of("adaptive_size")).is_equal([360])
	var view: Dictionary = _plugin.args_of("create")[0]
	assert_str(view["ad_unit_id"]).is_equal(AdIds.TEST_BANNER)
	assert_int(view["ad_position"]).is_equal(AdMobBackend.POSITION_BOTTOM)
	assert_int(_backend.banner_height_dp()).is_equal(56)


func test_hide_and_show_toggle_the_same_banner() -> void:
	_backend.show_banner()
	var uid: int = int(_plugin.args_of("create")[1])
	_backend.hide_banner()
	_backend.hide_banner()
	assert_int(_backend.banner_height_dp()).is_equal(0)
	assert_int(_plugin.count("hide")).is_equal(1)
	_backend.show_banner()
	assert_array(_plugin.args_of("show")).is_equal([uid])
	assert_int(_plugin.count("create")).is_equal(1)
	assert_int(_backend.banner_height_dp()).is_equal(56)


func test_a_failed_banner_reloads_itself_once_per_gap() -> void:
	_backend.show_banner()
	var uid: int = int(_plugin.args_of("create")[1])
	_plugin.on_ad_failed_to_load.emit(uid, {})
	await get_tree().process_frame
	assert_int(_later.size()).is_equal(1)
	assert_int(_later[0][0]).is_equal(30000)
	_now = 29999
	(_later[0][1] as Callable).call()
	assert_int(_plugin.count("load_ad")).is_equal(1)
	_now = 30000
	(_later[0][1] as Callable).call()
	assert_int(_plugin.count("load_ad")).is_equal(2)


func test_without_the_plugin_every_call_is_safe_and_nothing_fills() -> void:
	var bare: AdMobBackend = _make(func(_name: String) -> Object: return null)
	bare.initialize()
	bare.request_load(AdBackend.KIND_REWARDED)
	bare.show_banner()
	bare.hide_banner()
	assert_int(bare.banner_height_dp()).is_equal(0)
	assert_bool(bare.load_state(AdBackend.KIND_REWARDED) != AdBackend.LoadState.READY).is_true()


func test_the_service_uses_fakes_where_the_plugin_is_missing() -> void:
	assert_bool(AdMobBackend.plugin_present()).is_false()
	var script: GDScript = load(AdServiceHarness.SCRIPT_PATH) as GDScript
	assert_bool(script.call("_is_admob_mode")).is_false()
	assert_object(script.call("_make_backend")).is_instanceof(FakeAdBackend)
