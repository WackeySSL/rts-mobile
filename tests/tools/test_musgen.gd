extends GdUnitTestSuite
## The music synthesiser (plan row P506, ADR 0041 section 5): the same parameters give the same
## samples, a loop wraps its tails into its first bar without a click, pads are wide and drums and
## bass are centred, and the command line exits 4 when the encoder is missing.

const RATE: int = 8000
const BAD_FFMPEG: String = "/nonexistent/musgen-ffmpeg"
const PARAMS_FILE: String = "user://test_musgen_params.tres"
const CLI_OUT: String = "user://test_musgen_cli"


func after_test() -> void:
	for path: String in [PARAMS_FILE, CLI_OUT + "/fixture.ogg"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(CLI_OUT):
		DirAccess.remove_absolute(CLI_OUT)


func _voice(wave: SfxLayer.Wave, attack: float, release: float, lowpass: float = 0.0) -> SfxLayer:
	var layer: SfxLayer = SfxLayer.new()
	layer.wave = wave
	layer.attack = attack
	layer.decay = 0.05
	layer.sustain = 0.8
	layer.release = release
	layer.lowpass = lowpass
	return layer


func _lane(kind: MusicLane.Kind, voice: SfxLayer, patterns: Array, extra: Dictionary) -> MusicLane:
	var lane: MusicLane = MusicLane.new()
	lane.kind = kind
	lane.voice = voice
	lane.patterns = PackedStringArray(patterns)
	for key: String in extra:
		lane.set(key, extra[key])
	return lane


## A two-bar loop at 120 BPM: a detuned pad, a bass in the last bar only (its release runs past the
## end), a kick.
func _params(seed_value: int = 3, loop: bool = true) -> MusicParams:
	var params: MusicParams = MusicParams.new()
	params.id = &"fixture"
	params.bpm = 120.0
	params.bars = 2
	params.loop = loop
	params.tail = 0.5
	params.sample_rate = RATE
	params.seed_value = seed_value
	params.chord_bars = 1
	params.chords = [PackedInt32Array([57, 60, 64]), PackedInt32Array([55, 59, 62])]
	params.roots = PackedInt32Array([45, 43])
	var pad: MusicLane = _lane(
		MusicLane.Kind.PAD,
		_voice(SfxLayer.Wave.SAW, 0.3, 0.4, 900.0),
		[],
		{"detune_cents": 9.0, "pan": 0.8, "level": 0.5, "send": 0.3}
	)
	var bass: MusicLane = _lane(
		MusicLane.Kind.BASS,
		_voice(SfxLayer.Wave.SINE, 0.01, 0.6),
		["x..............."],
		{"mask": "01", "level": 0.8}
	)
	var kick_voice: SfxLayer = _voice(SfxLayer.Wave.SINE, 0.002, 0.05)
	kick_voice.freq = 100.0
	kick_voice.freq_end = 45.0
	kick_voice.length = 0.2
	var kick: MusicLane = _lane(MusicLane.Kind.DRUM, kick_voice, ["x...x...x...x..."], {})
	params.lanes = [pad, bass, kick]
	return params


func test_same_parameters_give_the_same_samples() -> void:
	var a: Array[PackedFloat32Array] = MusicSynth.render(_params())
	var b: Array[PackedFloat32Array] = MusicSynth.render(_params())
	assert_int(a[0].size()).is_equal(RATE * 4)
	assert_bool(a[0] == b[0] and a[1] == b[1]).is_true()


func test_the_seed_changes_the_samples() -> void:
	var noise: SfxLayer = _voice(SfxLayer.Wave.NOISE, 0.001, 0.02)
	noise.length = 0.1
	var params_a: MusicParams = _params(1)
	var params_b: MusicParams = _params(2)
	for params: MusicParams in [params_a, params_b]:
		params.lanes.append(_lane(MusicLane.Kind.DRUM, noise, ["x..............."], {}))
	assert_bool(MusicSynth.render(params_a)[0] == MusicSynth.render(params_b)[0]).is_false()


func test_the_peak_is_where_the_file_says() -> void:
	var params: MusicParams = _params()
	params.peak_db = -8.0
	var sides: Array[PackedFloat32Array] = MusicSynth.render(params)
	var peak: float = 0.0
	for side: PackedFloat32Array in sides:
		for value: float in side:
			peak = maxf(peak, absf(value))
	assert_float(linear_to_db(peak)).is_equal_approx(-8.0, 0.01)


func test_the_pad_is_wide_and_the_drums_and_bass_are_centred() -> void:
	var params: MusicParams = _params()
	var wide: Array[PackedFloat32Array] = MusicSynth.render(params)
	assert_bool(wide[0] == wide[1]).is_false()
	params.lanes.remove_at(0)
	var centred: Array[PackedFloat32Array] = MusicSynth.render(params)
	assert_bool(centred[0] == centred[1]).is_true()


func test_a_loop_has_no_click_at_its_seam_and_its_tail_wraps_to_the_start() -> void:
	var params: MusicParams = _params()
	params.lanes = [params.lanes[1]]  # The bass only: it plays in bar 1, silent in bar 0.
	var sides: Array[PackedFloat32Array] = MusicSynth.render(params)
	var left: PackedFloat32Array = sides[0]
	var ten_ms: int = RATE / 100
	var head: float = 0.0
	var step: float = 0.0
	for i: int in ten_ms:
		head = maxf(head, absf(left[i]))
	for i: int in range(1, left.size()):
		step = maxf(step, absf(left[i] - left[i - 1]))
	assert_float(head).is_greater(0.001)  # The release of bar 1 rings into bar 0.
	assert_float(absf(left[left.size() - 1] - left[0])).is_less(step * 2.0)


func test_a_sting_ends_in_silence_after_its_tail() -> void:
	var params: MusicParams = _params(3, false)
	var left: PackedFloat32Array = MusicSynth.render(params)[0]
	assert_int(left.size()).is_equal(RATE * 9 / 2)
	assert_float(absf(left[left.size() - 1])).is_less(0.01)


func test_a_missing_encoder_exits_4() -> void:
	assert_int(ResourceSaver.save(_params(), PARAMS_FILE)).is_equal(OK)
	var result: Array = _cli(["--params", PARAMS_FILE, "--out", CLI_OUT, "--ffmpeg", BAD_FFMPEG])
	assert_int(result[0]).is_equal(4)
	assert_str(result[1]).contains("FFMPEG MISSING")
	assert_bool(FileAccess.file_exists(CLI_OUT + "/fixture.ogg")).is_false()


func test_a_wrong_argument_exits_2() -> void:
	assert_int(_cli(["--bogus"])[0]).is_equal(2)


func test_the_encoder_writes_an_ogg() -> void:
	var output: Array = []
	var status: int = OS.execute("ffmpeg", ["-version"], output)
	assert_int(status).override_failure_message("ffmpeg is needed to run this suite").is_equal(0)
	assert_int(ResourceSaver.save(_params(), PARAMS_FILE)).is_equal(OK)
	var result: Array = _cli(["--params", PARAMS_FILE, "--out", CLI_OUT])
	assert_int(result[0]).is_equal(0)
	var head: PackedByteArray = FileAccess.get_file_as_bytes(CLI_OUT + "/fixture.ogg")
	assert_str(head.slice(0, 4).get_string_from_ascii()).is_equal("OggS")


func test_a_shipped_sting_dies_away_before_its_end() -> void:
	for id: String in ["victory", "defeat"]:
		var params: MusicParams = load("res://tools/musgen/params/%s.tres" % id) as MusicParams
		var left: PackedFloat32Array = MusicSynth.render(params)[0]
		var window: int = int(0.3 * float(params.sample_rate))
		var middle: float = _rms(left, left.size() / 2 - window / 2, window)
		var end: float = _rms(left, left.size() - window, window)
		var drop_db: float = linear_to_db(middle) - linear_to_db(end)
		assert_float(drop_db).override_failure_message("%s: %s dB" % [id, drop_db]).is_greater(12.0)


func test_problems_names_an_empty_chord_and_a_drum_without_a_pitch() -> void:
	var params: MusicParams = _params()
	assert_array(params.problems()).is_empty()
	params.chords.append(PackedInt32Array())
	params.lanes[2].voice.freq = 0.0
	assert_int(params.problems().size()).is_equal(2)


func _rms(samples: PackedFloat32Array, from: int, count: int) -> float:
	var sum: float = 0.0
	for i: int in range(from, from + count):
		sum += samples[i] * samples[i]
	return sqrt(sum / float(count))


## Runs gen_music.gd in a child Godot; returns [exit code, its output].
func _cli(args: Array[String]) -> Array:
	var full: PackedStringArray = [
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--script",
		"res://tools/musgen/gen_music.gd",
		"--"
	]
	full.append_array(args)
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), full, output, true)
	return [code, "".join(output)]
