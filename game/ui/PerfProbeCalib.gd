class_name PerfProbeCalib
extends RefCounted
## Spike P26n2 (ADR 0014 section 5, never merged): the perf probe's calibration numbers as pure
## static functions, so headless tests pin them. Pacing (ADR 0014 section 1): the period P, the
## slot V, `drop_ms`, dropped frames, cadence, hitches, the extra-slot histogram and the jitter
## share. Main-thread CPU (section 3): the reference loop, the burst's kept second half, and the two
## normalisations, the class method (one factor per frame class) and the per-frame method. Both
## multiply by min(1, ...), so neither can exceed the raw value.

const REF_ITERATIONS: int = 1000  ## ADR 0014 `ref_iterations`.
const BURST_USEC: int = 400000  ## ADR 0014 `ref_burst_ms`; the second half is kept.
const DROP_SLOTS: float = 0.5  ## A dropped frame: interval above P + 0.5 V.
const JITTER_MS: float = 17.5  ## The old on-time bound, diagnostic only.
const HITCH_USEC: int = 1000000 / Sim.TICK_RATE  ## One tick period: 66.7 ms.
const MEDIAN_FLOOR: float = 0.98  ## A median below P x 0.98 is INVALID (section 2, check C1).


## The pacing rows of one run; all times in ms.
class Pacing:
	var period_ms: float = 0.0
	var slot_ms: float = 0.0
	var drop_ms: float = 0.0
	var frames: int = 0
	var dropped: int = 0
	var dropped_pct: float = 0.0
	var cadence_pct: float = 0.0
	var hitches: int = 0
	var median_ms: float = 0.0
	var p99_ms: float = 0.0
	var max_ms: float = 0.0
	var jitter_pct: float = 0.0
	var slots: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])  ## Extra slots 0, 1, 2, >= 3.


## One main-thread class (all, tick, other or fog frames): its ref samples and work, raw and
## normalised both ways.
class Stats:
	var frames: int = 0
	var ref_span_us: float = 0.0  ## p25 of the class's ref samples.
	## p50 and p95 of the same samples: their spread is what the per-frame method also divides by.
	var ref_p50_us: float = 0.0
	var ref_p95_us: float = 0.0
	var speed_pct: float = 0.0  ## speed_main_pct = 100 x ref_peak / ref_span.
	var p95_raw: float = 0.0
	var p95_class: float = 0.0  ## Raw p95 x min(1, ref_peak / ref_span).
	var p95_frame: float = 0.0  ## p95 over frames of work_i x min(1, ref_peak / sample_i).
	var mean_raw: float = 0.0
	var mean_class: float = 0.0
	var mean_frame: float = 0.0


## P = 1000 / min(refresh_hz, max_fps); `max_fps` 0 (unlimited) counts as `refresh_hz`.
static func period_ms(refresh_hz: float, max_fps: int) -> float:
	return 1000.0 / (refresh_hz if max_fps <= 0 else minf(refresh_hz, float(max_fps)))


## V = 1000 / refresh_hz, one vsync slot.
static func slot_ms(refresh_hz: float) -> float:
	return 1000.0 / refresh_hz


static func drop_ms(refresh_hz: float, max_fps: int) -> float:
	return period_ms(refresh_hz, max_fps) + DROP_SLOTS * slot_ms(refresh_hz)


## 0 for an interval up to `drop`, else ceil((interval - drop) / slot): the vsync slots by which the
## interval exceeds P, rounded to the nearest with halves down (P + k V gives k). So an interval is
## a dropped frame exactly when it has at least one extra slot.
static func extra_slots(interval_ms: float, drop: float, slot: float) -> int:
	return 0 if interval_ms <= drop else ceili((interval_ms - drop) / slot)


## An interval of at least one tick period; the probe's intervals are whole microseconds.
static func is_hitch(interval_ms: float) -> bool:
	return roundi(interval_ms * 1000.0) >= HITCH_USEC


## Every pacing row of `intervals` (ms) at `refresh_hz` (> 0) and `max_fps`.
static func pacing(intervals: PackedFloat64Array, refresh_hz: float, max_fps: int) -> Pacing:
	var out: Pacing = Pacing.new()
	out.period_ms = period_ms(refresh_hz, max_fps)
	out.slot_ms = slot_ms(refresh_hz)
	out.drop_ms = drop_ms(refresh_hz, max_fps)
	out.frames = intervals.size()
	var calm: int = 0
	for ms: float in intervals:
		var extra: int = extra_slots(ms, out.drop_ms, out.slot_ms)
		out.slots[mini(extra, 3)] += 1
		out.dropped += int(extra > 0)
		out.hitches += int(is_hitch(ms))
		calm += int(ms <= JITTER_MS)
	var mean: float = PerfProbeTick.mean(intervals)
	out.cadence_pct = 100.0 * out.period_ms / mean if mean > 0.0 else 0.0
	out.dropped_pct = 100.0 * out.dropped / maxi(out.frames, 1)
	out.jitter_pct = 100.0 * calm / maxi(out.frames, 1)
	out.median_ms = PerfProbeTick.percentile(intervals, 50)
	out.p99_ms = PerfProbeTick.percentile(intervals, 99)
	out.max_ms = PerfProbeTick.percentile(intervals, 100)
	return out


## The fixed integer loop of ADR 0014 section 3 (PR #41's evidence, ref.gd).
static func ref_loop(n: int) -> int:
	var acc: int = 1
	for i: int in n:
		acc = (acc * 31 + i) & 0xFFFFFF
	return acc


## One timed reference run in microseconds.
static func ref_usec() -> int:
	var started: int = Time.get_ticks_usec()
	ref_loop(REF_ITERATIONS)
	return Time.get_ticks_usec() - started


## Runs `sampler` (returns usec) back to back for `usec` and returns the samples of the second half.
static func burst(usec: int, sampler: Callable) -> PackedFloat64Array:
	var samples: PackedFloat64Array = PackedFloat64Array()
	var starts: PackedInt64Array = PackedInt64Array()
	var begin: int = Time.get_ticks_usec()
	var at: int = begin
	while at - begin < usec:
		starts.append(at - begin)
		samples.append(sampler.call())
		at = Time.get_ticks_usec()
	return second_half(samples, starts, usec)


## The samples that started at or after half of a `usec` burst (`starts` in usec from its start).
static func second_half(
	samples: PackedFloat64Array, starts: PackedInt64Array, usec: int
) -> PackedFloat64Array:
	var kept: PackedFloat64Array = PackedFloat64Array()
	for i: int in samples.size():
		if starts[i] * 2 >= usec:
			kept.append(samples[i])
	return kept


## min(1, ref_peak / ref): the normalisation factor; 1 when either is unknown (0).
static func factor(ref_peak: float, ref: float) -> float:
	return minf(1.0, ref_peak / ref) if ref_peak > 0.0 and ref > 0.0 else 1.0


## A class's rows: `work` and `refs` are parallel (each work value with its frame's ref sample).
static func stats(work: PackedFloat64Array, refs: PackedFloat64Array, ref_peak: float) -> Stats:
	var out: Stats = Stats.new()
	var per_frame: PackedFloat64Array = PackedFloat64Array()
	for i: int in work.size():
		per_frame.append(work[i] * factor(ref_peak, refs[i]))
	out.frames = work.size()
	out.ref_span_us = PerfProbeTick.percentile(refs, 25)
	out.ref_p50_us = PerfProbeTick.percentile(refs, 50)
	out.ref_p95_us = PerfProbeTick.percentile(refs, 95)
	out.speed_pct = 100.0 * ref_peak / out.ref_span_us if out.ref_span_us > 0.0 else 0.0
	var by_class: float = factor(ref_peak, out.ref_span_us)
	out.p95_raw = PerfProbeTick.percentile(work, 95)
	out.p95_class = out.p95_raw * by_class
	out.p95_frame = PerfProbeTick.percentile(per_frame, 95)
	out.mean_raw = PerfProbeTick.mean(work)
	out.mean_class = out.mean_raw * by_class
	out.mean_frame = PerfProbeTick.mean(per_frame)
	return out
