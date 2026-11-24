extends GdUnitTestSuite
## The shipped music (plan row P506, ADR 0041 section 5): the four ids are in `music_tracks`, the
## loops are as long as their bars say and loop, the stings are the sting ids and do not loop.

const SETTINGS: String = "res://data/audio_settings.tres"
const PARAMS: String = "res://tools/musgen/params/%s.tres"
## One Vorbis frame at the 32 kHz the pieces are rendered at.
const FRAME_S: float = 2048.0 / 32000.0
const LOOPS: Array[StringName] = [&"menu", &"battle"]
const STINGS: Array[StringName] = [&"victory", &"defeat"]


func _settings() -> AudioSettings:
	return load(SETTINGS) as AudioSettings


func test_music_tracks_holds_the_four_pieces() -> void:
	var tracks: Dictionary[StringName, AudioStream] = _settings().music_tracks
	for id: StringName in LOOPS + STINGS:
		assert_object(tracks.get(id)).override_failure_message("no track " + id).is_not_null()
	assert_int(tracks.size()).is_equal(4)


func test_each_loop_is_as_long_as_its_bars_and_loops() -> void:
	for id: StringName in LOOPS:
		var params: MusicParams = load(PARAMS % id) as MusicParams
		var stream: AudioStreamOggVorbis = _settings().music_tracks[id] as AudioStreamOggVorbis
		var expected: float = params.bars * 4.0 * 60.0 / params.bpm
		assert_float(stream.get_length()).is_equal_approx(expected, FRAME_S)
		assert_bool(stream.loop).override_failure_message(id + " must loop").is_true()
		assert_float(stream.loop_offset).is_equal(0.0)


func test_the_stings_are_listed_and_do_not_loop() -> void:
	var settings: AudioSettings = _settings()
	for id: StringName in STINGS:
		assert_bool(settings.sting_ids.has(id)).is_true()
		assert_bool((settings.music_tracks[id] as AudioStreamOggVorbis).loop).is_false()
		var length: float = settings.music_tracks[id].get_length()
		assert_float(length).is_between(6.0, 8.5)
	for id: StringName in LOOPS:
		assert_bool(settings.sting_ids.has(id)).is_false()
