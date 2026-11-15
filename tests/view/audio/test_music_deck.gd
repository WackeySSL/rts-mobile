extends GdUnitTestSuite
## MusicDeck through AudioService (ADR 0041 section 5): the crossfade and its end state, the sting,
## the duck and its restore, silence while muted, and the same track twice. The tracks are generated
## streams (the music files come with P506); the tweens are stepped by hand, no frames needed.

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


func test_players_sit_on_the_music_bus() -> void:
	for i: int in 2:
		assert_str(String(_deck.player_for_tests(i).bus)).is_equal("Music")


func test_unknown_id_is_refused() -> void:
	assert_bool(_service.call(&"play_music", &"nope")).is_false()
	assert_int(_players_playing()).is_equal(0)


func test_first_track_starts_and_crossfade_ends_with_one_player() -> void:
	assert_bool(_service.call(&"play_music", &"menu")).is_true()
	_finish_fade()
	assert_int(_players_playing()).is_equal(1)
	assert_float(_deck.player_for_tests(0).volume_db).is_equal_approx(0.0, 0.01)
	assert_bool(_service.call(&"play_music", &"battle")).is_true()
	assert_int(_players_playing()).is_equal(2)
	_finish_fade()
	assert_int(_players_playing()).is_equal(1)
	assert_bool(_deck.player_for_tests(1).playing).is_true()
	assert_object(_deck.player_for_tests(1).stream).is_same(_settings.music_tracks[&"battle"])
	assert_float(_deck.player_for_tests(1).volume_db).is_equal_approx(0.0, 0.01)
	assert_bool(_deck.player_for_tests(0).playing).is_false()


func test_crossfade_is_halfway_at_half_the_time() -> void:
	_service.call(&"play_music", &"menu")
	_finish_fade()
	_service.call(&"play_music", &"battle")
	_deck.fade_tween_for_tests().custom_step(_settings.crossfade_ms / 2000.0)
	var half: float = linear_to_db(0.5)
	assert_float(_deck.player_for_tests(1).volume_db).is_equal_approx(half, 0.5)
	assert_float(_deck.player_for_tests(0).volume_db).is_equal_approx(half, 0.5)


func test_same_track_twice_is_a_no_op() -> void:
	assert_bool(_service.call(&"play_music", &"battle")).is_true()
	var tween: Tween = _deck.fade_tween_for_tests()
	assert_bool(_service.call(&"play_music", &"battle")).is_false()
	assert_object(_deck.fade_tween_for_tests()).is_same(tween)
	_finish_fade()
	assert_bool(_service.call(&"play_music", &"battle")).is_false()
	assert_int(_players_playing()).is_equal(1)


func test_sting_plays_at_full_level_over_the_fading_loop() -> void:
	_service.call(&"play_music", &"battle")
	_finish_fade()
	assert_bool(_service.call(&"play_music", &"victory")).is_true()
	var sting: AudioStreamPlayer = _deck.player_for_tests(1)
	var loop: AudioStreamPlayer = _deck.player_for_tests(0)
	assert_object(sting.stream).is_same(_settings.music_tracks[&"victory"])
	assert_float(sting.volume_db).is_equal(0.0)
	assert_bool(loop.playing).is_true()
	_deck.fade_tween_for_tests().custom_step(_settings.crossfade_ms / 2000.0)
	assert_float(loop.volume_db).is_less(-20.0)
	assert_float(sting.volume_db).is_equal(0.0)
	_finish_fade()
	assert_bool(loop.playing).is_false()
	assert_bool(sting.playing).is_true()


func test_sting_end_is_announced() -> void:
	_service.call(&"play_music", &"defeat")
	var heard: Array[StringName] = []
	_deck.sting_finished.connect(heard.append)
	_deck.player_for_tests(0).finished.emit()
	assert_array(heard).contains_exactly([&"defeat"])


func test_duck_lowers_then_restores() -> void:
	_service.call(&"play_music", &"battle")
	_finish_fade()
	_service.call(&"duck_music")
	assert_float(_deck.player_for_tests(0).volume_db).is_equal_approx(-_settings.duck_db, 0.01)
	_deck.duck_tween_for_tests().custom_step(_settings.duck_ms / 1000.0 + 1.0)
	assert_float(_deck.player_for_tests(0).volume_db).is_equal_approx(0.0, 0.01)
	assert_float(_deck.duck_db_now()).is_equal(0.0)


func test_second_duck_restarts_the_hold() -> void:
	_service.call(&"play_music", &"battle")
	_finish_fade()
	_service.call(&"duck_music")
	_deck.duck_tween_for_tests().custom_step(_settings.duck_ms / 2000.0)
	_service.call(&"duck_music")
	_deck.duck_tween_for_tests().custom_step(_settings.duck_ms / 2000.0)
	assert_float(_deck.duck_db_now()).is_equal(-_settings.duck_db)


func test_duck_leaves_the_music_bus_to_the_step() -> void:
	var bus: int = AudioServer.get_bus_index(&"Music")
	var before: float = AudioServer.get_bus_volume_db(bus)
	_service.call(&"play_music", &"battle")
	_service.call(&"duck_music")
	assert_float(AudioServer.get_bus_volume_db(bus)).is_equal(before)


func test_nothing_plays_while_muted_and_starts_when_the_sound_returns() -> void:
	_service.call(&"add_mute_reason", &"ad")
	assert_bool(_service.call(&"play_music", &"menu")).is_true()
	assert_int(_players_playing()).is_equal(0)
	assert_bool(_service.call(&"play_music", &"menu")).is_false()
	_service.call(&"clear_mute_reason", &"ad")
	assert_int(_players_playing()).is_equal(1)
	assert_object(_deck.player_for_tests(0).stream).is_same(_settings.music_tracks[&"menu"])


func test_mute_pauses_the_stream_and_unmute_resumes_it() -> void:
	_service.call(&"play_music", &"battle")
	_finish_fade()
	_service.call(&"add_mute_reason", &"background")
	assert_bool(_deck.player_for_tests(0).stream_paused).is_true()
	_service.call(&"clear_mute_reason", &"background")
	assert_bool(_deck.player_for_tests(0).stream_paused).is_false()
	assert_bool(_deck.player_for_tests(0).playing).is_true()


func test_stop_silences_both_players() -> void:
	_service.call(&"play_music", &"battle")
	_service.call(&"stop_music")
	assert_int(_players_playing()).is_equal(0)
	assert_bool(_service.call(&"play_music", &"battle")).is_true()
