class_name SfxSynth
extends RefCounted
## The synthesiser (plan row P507, ADR 0041 section 7): mixes the layers of an `SfxParams` into
## 16-bit mono samples and wraps them as an `AudioStreamWAV`. Deterministic: no randi/randf, the
## noise comes from a local xorshift32 seeded by the parameter file.


## The mixed samples in [-1, 1], one float per frame.
static func render(params: SfxParams) -> PackedFloat32Array:
	var rate: float = float(params.sample_rate)
	var count: int = int(round(params.duration * rate))
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var voice: int = 0
	for layer: SfxLayer in params.layers:
		var rng: int = _seed_state(params.seed_value, voice)
		voice += 1
		var phase: float = 0.0
		var lp: float = 0.0
		var hp_in: float = 0.0
		var hp_out: float = 0.0
		var lp_k: float = _coef(layer.lowpass, rate)
		var hp_k: float = _coef(layer.highpass, rate)
		var first: int = int(round(layer.start * rate))
		var last: int = mini(first + int(round(layer.length * rate)), count)
		for i: int in range(maxi(first, 0), last):
			var t: float = float(i - first) / rate
			var x: float
			if layer.wave == SfxLayer.Wave.NOISE:
				rng = _next(rng)
				x = float(rng & 0xFFFF) / 32767.5 - 1.0
			else:
				var f: float = layer.freq * pow(layer.freq_end / layer.freq, t / layer.length)
				phase = fposmod(phase + f / rate, 1.0)
				x = _osc(layer.wave, phase, layer.duty)
			if lp_k > 0.0:
				lp += lp_k * (x - lp)
				x = lp
			if hp_k > 0.0:
				hp_out = (1.0 - hp_k) * (hp_out + x - hp_in)
				hp_in = x
				x = hp_out
			out[i] += x * layer.amp * layer.envelope(t)
	for i: int in count:
		out[i] = clampf(out[i] * params.gain, -1.0, 1.0)
	return out


## The WAV stream: 16-bit little-endian mono PCM.
static func to_stream(params: SfxParams) -> AudioStreamWAV:
	var samples: PackedFloat32Array = render(params)
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in samples.size():
		data.encode_s16(i * 2, int(round(samples[i] * 32767.0)))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.mix_rate = params.sample_rate
	stream.data = data
	return stream


## The bytes of the WAV file `write` would produce (through a temporary file: Godot has no
## in-memory WAV encoder).
static func file_bytes(params: SfxParams) -> PackedByteArray:
	var tmp: String = "user://sfxgen_tmp.wav"
	to_stream(params).save_to_wav(tmp)
	return FileAccess.get_file_as_bytes(tmp)


## Writes the sound to `path` (a res:// or absolute path). Returns the Godot error code.
static func write(params: SfxParams, path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return to_stream(params).save_to_wav(path)


static func _osc(wave: SfxLayer.Wave, phase: float, duty: float) -> float:
	match wave:
		SfxLayer.Wave.SQUARE:
			return 1.0 if phase < duty else -1.0
		SfxLayer.Wave.SAW:
			return phase * 2.0 - 1.0
		SfxLayer.Wave.TRIANGLE:
			return 4.0 * absf(phase - 0.5) - 1.0
	return sin(phase * TAU)


## One-pole coefficient for a cut-off in Hz; 0 when the filter is off.
static func _coef(cutoff: float, rate: float) -> float:
	if cutoff <= 0.0:
		return 0.0
	return clampf(1.0 - exp(-TAU * cutoff / rate), 0.0, 1.0)


static func _seed_state(seed_value: int, voice: int) -> int:
	var s: int = (seed_value * 2654435761 + voice * 40503 + 1) & 0xFFFFFFFF
	return s if s != 0 else 1


## xorshift32.
static func _next(s: int) -> int:
	s = (s ^ (s << 13)) & 0xFFFFFFFF
	s = s ^ (s >> 17)
	s = (s ^ (s << 5)) & 0xFFFFFFFF
	return s
