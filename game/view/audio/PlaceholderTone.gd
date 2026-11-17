class_name PlaceholderTone
extends RefCounted
## A short synthesised tone for a cue that has no sound file yet (ADR 0041 section 7: audio made in
## this repository). Integer maths for the noise and no random generator, so a tone is the same
## every time.

const RATE: int = 22050


## A mono 16 bit tone of `hz` and `ms` with a falling envelope; `noise_permille` of its level is
## noise from a fixed linear congruential sequence.
static func make(hz: int, ms: int, noise_permille: int) -> AudioStreamWAV:
	var count: int = maxi(RATE * ms / 1000, 1)
	var data: PackedByteArray = PackedByteArray()
	data.resize(count * 2)
	var noise_state: int = hz * 7919 + 1
	var mix: float = float(noise_permille) / 1000.0
	for i: int in count:
		var tone: float = sin(TAU * float(hz) * float(i) / float(RATE))
		noise_state = (noise_state * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = float((noise_state >> 8) & 0xFFFF) / 32768.0 - 1.0
		var level: float = (tone * (1.0 - mix) + noise * mix) * (1.0 - float(i) / float(count))
		data.encode_s16(i * 2, int(clampf(level, -1.0, 1.0) * 12000.0))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream
