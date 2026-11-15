extends GdUnitTestSuite
## The sound synthesiser (plan row P507, ADR 0041 section 7): same parameters give the same bytes,
## the WAV header says mono 16-bit at the file's rate, and the envelope and the mix stay in bounds.

const RATE: int = 22050
const OUT: String = "user://test_sfxgen_%s.wav"
const FIXTURE: String = "res://tests/tools/fixtures/sfx_fixture.tres"
const CLI_OUT: String = "user://test_sfxgen_cli"
const BAD: String = "user://test_sfxgen_bad.tres"


func after_test() -> void:
	for path: String in [OUT % "header", BAD]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_remove_tree(CLI_OUT)


func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub: String in DirAccess.get_directories_at(dir):
		_remove_tree(dir + "/" + sub)
	for f: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)


## Runs gen_sfx.gd in a child Godot; returns [exit code, its output].
func _cli(args: Array[String]) -> Array:
	var full: PackedStringArray = [
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--script",
		"res://tools/sfxgen/gen_sfx.gd",
		"--"
	]
	full.append_array(args)
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), full, output, true)
	return [code, "".join(output)]


func _layer(wave: SfxLayer.Wave, freq: float, length: float) -> SfxLayer:
	var layer: SfxLayer = SfxLayer.new()
	layer.wave = wave
	layer.freq = freq
	layer.freq_end = freq
	layer.length = length
	return layer


func _params(seed_value: int = 7) -> SfxParams:
	var params: SfxParams = SfxParams.new()
	params.id = &"fixture"
	params.sample_rate = RATE
	params.duration = 0.25
	params.seed_value = seed_value
	var noise: SfxLayer = _layer(SfxLayer.Wave.NOISE, 440.0, 0.1)
	noise.lowpass = 3000.0
	noise.highpass = 200.0
	var chirp: SfxLayer = _layer(SfxLayer.Wave.SQUARE, 600.0, 0.2)
	chirp.freq_end = 1200.0
	chirp.start = 0.02
	params.layers = [noise, chirp, _layer(SfxLayer.Wave.SAW, 220.0, 0.2)]
	return params


func test_same_parameters_give_byte_identical_files() -> void:
	var a: PackedByteArray = SfxSynth.wav_bytes(_params())
	var b: PackedByteArray = SfxSynth.wav_bytes(_params())
	assert_int(a.size()).is_greater(44)
	assert_bool(a == b).is_true()


func test_noise_seed_changes_the_bytes() -> void:
	assert_bool(SfxSynth.wav_bytes(_params(7)) == SfxSynth.wav_bytes(_params(8))).is_false()


func test_wav_header_is_mono_16_bit_at_the_rate() -> void:
	var path: String = OUT % "header"
	var bytes_out: PackedByteArray = SfxSynth.wav_bytes(_params())
	assert_int(SfxSynth.write_bytes(bytes_out, path)).is_equal(OK)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	assert_str(bytes.slice(0, 4).get_string_from_ascii()).is_equal("RIFF")
	assert_str(bytes.slice(8, 12).get_string_from_ascii()).is_equal("WAVE")
	assert_int(bytes.decode_u16(20)).is_equal(1)  # PCM
	assert_int(bytes.decode_u16(22)).is_equal(1)  # mono
	assert_int(bytes.decode_u32(24)).is_equal(RATE)
	assert_int(bytes.decode_u16(34)).is_equal(16)
	var frames: int = int(round(0.25 * RATE))
	assert_int(bytes.decode_u32(40)).is_equal(frames * 2)
	var loaded: AudioStreamWAV = AudioStreamWAV.load_from_file(path)
	assert_int(loaded.mix_rate).is_equal(RATE)
	assert_bool(loaded.stereo).is_false()


func test_the_limiter_clamps_an_overflowing_mix() -> void:
	var params: SfxParams = SfxParams.new()
	params.id = &"loud"
	params.sample_rate = RATE
	params.duration = 0.1
	params.gain = 1.0
	for i: int in 2:
		var layer: SfxLayer = _layer(SfxLayer.Wave.SQUARE, 200.0, 0.1)
		layer.amp = 1.0
		layer.attack = 0.0
		layer.decay = 0.0
		layer.sustain = 1.0
		layer.release = 0.0
		params.layers.append(layer)
	var samples: PackedFloat32Array = SfxSynth.render(params)
	# Two in-phase full-scale squares sum to 2.0 before the limiter.
	var low: float = 0.0
	var high: float = 0.0
	for x: float in samples:
		low = minf(low, x)
		high = maxf(high, x)
	assert_float(high).is_equal(1.0)
	assert_float(low).is_equal(-1.0)


func test_a_release_longer_than_the_voice_still_ends_at_zero() -> void:
	var layer: SfxLayer = _layer(SfxLayer.Wave.SINE, 440.0, 0.1)
	layer.attack = 0.0
	layer.decay = 0.0
	layer.sustain = 1.0
	layer.release = 0.5
	assert_float(layer.envelope(0.0)).is_equal_approx(1.0, 0.001)
	assert_float(layer.envelope(0.05)).is_equal_approx(0.5, 0.001)
	assert_float(layer.envelope(0.0999)).is_less(0.01)
	assert_float(layer.envelope(0.1)).is_equal(0.0)


func test_problems_names_every_bad_parameter() -> void:
	assert_array(SfxSynth.problems(_params())).is_empty()
	var params: SfxParams = _params()
	params.id = &"../evil"
	params.family = &"A b"
	params.sample_rate = 12000
	params.duration = -1.0
	params.layers[0].freq = 0.0
	params.layers[1].freq_end = 20000.0
	params.layers.append(null)
	assert_int(SfxSynth.problems(params).size()).is_equal(7)


func test_the_fixture_loads_with_its_typed_layers_and_renders() -> void:
	var params: SfxParams = load(FIXTURE) as SfxParams
	assert_object(params).is_not_null()
	assert_int(params.layers.size()).is_equal(2)
	assert_array(SfxSynth.problems(params)).is_empty()
	assert_int(SfxSynth.wav_bytes(params).size()).is_equal(44 + int(round(0.2 * 22050)) * 2)


func test_cli_writes_once_then_nothing_and_check_follows() -> void:
	var first: Array = _cli(["--params", FIXTURE, "--out", CLI_OUT, "--check"])
	assert_int(first[0]).is_equal(4)
	assert_bool(FileAccess.file_exists(CLI_OUT + "/test/fixture_chirp.wav")).is_false()
	var run: Array = _cli(["--params", FIXTURE, "--out", CLI_OUT])
	assert_int(run[0]).is_equal(0)
	assert_str(run[1]).contains("gen-sfx: wrote")
	var again: Array = _cli(["--params", FIXTURE, "--out", CLI_OUT])
	assert_int(again[0]).is_equal(0)
	assert_str(again[1]).not_contains("gen-sfx: wrote")
	assert_int(_cli(["--params", FIXTURE, "--out", CLI_OUT, "--check"])[0]).is_equal(0)
	var expected: PackedByteArray = SfxSynth.wav_bytes(load(FIXTURE) as SfxParams)
	var written: PackedByteArray = FileAccess.get_file_as_bytes(CLI_OUT + "/test/fixture_chirp.wav")
	assert_bool(written == expected).is_true()


func test_cli_exit_2_for_a_missing_file_or_a_wrong_argument() -> void:
	assert_int(_cli(["--params", "res://tests/tools/fixtures/none.tres"])[0]).is_equal(2)
	assert_int(_cli(["--bogus"])[0]).is_equal(2)


func test_cli_exit_1_for_an_invalid_parameter_file() -> void:
	var params: SfxParams = load(FIXTURE).duplicate() as SfxParams
	params.layers[0].freq = 0.0
	assert_int(ResourceSaver.save(params, BAD)).is_equal(OK)
	var result: Array = _cli(["--params", BAD, "--out", CLI_OUT])
	assert_int(result[0]).is_equal(1)
	assert_str(result[1]).contains("freq")


func test_envelope_bounds_and_shape() -> void:
	var layer: SfxLayer = _layer(SfxLayer.Wave.SINE, 440.0, 0.2)
	layer.attack = 0.02
	layer.decay = 0.04
	layer.sustain = 0.5
	layer.release = 0.05
	assert_float(layer.envelope(-0.01)).is_equal(0.0)
	assert_float(layer.envelope(0.0)).is_equal(0.0)
	assert_float(layer.envelope(0.02)).is_equal_approx(1.0, 0.001)
	assert_float(layer.envelope(0.1)).is_equal_approx(0.5, 0.001)
	assert_float(layer.envelope(0.2)).is_equal(0.0)
	assert_float(layer.envelope(0.175)).is_equal_approx(0.25, 0.001)
	for i: int in 400:
		var v: float = layer.envelope(float(i) * 0.001)
		assert_bool(v >= 0.0 and v <= 1.0).is_true()


func test_sine_has_the_asked_frequency() -> void:
	var params: SfxParams = SfxParams.new()
	params.id = &"tone"
	params.sample_rate = RATE
	params.duration = 1.0
	params.gain = 1.0
	var tone: SfxLayer = _layer(SfxLayer.Wave.SINE, 441.0, 1.0)
	tone.attack = 0.0
	tone.decay = 0.0
	tone.sustain = 1.0
	tone.release = 0.0
	tone.amp = 1.0
	params.layers = [tone]
	var samples: PackedFloat32Array = SfxSynth.render(params)
	var crossings: int = 0
	for i: int in range(1, samples.size()):
		if samples[i - 1] < 0.0 and samples[i] >= 0.0:
			crossings += 1
	assert_int(crossings).is_between(440, 442)
