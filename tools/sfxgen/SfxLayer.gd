class_name SfxLayer
extends Resource
## One voice of a generated sound (plan row P507, ADR 0041 section 7): an oscillator or noise, a
## frequency sweep, an ADSR envelope and an optional one-pole filter. All times are in seconds.

enum Wave { SINE, SQUARE, SAW, TRIANGLE, NOISE }

@export var wave: Wave = Wave.SINE
## Start and end frequency in Hz; the pitch glides exponentially between them over `length`.
@export_range(20.0, 20000.0) var freq: float = 440.0
@export_range(20.0, 20000.0) var freq_end: float = 440.0
## Pulse width of a square wave, 0.5 is symmetric.
@export_range(0.05, 0.95) var duty: float = 0.5
@export_range(0.0, 1.0) var amp: float = 0.5
## When the voice starts, and how long its envelope runs (attack + decay + hold + release).
@export var start: float = 0.0
@export var length: float = 0.2
@export var attack: float = 0.005
@export var decay: float = 0.05
@export_range(0.0, 1.0) var sustain: float = 0.6
@export var release: float = 0.05
## Filter cut-off in Hz, 0 = off.
@export var lowpass: float = 0.0
@export var highpass: float = 0.0


## The envelope at `t` seconds after the voice started (0 outside [0, length)).
func envelope(t: float) -> float:
	if t < 0.0 or t >= length:
		return 0.0
	var rel_start: float = maxf(length - release, 0.0)
	var level: float
	if t < attack:
		level = t / maxf(attack, 0.000001)
	elif t < attack + decay:
		level = lerpf(1.0, sustain, (t - attack) / maxf(decay, 0.000001))
	else:
		level = sustain
	if t >= rel_start:
		level *= 1.0 - (t - rel_start) / maxf(release, 0.000001)
	return clampf(level, 0.0, 1.0)
