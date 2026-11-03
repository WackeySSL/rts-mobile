class_name IncomeRing
extends RefCounted
## The income the economy card shows as "+N/min" (ADR 0025 section 3, plan P119b): how much the
## player harvested over the last 60 s of match time, from the snapshots' `stat_harvested`. A ring
## of `SECONDS` one-second samples, allocated once; the match's own ticks are the clock, not the
## frame. `feed` takes the player's harvested total at a tick; the sample of a second is the first
## total seen in it. The figure is the total now less the sample taken 60 s ago, so it is what was
## harvested in the last minute; in the first minute it is what was harvested since the first
## sample, and no more (it is not scaled up to a rate). A snapshot that jumps several seconds fills
## the seconds it skipped on the straight line between the two totals. View state only: nothing is
## sent to the sim, and nothing here is in a hash.

const SECONDS: int = 60

var _ring: PackedInt32Array = PackedInt32Array()  ## Total at second `s`, in slot `s % SECONDS`.
var _second: int = -1  ## The last second sampled; -1 before the first sample.
var _per_minute: int = 0


func _init() -> void:
	_ring.resize(SECONDS)


## Harvested over the last 60 s (or since the first sample, in the first minute).
func per_minute() -> int:
	return _per_minute


## Forgets every sample: a new match.
func reset() -> void:
	_second = -1
	_per_minute = 0


## Takes the player's harvested total `harvested` at match tick `tick`. A tick in the same second as
## the last sample changes nothing.
@warning_ignore("integer_division")
func feed(tick: int, harvested: int) -> void:
	var second: int = tick / Sim.TICK_RATE
	if _second < 0 or second < _second:
		_ring.fill(harvested)  # No history: the first sample is every slot's, income 0.
		_second = second
		_per_minute = 0
		return
	if second == _second:
		return
	var back: int = _ring[second % SECONDS]  # The sample of 60 s ago, before it is overwritten.
	var span: int = second - _second
	if span >= SECONDS:
		_ring.fill(harvested)
		back = harvested
	else:
		var from: int = _ring[_second % SECONDS]
		for step: int in range(1, span + 1):
			_ring[(_second + step) % SECONDS] = from + (harvested - from) * step / span
	_second = second
	_per_minute = maxi(harvested - back, 0)
