class_name MusicSynth
extends RefCounted
## The sequencer and renderer of generated music (plan row P506, ADR 0041 section 5). It plays the
## lanes of a `MusicParams` through the oscillators, envelopes, filters and xorshift noise of
## `SfxSynth`/`SfxLayer` into stereo float samples. Deterministic: no randi/randf.
## A loop writes its notes modulo its length, so a tail that runs past the last bar lands on the
## first bar (the same result as rendering two cycles and keeping the second); the echo runs two
## laps for the same reason. A sting plays once and is cut at its end.

## Envelope control rate: the envelope is read every CONTROL frames and interpolated.
const CONTROL: int = 32
const STEPS: int = 16


## The mixed piece as [left, right], peak at `peak_db`.
static func render(params: MusicParams) -> Array[PackedFloat32Array]:
	var mix: Mix = Mix.new(params)
	for index: int in params.lanes.size():
		_lane(params, params.lanes[index], index, mix)
	_echo(params, mix)
	_finish(params, mix)
	return [mix.left, mix.right]


## The 16-bit stereo WAV stream of the render (what the CLI hands to the encoder).
static func to_stream(params: MusicParams) -> AudioStreamWAV:
	var sides: Array[PackedFloat32Array] = render(params)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sides[0].size() * 4)
	for i: int in sides[0].size():
		data.encode_s16(i * 4, int(round(sides[0][i] * 32767.0)))
		data.encode_s16(i * 4 + 2, int(round(sides[1][i] * 32767.0)))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = true
	stream.mix_rate = params.sample_rate
	stream.data = data
	return stream


static func _lane(params: MusicParams, lane: MusicLane, index: int, mix: Mix) -> void:
	var voice: SfxLayer = lane.voice.duplicate() as SfxLayer
	var bar_s: float = params.bar_seconds()
	var step_s: float = bar_s / float(STEPS)
	var hits: int = 0
	for bar: int in params.bars:
		if bar % params.chord_bars == 0:
			hits = 0
		if not lane.active(bar):
			continue
		var chord: PackedInt32Array = params.chord_at(bar)
		var start: float = bar * bar_s
		if lane.kind == MusicLane.Kind.PAD:
			if bar % params.chord_bars == 0:
				var hold: float = params.chord_bars * bar_s
				if not params.loop and bar + params.chord_bars >= params.bars:
					# The last chord's release ends with the file, not after it.
					hold = maxf(hold + params.tail - voice.release, 0.0)
				_pad(params, lane, voice, chord, start, hold, index * 97 + bar, mix)
			continue
		var pattern: String = lane.pattern_for(bar)
		for step: int in mini(pattern.length(), STEPS):
			var c: String = pattern[step]
			if c == ".":
				continue
			var t0: float = start + step * step_s
			var seed_id: int = index * 997 + bar * 31 + step
			if lane.kind == MusicLane.Kind.DRUM:
				var amp: float = 1.25 if c == "o" else (0.5 if c == "g" else 1.0)
				_voice(
					params,
					voice,
					[t0, voice.length, amp, lane.pan, lane.send, seed_id],
					mix,
					lane.level
				)
				continue
			var run: int = 1
			while (
				step + run < STEPS
				and (step + run >= pattern.length() or pattern[step + run] == ".")
			):
				run += 1
			var midi: int
			if lane.kind == MusicLane.Kind.BASS:
				midi = params.root_at(bar) + (12 if c == "o" else (7 if c == "f" else 0))
			else:
				midi = _arp_note(chord, hits, lane.arp_dir)
				hits += 1
			var f: float = _hz(midi + lane.octave_shift)
			voice.freq = f
			voice.freq_end = f
			voice.length = run * step_s * lane.gate + voice.release
			_voice(
				params,
				voice,
				[t0, voice.length, 1.0, lane.pan, lane.send, seed_id],
				mix,
				lane.level
			)


## Both detuned halves of a pad chord (or one voice when `detune_cents` is 0).
static func _pad(
	params: MusicParams,
	lane: MusicLane,
	voice: SfxLayer,
	chord: PackedInt32Array,
	start: float,
	hold: float,
	seed_id: int,
	mix: Mix
) -> void:
	voice.length = hold + voice.release
	var sides: Array[float] = [0.0]
	if lane.detune_cents > 0.0:
		sides = [-1.0, 1.0]
	for note: int in chord.size():
		for side: float in sides:
			var f: float = (
				_hz(chord[note] + lane.octave_shift) * pow(2.0, side * lane.detune_cents / 1200.0)
			)
			voice.freq = f
			voice.freq_end = f
			var pan: float = side * absf(lane.pan) if side != 0.0 else lane.pan
			_voice(
				params,
				voice,
				[start, voice.length, 1.0, pan, lane.send, seed_id * 7 + note],
				mix,
				lane.level
			)


## Which chord tone the `k`-th hit of an arpeggio plays: two octaves up, down or up and down.
static func _arp_note(chord: PackedInt32Array, k: int, dir: MusicLane.Dir) -> int:
	var n: int = chord.size()
	var span: int = 2 * n
	var p: int = k % span
	if dir == MusicLane.Dir.DOWN:
		p = span - 1 - p
	elif dir == MusicLane.Dir.PING:
		var c: int = k % (2 * span - 2)
		p = c if c < span else 2 * span - 2 - c
	return chord[p % n] + 12 * (p / n)


## One note: `at` = [start s, length s, amplitude, pan, send share, noise seed id]. Pitched voices
## have their `freq`/`length` set by the caller; a drum glides from `freq` to `freq_end`.
static func _voice(
	params: MusicParams, voice: SfxLayer, at: Array, mix: Mix, level: float = 1.0
) -> void:
	var rate: float = float(params.sample_rate)
	var first: int = int(round(float(at[0]) * rate))
	var count: int = int(round(float(at[1]) * rate))
	var pan_angle: float = (float(at[3]) + 1.0) * PI / 4.0
	var gain: float = voice.amp * float(at[2]) * level
	var gl: float = cos(pan_angle) * gain
	var gr: float = sin(pan_angle) * gain
	var send: float = float(at[4])
	var rng: int = SfxSynth.seed_state(params.seed_value, int(at[5]))
	var phase: float = float(rng & 0xFFFF) / 65536.0
	var step: float = pow(voice.freq_end / voice.freq, 1.0 / maxf(float(count), 1.0))
	var f: float = voice.freq
	var lp_k: float = SfxSynth.coef(voice.lowpass, rate)
	var hp_k: float = SfxSynth.coef(voice.highpass, rate)
	var lp1: float = 0.0
	var lp2: float = 0.0
	var hp_in: float = 0.0
	var hp_out: float = 0.0
	var env0: float = voice.envelope(0.0)
	var env1: float = env0
	var noise: bool = voice.wave == SfxLayer.Wave.NOISE
	for i: int in count:
		var idx: int = first + i
		if idx >= mix.n:
			if not params.loop:
				break
			idx %= mix.n
		var c: int = i & (CONTROL - 1)
		if c == 0:
			env0 = env1
			env1 = voice.envelope(float(i + CONTROL) / rate)
		var x: float
		if noise:
			rng = SfxSynth.next_state(rng)
			x = float(rng & 0xFFFF) / 32767.5 - 1.0
		else:
			phase = fposmod(phase + f / rate, 1.0)
			x = SfxSynth.osc(voice.wave, phase, voice.duty)
			f *= step
		if lp_k > 0.0:
			lp1 += lp_k * (x - lp1)
			lp2 += lp_k * (lp1 - lp2)
			x = lp2
		if hp_k > 0.0:
			hp_out = (1.0 - hp_k) * (hp_out + x - hp_in)
			hp_in = x
			x = hp_out
		x *= env0 + (env1 - env0) * float(c) / float(CONTROL)
		mix.left[idx] += x * gl
		mix.right[idx] += x * gr
		if send > 0.0:
			mix.send_left[idx] += x * gl * send
			mix.send_right[idx] += x * gr * send


## The ping-pong echo: the left channel echoes the right send and the other way round.
static func _echo(params: MusicParams, mix: Mix) -> void:
	var delay: int = int(round(params.echo_beats * 60.0 / params.bpm * float(params.sample_rate)))
	if delay <= 0 or params.echo_mix <= 0.0 or delay >= mix.n:
		return
	var wet_l: PackedFloat32Array = PackedFloat32Array()
	var wet_r: PackedFloat32Array = PackedFloat32Array()
	wet_l.resize(mix.n)
	wet_r.resize(mix.n)
	for lap: int in 2 if params.loop else 1:
		for i: int in mix.n:
			var j: int = i - delay
			if j < 0:
				if not params.loop:
					continue
				j += mix.n
			wet_l[i] = mix.send_right[j] + params.echo_feedback * wet_r[j]
			wet_r[i] = mix.send_left[j] + params.echo_feedback * wet_l[j]
	for i: int in mix.n:
		mix.left[i] += wet_l[i] * params.echo_mix
		mix.right[i] += wet_r[i] * params.echo_mix


## Scales the peak to `peak_db`; a sting also gets 3 ms in and 20 ms out so it cannot click.
static func _finish(params: MusicParams, mix: Mix) -> void:
	var peak: float = 0.000001
	for i: int in mix.n:
		peak = maxf(peak, maxf(absf(mix.left[i]), absf(mix.right[i])))
	var scale: float = db_to_linear(params.peak_db) / peak
	var fade_in: int = int(0.003 * float(params.sample_rate))
	var fade_out: int = int(0.02 * float(params.sample_rate))
	for i: int in mix.n:
		var g: float = scale
		if not params.loop:
			g *= (
				minf(float(i) / float(fade_in), 1.0) * minf(float(mix.n - i) / float(fade_out), 1.0)
			)
		mix.left[i] *= g
		mix.right[i] *= g


static func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, float(midi - 69) / 12.0)


## The buffers of one render.
class Mix:
	extends RefCounted
	var n: int
	var left: PackedFloat32Array = PackedFloat32Array()
	var right: PackedFloat32Array = PackedFloat32Array()
	var send_left: PackedFloat32Array = PackedFloat32Array()
	var send_right: PackedFloat32Array = PackedFloat32Array()

	func _init(params: MusicParams) -> void:
		n = params.frames()
		left.resize(n)
		right.resize(n)
		send_left.resize(n)
		send_right.resize(n)
