extends GdUnitTestSuite
## The sound synthesiser (plan row P507, ADR 0041 section 7): same parameters give the same bytes,
## the WAV header says mono 16-bit at the file's rate, and the envelope and the mix stay in bounds.

const RATE: int = 22050
const OUT: String = "user://test_sfxgen_%s.wav"


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
	var a: PackedByteArray = SfxSynth.file_bytes(_params())
	var b: PackedByteArray = SfxSynth.file_bytes(_params())
	assert_int(a.size()).is_greater(44)
	assert_bool(a == b).is_true()


func test_noise_seed_changes_the_bytes() -> void:
	assert_bool(SfxSynth.file_bytes(_params(7)) == SfxSynth.file_bytes(_params(8))).is_false()


func test_wav_header_is_mono_16_bit_at_the_rate() -> void:
	var path: String = OUT % "header"
	assert_int(SfxSynth.write(_params(), path)).is_equal(OK)
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


func test_mix_is_limited_and_silent_after_the_voices() -> void:
	var params: SfxParams = _params()
	params.gain = 1.0
	for layer: SfxLayer in params.layers:
		layer.amp = 1.0
		layer.sustain = 1.0
	params.duration = 0.4
	var samples: PackedFloat32Array = SfxSynth.render(params)
	var peak: float = 0.0
	for s: float in samples:
		peak = maxf(peak, absf(s))
	assert_float(peak).is_less_equal(1.0)
	assert_float(peak).is_greater(0.5)
	assert_float(samples[samples.size() - 1]).is_equal(0.0)


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
