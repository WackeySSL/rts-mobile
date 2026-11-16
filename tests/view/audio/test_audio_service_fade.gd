extends GdUnitTestSuite
## AudioService's AdService hook (ADR 0041 section 5, whatever the autoload order) and the Master
## fade with the shipped `fade_ms`; the immediate mute of `background` in the middle of a fade.

const SERVICE_SCRIPT: String = "res://game/view/audio/audio_service.gd"
const SETTINGS_PATH: String = "res://data/audio_settings.tres"
const REASONS: Array[StringName] = [&"background", &"ad", &"restoring"]

var _service: Node
var _settings: AudioSettings


func before_test() -> void:
	_settings = (load(SETTINGS_PATH) as AudioSettings).duplicate()
	_settings.fade_ms = 0
	_service = _make_service()
	add_child(_service)


func after_test() -> void:
	for reason: StringName in REASONS:
		_service.call(&"clear_mute_reason", reason)
	_service.call(&"set_step", &"Music", _settings.default_music_step)
	_service.call(&"set_sound_step", _settings.default_sfx_step)
	_service.free()


func _make_service() -> Node:
	var service: Node = (load(SERVICE_SCRIPT) as GDScript).new()
	service.set("settings", _settings)
	return service


func _master_muted() -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master"))


func _fake_ad_service(node_name: String) -> Node:
	var ads: Node = Node.new()
	ads.name = node_name
	ads.add_user_signal("ad_opened", [{"name": "placement", "type": TYPE_STRING_NAME}])
	ads.add_user_signal("ad_closed", [{"name": "placement", "type": TYPE_STRING_NAME}])
	return ads


## A service that looks for a root child of a test-only name, so a real /root/AdService (Phase 6)
## is neither hooked nor disturbed.
func _make_service_for(node_name: StringName) -> Node:
	var service: Node = _make_service()
	service.set("ad_service_name", node_name)
	return service


func test_connect_ad_service_hook_drives_the_ad_reason() -> void:
	var ads: Node = _fake_ad_service("FakeAds")
	add_child(ads)
	_service.call(&"connect_ad_service", ads)
	_service.call(&"connect_ad_service", ads)
	assert_int(ads.get_signal_connection_list("ad_opened").size()).is_equal(1)
	ads.emit_signal("ad_opened", &"post_match")
	assert_bool(_service.call(&"has_mute_reason", &"ad")).is_true()
	assert_bool(_master_muted()).is_true()
	ads.emit_signal("ad_closed", &"post_match")
	assert_bool(_service.call(&"is_muted")).is_false()
	assert_bool(_master_muted()).is_false()
	ads.emit_signal("ad_opened", &"menu")
	_service.call(&"disconnect_ad_service", ads)
	assert_bool(_service.call(&"is_muted")).is_false()
	ads.emit_signal("ad_opened", &"menu")
	assert_bool(_service.call(&"is_muted")).is_false()


func test_ad_service_added_after_the_service_is_hooked_lazily() -> void:
	var service: Node = _make_service_for(&"FakeAdsLazy")
	add_child(service)
	var ads: Node = _fake_ad_service("FakeAdsLazy")
	get_tree().root.add_child(ads)
	ads.emit_signal("ad_opened", &"menu")
	assert_bool(service.call(&"has_mute_reason", &"ad")).is_true()
	ads.emit_signal("ad_closed", &"menu")
	assert_bool(service.call(&"is_muted")).is_false()
	service.free()
	ads.free()


func test_ad_service_already_in_the_tree_is_hooked_at_ready() -> void:
	var ads: Node = _fake_ad_service("FakeAdsReady")
	get_tree().root.add_child(ads)
	var service: Node = _make_service_for(&"FakeAdsReady")
	add_child(service)
	ads.emit_signal("ad_opened", &"menu")
	assert_bool(service.call(&"has_mute_reason", &"ad")).is_true()
	ads.emit_signal("ad_closed", &"menu")
	assert_bool(service.call(&"is_muted")).is_false()
	service.free()
	ads.free()


func test_no_ad_service_is_fine() -> void:
	var service: Node = _make_service_for(&"FakeAdsNever")
	add_child(service)
	assert_bool(service.call(&"is_muted")).is_false()
	service.free()


func test_background_mutes_at_once_in_the_middle_of_a_fade() -> void:
	_service.free()
	_settings = load(SETTINGS_PATH)
	_service = _make_service()
	add_child(_service)
	_service.call(&"add_mute_reason", &"ad")
	assert_bool(_master_muted()).is_false()
	_service.call(&"add_mute_reason", &"background")
	assert_bool(_master_muted()).is_true()
	await await_millis(300)
	assert_bool(_master_muted()).is_true()
	assert_float(AudioServer.get_bus_volume_db(0)).is_equal(_settings.mute_floor_db)


func test_shipped_fade_out_and_in() -> void:
	_service.free()
	_settings = load(SETTINGS_PATH)
	_service = _make_service()
	add_child(_service)
	_service.call(&"add_mute_reason", &"ad")
	assert_bool(_master_muted()).is_false()
	await await_millis(_settings.fade_ms + 250)
	assert_bool(_master_muted()).is_true()
	assert_float(AudioServer.get_bus_volume_db(0)).is_equal(_settings.mute_floor_db)
	_service.call(&"clear_mute_reason", &"ad")
	assert_bool(_master_muted()).is_false()
	await await_millis(_settings.fade_ms + 250)
	assert_bool(_master_muted()).is_false()
	assert_float(AudioServer.get_bus_volume_db(0)).is_equal(0.0)
