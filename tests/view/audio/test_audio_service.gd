extends GdUnitTestSuite
## AudioService (ADR 0041 sections 2, 3 and 5) on the dummy audio driver: mute reasons that stack
## and clear in any order, volume steps per bus (step 0 mutes), nothing plays while muted, and the
## pool's caps, priority steal and per-tick budget. A fresh service per test; the shared buses go
## back to the defaults afterwards.

const SERVICE_SCRIPT: String = "res://game/view/audio/audio_service.gd"
const SETTINGS_PATH: String = "res://data/audio_settings.tres"
const REASONS: Array[StringName] = [&"background", &"ad", &"restoring"]

var _service: Node
var _settings: AudioSettings
var _stream: AudioStreamWAV


func before_test() -> void:
	_settings = (load(SETTINGS_PATH) as AudioSettings).duplicate()
	_settings.fade_ms = 0
	_service = _make_service()
	add_child(_service)
	_stream = AudioStreamWAV.new()
	_stream.format = AudioStreamWAV.FORMAT_8_BITS
	_stream.data = PackedByteArray([0, 0, 0, 0])
	_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_stream.loop_end = 4


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


func _bus_muted(bus: StringName) -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index(bus))


func test_reasons_stack_and_clear_in_any_order() -> void:
	var orders: Array = [
		[&"background", &"ad", &"restoring"],
		[&"restoring", &"background", &"ad"],
		[&"ad", &"restoring", &"background"],
	]
	for order: Array in orders:
		for reason: StringName in REASONS:
			_service.call(&"add_mute_reason", reason)
		for i: int in order.size():
			assert_bool(_master_muted()).is_true()
			_service.call(&"clear_mute_reason", order[i])
		assert_bool(_service.call(&"is_muted")).is_false()
		assert_bool(_master_muted()).is_false()


func test_reasons_are_idempotent() -> void:
	_service.call(&"add_mute_reason", &"ad")
	_service.call(&"add_mute_reason", &"ad")
	_service.call(&"clear_mute_reason", &"ad")
	assert_bool(_service.call(&"is_muted")).is_false()
	_service.call(&"clear_mute_reason", &"ad")
	assert_bool(_master_muted()).is_false()


func test_notifications_add_and_clear_background() -> void:
	var pairs: Array = [
		[Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_APPLICATION_RESUMED],
		[Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_FOCUS_IN],
	]
	for pair: Array in pairs:
		_service.notification(pair[0])
		assert_bool(_service.call(&"has_mute_reason", &"background")).is_true()
		assert_bool(_master_muted()).is_true()
		_service.notification(pair[1])
		assert_bool(_service.call(&"is_muted")).is_false()
		assert_bool(_master_muted()).is_false()


func test_pause_and_focus_out_are_one_reason() -> void:
	_service.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_service.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_service.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	assert_bool(_service.call(&"is_muted")).is_false()


func test_ad_service_signals_drive_the_ad_reason() -> void:
	var ads: Node = Node.new()
	ads.name = "AdService"
	ads.add_user_signal("ad_opened")
	ads.add_user_signal("ad_closed")
	get_tree().root.add_child(ads)
	var other: Node = _make_service()
	add_child(other)
	ads.emit_signal("ad_opened")
	assert_bool(other.call(&"has_mute_reason", &"ad")).is_true()
	assert_bool(_master_muted()).is_true()
	ads.emit_signal("ad_closed")
	assert_bool(other.call(&"is_muted")).is_false()
	other.free()
	ads.free()


func test_no_ad_service_is_fine() -> void:
	assert_bool(get_tree().root.has_node(^"AdService")).is_false()
	assert_bool(_service.call(&"is_muted")).is_false()


func test_step_zero_mutes_its_bus_only() -> void:
	_service.call(&"set_step", &"Music", 0)
	assert_bool(_bus_muted(&"Music")).is_true()
	assert_bool(_bus_muted(&"Sfx")).is_false()
	_service.call(&"set_step", &"Music", 5)
	assert_bool(_bus_muted(&"Music")).is_false()
	var db: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music"))
	assert_float(db).is_equal_approx(linear_to_db(0.5), 0.001)


func test_steps_clamp_and_full_step_is_0_db() -> void:
	_service.call(&"set_step", &"Sfx", 99)
	assert_int(_service.call(&"get_step", &"Sfx")).is_equal(_settings.steps)
	assert_float(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Sfx"))).is_equal(0.0)
	_service.call(&"set_step", &"Sfx", -3)
	assert_int(_service.call(&"get_step", &"Sfx")).is_equal(0)


func test_sound_step_sets_sfx_and_ui_together() -> void:
	_service.call(&"set_sound_step", 0)
	assert_int(_service.call(&"get_step", &"Sfx")).is_equal(0)
	assert_int(_service.call(&"get_step", &"Ui")).is_equal(0)
	assert_int(_service.call(&"get_step", &"Music")).is_equal(_settings.default_music_step)


func test_nothing_plays_while_muted() -> void:
	assert_bool(_service.call(&"play_world", _stream, Vector2.ZERO, &"shot")).is_true()
	assert_bool(_service.call(&"play_ui", _stream, &"click")).is_true()
	_service.call(&"add_mute_reason", &"ad")
	assert_int(_service.pool.active_world()).is_equal(0)
	assert_int(_service.pool.active_ui()).is_equal(0)
	assert_bool(_service.call(&"play_world", _stream, Vector2.ZERO, &"shot")).is_false()
	assert_bool(_service.call(&"play_ui", _stream, &"click")).is_false()
	_service.call(&"clear_mute_reason", &"ad")
	assert_bool(_service.call(&"play_ui", _stream, &"click")).is_true()


func test_nothing_plays_on_a_bus_at_step_zero() -> void:
	_service.call(&"set_sound_step", 0)
	assert_bool(_service.call(&"play_world", _stream, Vector2.ZERO, &"shot")).is_false()
	assert_bool(_service.call(&"play_ui", _stream, &"click")).is_false()


func test_world_pool_caps_at_its_capacity() -> void:
	var pool: VoicePool = _service.pool
	assert_int(pool.world_capacity()).is_equal(_settings.world_voices)
	assert_int(pool.ui_capacity()).is_equal(_settings.ui_voices)
	for i: int in pool.world_capacity() + 5:
		pool.play_world(_stream, Vector2(i, 0), &"shot")
	assert_int(pool.active_world()).is_equal(pool.world_capacity())
	assert_bool(pool.play_world(_stream, Vector2.ZERO, &"shot")).is_false()


func test_higher_priority_steals_the_oldest_lower_one() -> void:
	var pool: VoicePool = _service.pool
	for i: int in pool.world_capacity():
		pool.play_world(_stream, Vector2.ZERO, &"shot", 1)
	assert_bool(pool.play_world(_stream, Vector2.ZERO, &"boom", 1)).is_false()
	assert_bool(pool.play_world(_stream, Vector2.ZERO, &"boom", 5)).is_true()
	assert_int(pool.active_world()).is_equal(pool.world_capacity())
	assert_int(pool.active_of(&"boom")).is_equal(1)
	assert_int(pool.active_of(&"shot")).is_equal(pool.world_capacity() - 1)


func test_cue_max_voices_replaces_its_own_oldest() -> void:
	var pool: VoicePool = _service.pool
	for i: int in 3:
		assert_bool(pool.play_world(_stream, Vector2.ZERO, &"shot", 1, 2)).is_true()
	assert_int(pool.active_of(&"shot")).is_equal(2)
	# A lower priority new sound cannot replace its higher-priority peer.
	pool.play_world(_stream, Vector2.ZERO, &"hum", 9, 1)
	assert_bool(pool.play_world(_stream, Vector2.ZERO, &"hum", 1, 1)).is_false()


func test_voices_per_tick_budget() -> void:
	var pool: VoicePool = _service.pool
	pool.begin_tick()
	var started: int = 0
	for i: int in _settings.voices_per_tick + 4:
		if pool.play_world(_stream, Vector2.ZERO, &"shot", 0):
			started += 1
	assert_int(started).is_equal(_settings.voices_per_tick)
	pool.begin_tick()
	assert_bool(pool.play_world(_stream, Vector2.ZERO, &"shot", 0)).is_true()


func test_ui_pool_caps_and_steals() -> void:
	var pool: VoicePool = _service.pool
	for i: int in pool.ui_capacity():
		assert_bool(pool.play_ui(_stream, &"click", 1)).is_true()
	assert_bool(pool.play_ui(_stream, &"click", 1)).is_false()
	assert_bool(pool.play_ui(_stream, &"alert", 3)).is_true()
	assert_int(pool.active_ui()).is_equal(pool.ui_capacity())


func test_pool_makes_no_player_while_playing() -> void:
	var pool: VoicePool = _service.pool
	var children: int = pool.get_child_count()
	for i: int in 100:
		pool.play_world(_stream, Vector2(i, i), &"shot", i % 3)
		pool.play_ui(_stream, &"click", i % 3)
	assert_int(pool.get_child_count()).is_equal(children)
