extends GdUnitTestSuite
## P405: AdMobBackend against fake Poing singletons: call order, the callbacks mapped, the banner,
## and the mode choice (ADR 0039 section 2). No real plugin is involved.

signal resized

var _set: FakePoingSet
var _core: FakePoingPlugin
var _inter: FakePoingPlugin
var _rewarded: FakePoingPlugin
var _view: FakePoingPlugin
var _backend: AdMobBackend
var _now: int = 0
var _width: int = 360
var _allowed: bool = true
var _later: Array[Array] = []
var _events: Array[String] = []
var _height_signals: int = 0


func before_test() -> void:
	_set = FakePoingSet.new()
	_core = _set.of(AdMobBackend.S_CORE)
	_inter = _set.of(AdMobBackend.S_INTERSTITIAL)
	_rewarded = _set.of(AdMobBackend.S_REWARDED)
	_view = _set.of(AdMobBackend.S_VIEW)
	_now = 0
	_width = 360
	_allowed = true
	_later = []
	_events = []
	_height_signals = 0
	_backend = _make(_set.lookup)
	_backend.opened.connect(func(kind: StringName) -> void: _events.append("opened " + kind))
	_backend.closed.connect(func(kind: StringName) -> void: _events.append("closed " + kind))
	_backend.reward_earned.connect(func(kind: StringName) -> void: _events.append("reward " + kind))
	_backend.show_failed.connect(func(kind: StringName) -> void: _events.append("failed " + kind))
	_backend.banner_height_changed.connect(func() -> void: _height_signals += 1)


func _make(lookup: Callable) -> AdMobBackend:
	var backend: AdMobBackend = AdMobBackend.new(
		AdIds.new(),
		lookup,
		func() -> int: return _width,
		func() -> int: return _now,
		func(ms: int, callback: Callable) -> void: _later.append([ms, callback]),
		resized
	)
	backend.banner_reload_min_ms = 30000
	backend.can_request_ads = func() -> bool: return _allowed
	return backend


func _ready_sdk() -> void:
	_backend.initialize()
	_core.on_initialization_complete.emit({})
	await get_tree().process_frame


## Loads `kind` and answers the load; returns the ad's uid in its own singleton.
func _fill(kind: StringName) -> int:
	_backend.request_load(kind)
	var plugin: FakePoingPlugin = _inter if kind == AdBackend.KIND_INTERSTITIAL else _rewarded
	var uid: int = int(_last_create(plugin))
	if kind == AdBackend.KIND_INTERSTITIAL:
		plugin.on_interstitial_ad_loaded.emit(uid)
	else:
		plugin.on_rewarded_ad_loaded.emit(uid)
	await get_tree().process_frame
	return uid


func _last_create(plugin: FakePoingPlugin) -> int:
	var uid: int = -1
	for entry: Array in _set.calls:
		if entry[0] == "create" and entry[entry.size() - 1] == plugin.singleton:
			uid = int(entry[2])
	return uid


func _banner_uid() -> int:
	return _last_create(_view)


func _load_banner() -> void:
	_view.on_ad_loaded.emit(_banner_uid())
	await get_tree().process_frame


func test_nothing_is_requested_before_initialize() -> void:
	_backend.request_load(AdBackend.KIND_REWARDED)
	assert_int(_backend.load_state(AdBackend.KIND_REWARDED)).is_equal(AdBackend.LoadState.IDLE)
	assert_array(_set.calls).is_empty()


func test_initialize_sets_the_request_configuration_before_the_sdk_starts() -> void:
	_backend.initialize()
	_backend.initialize()
	assert_array(_set.names()).is_equal(["set_request_configuration", "initialize"])
	var config: Dictionary = _set.args_of("set_request_configuration")[0]
	assert_str(config["max_ad_content_rating"]).is_equal("T")
	assert_int(config["tag_for_child_directed_treatment"]).is_equal(0)
	assert_int(config["tag_for_under_age_of_consent"]).is_equal(0)


func test_a_load_waits_for_the_sdk_and_uses_the_test_unit() -> void:
	_backend.initialize()
	_backend.request_load(AdBackend.KIND_REWARDED)
	assert_int(_set.count("create")).is_equal(0)
	assert_int(_backend.load_state(AdBackend.KIND_REWARDED)).is_equal(AdBackend.LoadState.LOADING)
	_core.on_initialization_complete.emit({})
	await get_tree().process_frame
	assert_array(_set.names()).is_equal(
		["set_request_configuration", "initialize", "create", "load"]
	)
	assert_str(_set.args_of("load")[0]).is_equal(AdIds.TEST_REWARDED)
	assert_int(_set.args_of("load")[3]).is_equal(_set.args_of("create")[1])


func test_a_load_is_not_repeated_while_loading_or_ready() -> void:
	await _ready_sdk()
	await _fill(AdBackend.KIND_INTERSTITIAL)
	_backend.request_load(AdBackend.KIND_INTERSTITIAL)
	assert_int(_set.count("create")).is_equal(1)
	assert_int(_backend.load_state(AdBackend.KIND_INTERSTITIAL)).is_equal(AdBackend.LoadState.READY)


func test_a_failed_load_is_failed_destroys_its_ad_and_a_stranger_uid_is_ignored() -> void:
	await _ready_sdk()
	_backend.request_load(AdBackend.KIND_INTERSTITIAL)
	var uid: int = _last_create(_inter)
	_inter.on_interstitial_ad_loaded.emit(uid + 50)
	await get_tree().process_frame
	assert_int(_backend.load_state(AdBackend.KIND_INTERSTITIAL)).is_equal(
		AdBackend.LoadState.LOADING
	)
	_inter.on_interstitial_ad_failed_to_load.emit(uid, {})
	await get_tree().process_frame
	assert_int(_backend.load_state(AdBackend.KIND_INTERSTITIAL)).is_equal(
		AdBackend.LoadState.FAILED
	)
	assert_array(_set.args_of("destroy")).is_equal([uid])
	_backend.request_load(AdBackend.KIND_INTERSTITIAL)
	assert_int(_set.count("create")).is_equal(2)


func test_an_interstitial_and_a_rewarded_ad_with_the_same_uid_are_told_apart() -> void:
	await _ready_sdk()
	var inter_uid: int = await _fill(AdBackend.KIND_INTERSTITIAL)
	var rewarded_uid: int = await _fill(AdBackend.KIND_REWARDED)
	assert_int(inter_uid).is_equal(rewarded_uid)
	assert_int(_backend.load_state(AdBackend.KIND_INTERSTITIAL)).is_equal(AdBackend.LoadState.READY)
	assert_int(_backend.load_state(AdBackend.KIND_REWARDED)).is_equal(AdBackend.LoadState.READY)
	_backend.show_ad(AdBackend.KIND_INTERSTITIAL)
	_backend.show_ad(AdBackend.KIND_REWARDED)
	_inter.on_interstitial_ad_showed_full_screen_content.emit(inter_uid)
	_rewarded.on_rewarded_ad_showed_full_screen_content.emit(rewarded_uid)
	_rewarded.on_rewarded_ad_user_earned_reward.emit(rewarded_uid, {})
	_inter.on_interstitial_ad_dismissed_full_screen_content.emit(inter_uid)
	await get_tree().process_frame
	assert_array(_events).is_equal(
		["opened interstitial", "opened rewarded", "reward rewarded", "closed interstitial"]
	)
	var shows: Array[Array] = []
	for entry: Array in _set.calls:
		if entry[0] == "show":
			shows.append([entry[2], entry[1]])
	assert_array(shows).is_equal(
		[[AdMobBackend.S_INTERSTITIAL, inter_uid], [AdMobBackend.S_REWARDED, rewarded_uid]]
	)


func test_a_rewarded_show_relays_open_then_reward_then_close_and_frees_the_ad() -> void:
	await _ready_sdk()
	var uid: int = await _fill(AdBackend.KIND_REWARDED)
	_backend.show_ad(AdBackend.KIND_REWARDED)
	assert_array(_set.args_of("show")).is_equal([uid])
	assert_int(_backend.load_state(AdBackend.KIND_REWARDED)).is_equal(AdBackend.LoadState.IDLE)
	_rewarded.on_rewarded_ad_showed_full_screen_content.emit(uid)
	_rewarded.on_rewarded_ad_user_earned_reward.emit(uid, {"amount": 1, "type": "x"})
	_rewarded.on_rewarded_ad_dismissed_full_screen_content.emit(uid)
	assert_array(_events).is_empty()
	await get_tree().process_frame
	assert_array(_events).is_equal(["opened rewarded", "reward rewarded", "closed rewarded"])
	assert_array(_set.args_of("destroy")).is_equal([uid])


func test_a_reward_that_comes_after_the_close_is_relayed_after_it() -> void:
	await _ready_sdk()
	var uid: int = await _fill(AdBackend.KIND_REWARDED)
	_backend.show_ad(AdBackend.KIND_REWARDED)
	_rewarded.on_rewarded_ad_dismissed_full_screen_content.emit(uid)
	_rewarded.on_rewarded_ad_user_earned_reward.emit(uid, {})
	await get_tree().process_frame
	assert_array(_events).is_equal(["closed rewarded"])


func test_an_old_ad_cannot_end_or_reward_a_newer_one_of_the_same_kind() -> void:
	await _ready_sdk()
	var old_uid: int = await _fill(AdBackend.KIND_REWARDED)
	_backend.show_ad(AdBackend.KIND_REWARDED)
	var new_uid: int = await _fill(AdBackend.KIND_REWARDED)
	assert_int(new_uid).is_not_equal(old_uid)
	_backend.show_ad(AdBackend.KIND_REWARDED)
	_rewarded.on_rewarded_ad_user_earned_reward.emit(old_uid, {})
	_rewarded.on_rewarded_ad_dismissed_full_screen_content.emit(old_uid)
	_rewarded.on_rewarded_ad_failed_to_show_full_screen_content.emit(old_uid, {})
	_rewarded.on_rewarded_ad_showed_full_screen_content.emit(old_uid)
	await get_tree().process_frame
	assert_array(_events).is_empty()
	assert_array(_set.args_of("destroy")).is_equal([old_uid])
	_rewarded.on_rewarded_ad_user_earned_reward.emit(new_uid, {})
	_rewarded.on_rewarded_ad_dismissed_full_screen_content.emit(new_uid)
	await get_tree().process_frame
	assert_array(_events).is_equal(["reward rewarded", "closed rewarded"])


func test_a_late_open_of_the_only_shown_ad_is_still_relayed() -> void:
	await _ready_sdk()
	var uid: int = await _fill(AdBackend.KIND_INTERSTITIAL)
	_backend.show_ad(AdBackend.KIND_INTERSTITIAL)
	_backend.cancel_show(AdBackend.KIND_INTERSTITIAL)
	_inter.on_interstitial_ad_showed_full_screen_content.emit(uid)
	await get_tree().process_frame
	assert_array(_events).is_equal(["opened interstitial"])


func test_an_interstitial_failing_to_show_reports_it_and_frees_the_ad() -> void:
	await _ready_sdk()
	var uid: int = await _fill(AdBackend.KIND_INTERSTITIAL)
	_backend.show_ad(AdBackend.KIND_INTERSTITIAL)
	_inter.on_interstitial_ad_failed_to_show_full_screen_content.emit(uid, {})
	await get_tree().process_frame
	assert_array(_events).is_equal(["failed interstitial"])
	assert_array(_set.args_of("destroy")).is_equal([uid])


func test_showing_an_ad_that_is_not_loaded_fails_without_calling_the_plugin() -> void:
	await _ready_sdk()
	_backend.show_ad(AdBackend.KIND_REWARDED)
	assert_array(_events).is_equal(["failed rewarded"])
	assert_int(_set.count("show")).is_equal(0)


func test_no_load_starts_while_ads_may_not_be_requested() -> void:
	_backend.initialize()
	_backend.request_load(AdBackend.KIND_REWARDED)
	_allowed = false
	_core.on_initialization_complete.emit({})
	await get_tree().process_frame
	assert_int(_set.count("create")).is_equal(0)
	assert_int(_backend.load_state(AdBackend.KIND_REWARDED)).is_equal(AdBackend.LoadState.IDLE)
	_backend.request_load(AdBackend.KIND_INTERSTITIAL)
	assert_int(_set.count("create")).is_equal(0)
	_allowed = true
	_backend.request_load(AdBackend.KIND_REWARDED)
	assert_int(_set.count("create")).is_equal(1)


func test_without_the_plugin_every_call_is_safe_and_nothing_fills() -> void:
	var bare: AdMobBackend = _make(func(_name: String) -> Object: return null)
	bare.initialize()
	bare.request_load(AdBackend.KIND_REWARDED)
	bare.show_banner()
	bare.hide_banner()
	bare.destroy_banner()
	assert_int(bare.banner_height_dp()).is_equal(0)
	assert_bool(bare.load_state(AdBackend.KIND_REWARDED) != AdBackend.LoadState.READY).is_true()


func test_the_service_uses_fakes_where_the_plugin_is_missing() -> void:
	assert_bool(AdMobBackend.plugin_present()).is_false()
	assert_bool(UmpPluginBackend.plugin_present()).is_false()
	var script: GDScript = load(AdServiceHarness.SCRIPT_PATH) as GDScript
	assert_bool(script.call("_is_admob_mode")).is_false()
	assert_object(script.call("_make_backend")).is_instanceof(FakeAdBackend)
	assert_object(script.call("_make_consent", false)).is_instanceof(FakeUmp)
