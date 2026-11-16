extends GdUnitTestSuite
## MusicDeck mid-fade behaviour (ADR 0041 section 5): requests during a crossfade, a sting or a duck
## during one, mute mid-fade, stop and repeat of a sting. Same generated streams and hand-stepped
## tweens as test_music_deck.gd.

const SERVICE_SCRIPT: String = "res://game/view/audio/audio_service.gd"
const SETTINGS_PATH: String = "res://data/audio_settings.tres"

var _service: Node
var _settings: AudioSettings
var _deck: MusicDeck


func _stream(loop: bool) -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 8000
	var data: PackedByteArray = PackedByteArray()
	data.resize(8000)
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = 8000
	return wav


func before_test() -> void:
	_settings = (load(SETTINGS_PATH) as AudioSettings).duplicate()
	_settings.fade_ms = 0
	_settings.music_tracks = {
		&"menu": _stream(true),
		&"battle": _stream(true),
		&"credits": _stream(true),
		&"victory": _stream(false),
		&"defeat": _stream(false),
	}
	_service = (load(SERVICE_SCRIPT) as GDScript).new()
	_service.set("settings", _settings)
	_service.set("ad_service_name", &"NoAdsForMusicTests")
	add_child(_service)
	_deck = _service.call(&"get_music_for_tests")


func after_test() -> void:
	_service.call(&"clear_mute_reason", &"ad")
	_service.call(&"clear_mute_reason", &"background")
	_service.free()


func _finish_fade() -> void:
	_deck.fade_tween_for_tests().custom_step(10.0)


func _players_playing() -> int:
	var n: int = 0
	for i: int in 2:
		if _deck.player_for_tests(i).playing:
			n += 1
	return n


func _step_fade(seconds: float) -> void:
	_deck.fade_tween_for_tests().custom_step(seconds)


func test_third_request_mid_fade_cuts_only_the_quiet_player() -> void:
	_service.call(&"play_music", &"menu")
	_finish_fade()
	_service.call(&"play_music", &"battle")
	_step_fade(0.2)
	var menu_before: float = _deck.level_for_tests(0)
	assert_bool(_service.call(&"play_music", &"credits")).is_true()
	# The battle track was the quiet one and is replaced; the menu loop goes on from where it was.
	assert_float(_deck.level_for_tests(0)).is_equal_approx(menu_before, 0.01)
	assert_object(_deck.player_for_tests(0).stream).is_same(_settings.music_tracks[&"menu"])
	assert_bool(_deck.player_for_tests(0).playing).is_true()
	assert_object(_deck.player_for_tests(1).stream).is_same(_settings.music_tracks[&"credits"])
	_step_fade(0.1)
	assert_float(_deck.level_for_tests(0)).is_less(menu_before)
	_finish_fade()
	assert_int(_players_playing()).is_equal(1)
	assert_bool(_deck.player_for_tests(1).playing).is_true()


func test_outgoing_level_never_rises_across_switches() -> void:
	_service.call(&"play_music", &"menu")
	_finish_fade()
	_service.call(&"play_music", &"battle")
	_step_fade(0.5)
	var outgoing: float = _deck.level_for_tests(0)
	_service.call(&"play_music", &"credits")
	assert_float(_deck.level_for_tests(0)).is_less_equal(outgoing + 0.01)
	var last: float = _deck.level_for_tests(0)
	for i: int in 5:
		_step_fade(0.1)
		assert_float(_deck.level_for_tests(0)).is_less_equal(last + 0.001)
		last = _deck.level_for_tests(0)


func test_request_for_the_fading_out_track_reverses_the_fade() -> void:
	_service.call(&"play_music", &"menu")
	_finish_fade()
	_service.call(&"play_music", &"battle")
	_step_fade(0.5)
	var menu_level: float = _deck.level_for_tests(0)
	var stream: AudioStream = _deck.player_for_tests(0).stream
	assert_bool(_service.call(&"play_music", &"menu")).is_true()
	assert_str(String(_deck.current())).is_equal("menu")
	assert_float(_deck.level_for_tests(0)).is_equal_approx(menu_level, 0.01)
	assert_object(_deck.player_for_tests(0).stream).is_same(stream)
	_finish_fade()
	assert_float(_deck.level_for_tests(0)).is_equal_approx(0.0, 0.01)
	assert_bool(_deck.player_for_tests(1).playing).is_false()
	assert_bool(_deck.player_for_tests(0).playing).is_true()


func test_sting_during_a_crossfade_ends_with_the_sting_alone() -> void:
	_service.call(&"play_music", &"menu")
	_finish_fade()
	_service.call(&"play_music", &"battle")
	_step_fade(0.3)
	assert_bool(_service.call(&"play_music", &"victory")).is_true()
	var sting_player: int = 0
	for i: int in 2:
		if _deck.player_for_tests(i).stream == _settings.music_tracks[&"victory"]:
			sting_player = i
	assert_float(_deck.level_for_tests(sting_player)).is_equal(0.0)
	_finish_fade()
	assert_int(_players_playing()).is_equal(1)
	assert_bool(_deck.player_for_tests(sting_player).playing).is_true()


func test_duck_during_a_crossfade_lowers_both_and_restores() -> void:
	_service.call(&"play_music", &"menu")
	_finish_fade()
	_service.call(&"play_music", &"battle")
	_step_fade(0.5)
	var level: float = _deck.level_for_tests(1)
	_service.call(&"duck_music")
	assert_float(_deck.player_for_tests(1).volume_db).is_equal_approx(
		level - _settings.duck_db, 0.01
	)
	_step_fade(10.0)
	_deck.duck_tween_for_tests().custom_step(10.0)
	assert_float(_deck.player_for_tests(1).volume_db).is_equal_approx(0.0, 0.01)


func test_mute_mid_fade_pauses_the_fade_and_resumes_it() -> void:
	_service.call(&"play_music", &"menu")
	_finish_fade()
	_service.call(&"play_music", &"battle")
	_service.call(&"add_mute_reason", &"background")
	assert_bool(_deck.fade_tween_for_tests().is_running()).is_false()
	assert_bool(_deck.player_for_tests(1).stream_paused).is_true()
	_service.call(&"clear_mute_reason", &"background")
	assert_bool(_deck.fade_tween_for_tests().is_running()).is_true()
	_finish_fade()
	assert_float(_deck.level_for_tests(1)).is_equal_approx(0.0, 0.01)


func test_master_fade_reasons_pause_the_streams_after_the_fade() -> void:
	_settings.fade_ms = 60
	_service.call(&"play_music", &"battle")
	_finish_fade()
	_service.call(&"add_mute_reason", &"ad")
	assert_bool(_deck.player_for_tests(0).stream_paused).is_false()
	await await_millis(400)
	assert_bool(_deck.player_for_tests(0).stream_paused).is_true()
	_service.call(&"clear_mute_reason", &"ad")
	assert_bool(_deck.player_for_tests(0).stream_paused).is_false()


func test_unmute_inside_the_fade_never_pauses() -> void:
	_settings.fade_ms = 60
	_service.call(&"play_music", &"battle")
	_finish_fade()
	_service.call(&"add_mute_reason", &"ad")
	_service.call(&"clear_mute_reason", &"ad")
	await await_millis(300)
	assert_bool(_deck.player_for_tests(0).stream_paused).is_false()


func test_stop_during_a_sting_emits_sting_finished() -> void:
	_service.call(&"play_music", &"victory")
	var heard: Array[StringName] = []
	_deck.sting_finished.connect(heard.append)
	_service.call(&"stop_music")
	assert_array(heard).contains_exactly([&"victory"])
	_service.call(&"stop_music")
	assert_array(heard).has_size(1)


func test_stop_ends_the_duck() -> void:
	_service.call(&"play_music", &"battle")
	_service.call(&"duck_music")
	_service.call(&"stop_music")
	assert_float(_deck.duck_db_now()).is_equal(0.0)


func test_same_sting_plays_again_after_it_finished() -> void:
	_service.call(&"play_music", &"defeat")
	assert_bool(_service.call(&"play_music", &"defeat")).is_false()
	_deck.player_for_tests(0).finished.emit()
	assert_bool(_service.call(&"play_music", &"defeat")).is_true()
